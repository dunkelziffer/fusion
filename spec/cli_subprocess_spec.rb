# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tmpdir"

# Integration tests that drive the real `exe/fusion` binary as a subprocess.
#
# Most language behavior is specced in-process via the FusionHelpers harness;
# this file owns everything only observable at the real boundary: flag parsing,
# the stdout/stderr split and exit codes, the input/output modes, the NDJSON
# stream loop, the REPL session, and the top-level `rescue Exception` net. In
# particular, a stack overflow raises Ruby's SystemStackError (not a
# StandardError), which is converted to a payload only by that net; the
# in-process harness cannot model it (see error_kinds_spec.rb).
RSpec.describe "CLI (exe/fusion)" do
  ROOT = File.expand_path("..", __dir__)
  EXE  = File.join(ROOT, "exe", "fusion")
  FIX  = File.expand_path("fixtures", __dir__)

  let(:division_by_zero) do
    '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@divide","status":0,"input":[1,0],"message":"division by zero"}'
  end

  # Run the binary with the given args and stdin; returns [stdout, stderr, status].
  def run_cli(*args, stdin: "", chdir: nil)
    opts = { stdin_data: stdin }
    opts[:chdir] = chdir if chdir
    Open3.capture3(RbConfig.ruby, EXE, *args, **opts)
  end

  # Drop terminal control codes (and bare CRs) so the REPL's stderr — where the
  # prompt and the echoed input land — can be asserted as plain text.
  def strip_ansi(text)
    text.gsub(/\e\[[\d;?]*[ -\/]*[@-~]/, "").delete("\r")
  end

  describe "the result/error channel split" do
    it "prints the result to stdout and exits 0 on success" do
      out, err, status = run_cli(File.join(FIX, "fact.fsn"), stdin: "5")
      expect(out).to eq("120\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "prints only the payload to stderr (stdout empty) and exits 1 on error" do
      out, err, status = run_cli("-e", "(p => p | @divide)", stdin: "[1,0]")
      expect(out).to eq("")
      expect(err).to eq("#{division_by_zero}\n")
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "use case selection" do
    it "starts the REPL when run with no arguments at all" do
      out, _err, status = run_cli(stdin: "[1, 2, 3] | @size\n")
      expect(out).to eq("3\n")
      expect(status.exitstatus).to eq(0)
    end

    it "defaults to the pipe use case once any argument is given" do
      out, _err, status = run_cli("-e", "(n => [n, 1] | @OP.sum)", stdin: "5")
      expect(out).to eq("6\n")
      expect(status.exitstatus).to eq(0)
    end

    it "runs the pipe use case under an explicit --pipe" do
      out, _err, status = run_cli("--pipe", "-e", "(n => [n, 1] | @OP.sum)", stdin: "5")
      expect(out).to eq("6\n")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "short flags and repeated modes" do
    it "accepts the short forms of the use-case and mode flags" do
      out, _err, status = run_cli("-p", "-i", "array", "-o", "object", "-e", "(n => n)", stdin: "[0,5]")
      expect(out).to eq(%({"value":5}\n))
      expect(status.exitstatus).to eq(0)
    end

    it "accepts --execute as the long form of -e" do
      out, _err, status = run_cli("--execute", "(n => [n, 1] | @OP.sum)", stdin: "5")
      expect(out).to eq("6\n")
      expect(status.exitstatus).to eq(0)
    end

    it "allows a mode to be repeated with the same value" do
      out, _err, status = run_cli("-i", "array", "--input", "array", "-e", "(n => n)", stdin: "[0,5]")
      expect(out).to eq("5\n")
      expect(status.exitstatus).to eq(0)
    end

    it "rejects two different modes for the same direction" do
      _out, err, status = run_cli("--input", "array", "-i", "object", "-e", "(n => n)", stdin: "[0,5]")
      expect(err).to start_with("fusion: conflicting --input modes: array, object")
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "the pipe use case with no input" do
    it "emits the program's own value when stdin is empty" do
      out, err, status = run_cli("-e", "[1, [2, 3] | @OP.sum]")
      expect(out).to eq("[1,5]\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "still pipes stdin through the program when input is present" do
      out, _err, status = run_cli("-e", "(n => [n, 1] | @OP.sum)", stdin: "5")
      expect(out).to eq("6\n")
      expect(status.exitstatus).to eq(0)
    end

    it "reports a serialization_error when a bare program is itself a function" do
      _out, err, status = run_cli("-e", "(n => n)")
      expect(err).to include('"kind":"serialization_error"', '"origin":"output"')
      expect(status.exitstatus).to eq(1)
    end

    # With empty input meaning "no input", the value null is supplied by piping
    # the literal "null". We need to ensure, that we always output this
    # as "null" again and not as empty string, or our program won't chain properly.
    it "round-trips a piped null (NULL always serializes as null)" do
      out, _err, status = run_cli("-e", '(n => [n, {"k": n}])', stdin: "null")
      expect(out).to eq(%([null,{"k":null}]\n))
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "bare @ in inline (-e) source" do
    it "recurses through a bare @ when the unit is a function applied to stdin" do
      out, err, status = run_cli("-e", "(0 => [0], n ? @Integer => [n, ...([n,1] | @subtract | @)])", stdin: "3")
      expect(out).to eq("[3,2,1,0]\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "yields the unit's own function value (a serialization_error) when no stdin applies it" do
      out, err, status = run_cli("-e", "(0 => 1, n => [n, [n,1] | @subtract | @] | @OP.product)")
      expect(out).to eq("")
      expect(err).to eq(
        %({"kind":"serialization_error","origin":"output","operation":"serializing result","status":0,"input":"<function>","message":"cannot serialize a function"}\n)
      )
      expect(status.exitstatus).to eq(1)
    end

    it "reports a non-productive data cycle when a bare @ is forced in data position at load" do
      out, err, status = run_cli("-e", "[1, @]")
      expect(out).to eq("")
      expect(err).to eq(
        %({"kind":"reference_error","origin":"code","file":"<inline>","operation":"@","status":0,"input":null,"message":"non-productive data cycle"}\n)
      )
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "the jail (-j/--jail)" do
    it "defaults the jail to the program's directory, blocking an @../ escape" do
      out, err, status = run_cli(File.join(FIX, "ref", "sub", "usesParent.fsn"), stdin: "7")
      expect(out).to eq("")
      expect(err).to eq(
        %({"kind":"reference_error","origin":"code","file":"spec/fixtures/ref/sub/usesParent.fsn","operation":"@../helper","status":0,"input":null,"message":"outside the jail"}\n)
      )
      expect(status.exitstatus).to eq(1)
    end

    it "widens the jail with -j .. so the @../ reference resolves" do
      out, _err, status = run_cli("-j", "..", File.join(FIX, "ref", "sub", "usesParent.fsn"), stdin: "7")
      expect(out).to eq("[7,7]\n")
      expect(status.exitstatus).to eq(0)
    end

    it "confines inline (-e) source too, defaulting the jail to the working directory" do
      # @-refs in inline source resolve against the cwd, which is also the default
      # jail, so @../ escapes it.
      out, err, status = run_cli("-e", "(x => x | @../helper)", stdin: "7")
      expect(out).to eq("")
      expect(err).to eq(
        %({"kind":"reference_error","origin":"code","file":"<inline>","operation":"@../helper","status":0,"input":null,"message":"outside the jail"}\n)
      )
      expect(status.exitstatus).to eq(1)
    end

    it "disables confinement with -j '*'" do
      out, _err, status = run_cli("-j", "*", File.join(FIX, "ref", "sub", "usesParent.fsn"), stdin: "7")
      expect(out).to eq("[7,7]\n")
      expect(status.exitstatus).to eq(0)
    end

    it "rejects a --jail directory that does not exist (plain usage error)" do
      _out, err, status = run_cli("-j", "/no/such/dir", File.join(FIX, "ref", "sub", "usesParent.fsn"), stdin: "7")
      expect(err).to start_with("fusion: jail directory not found: /no/such/dir")
      expect(status.exitstatus).to eq(1)
    end

    it "accepts --jail with --repl" do
      out, _err, status = run_cli("--repl", "-j", ".", stdin: "[1, 2, 3] | @size\n")
      expect(out).to eq("3\n")
      expect(status.exitstatus).to eq(0)
    end

    it "enforces a non-default jail in the REPL (a sibling of the jail dir is blocked)" do
      Dir.mktmpdir do |tmp|
        Dir.mkdir(File.join(tmp, "sub"))
        File.write(File.join(tmp, "secret.fsn"), %("leaked"\n))
        # cwd = `tmp` (so @-refs resolve there)
        # jail = `tmp/sub`.
        # `@secret` resolves to `tmp/secret.fsn` (exists, but lies outside the jail)
        out, _err, status = run_cli("--repl", "-j", "sub", stdin: "@secret\n", chdir: tmp)
        expect(out).to eq(
          %(!{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@secret","status":0,"input":null,"message":"outside the jail"}\n)
        )
        expect(status.exitstatus).to eq(0)
      end
    end
  end

  describe "the top-level Ruby-error net" do
    it "converts a stack overflow (SystemStackError) into a limit_error payload" do
      out, err, status = run_cli(File.join(FIX, "loop.fsn"), stdin: "0")
      expect(out).to eq("")
      expect(err).to include(
        '"kind":"limit_error"', '"origin":"interpreter"', '"message":"stack level too deep"'
      )
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "boundary conversions also reachable in-process" do
    it "converts an inline parse error" do
      _out, err, status = run_cli("-e", "(_ => @", stdin: "null")
      expect(err).to include('"kind":"syntax_error"', '"origin":"code"')
      expect(status.exitstatus).to eq(1)
    end

    it "reports a function result as a serialization_error" do
      _out, err, status = run_cli("-e", "(n => (m => m))", stdin: "null")
      expect(err).to include('"kind":"serialization_error"', '"origin":"output"')
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "usage errors (plain text, before the input/output contract)" do
    it "rejects a missing program" do
      out, err, status = run_cli("--pipe")
      expect(out).to eq("")
      expect(err).to start_with("fusion: missing program")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects passing more than one use case" do
      _out, err, status = run_cli("--stream", "--repl", "-e", "(n => n)")
      expect(err).to start_with("fusion: choose one use case")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects an unknown option" do
      _out, err, status = run_cli("--frobnicate", "-e", "(n => n)")
      expect(err).to start_with("fusion: unknown option --frobnicate")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects an unknown mode" do
      _out, err, status = run_cli("--input", "nope", "-e", "(n => n)")
      expect(err).to start_with("fusion: --input expects one of: unix, bang, array, object")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects the unix mode for --stream" do
      _out, err, status = run_cli("--stream", "--input", "unix", "-e", "(n => n)")
      expect(err).to start_with("fusion: --stream does not support the unix mode")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects an input argument for --stream when -e is already given" do
      _out, err, status = run_cli("--stream", "-e", "(n => n)", "1")
      expect(err).to start_with("fusion: too many positional arguments")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects an input argument for --pipe when -e is already given" do
      _out, err, status = run_cli("-e", "(n => n)", "1")
      expect(err).to start_with("fusion: too many positional arguments")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects --skip-blank-lines outside --stream" do
      _out, err, status = run_cli("--skip-blank-lines", "-e", "(n => n)")
      expect(err).to start_with("fusion: --skip-blank-lines is only for --stream")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects a program, input, or modes for --repl" do
      _out, err, status = run_cli("--repl", "-e", "(n => n)")
      expect(err).to start_with("fusion: --repl takes no program, no input, and no modes")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects -! when the input mode is not unix" do
      _out, err, status = run_cli("-!", "--input", "bang", "-e", "(n => n)")
      expect(err).to start_with("fusion: -! requires the unix input mode")
      expect(status.exitstatus).to eq(1)
    end

    it "prints the usage on --help and exits 0" do
      out, err, status = run_cli("--help")
      expect(out).to start_with("usage: fusion")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "the -! flag (the input is an error value)" do
    it "feeds the input to the program as an error" do
      out, err, status = run_cli("-!", "-e", "(!payload => payload)", stdin: "42")
      expect(out).to eq("42\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "propagates the input error when no clause catches it (binders never capture errors)" do
      out, err, status = run_cli("-!", "-e", "(n => n)", stdin: "42")
      expect(out).to eq("")
      expect(err).to eq("42\n")
      expect(status.exitstatus).to eq(1)
    end

    # -! with empty stdin has no payload to mark. Unlike a wrong-mode -!, this is
    # only catchable while reading input, but it is still a usage error: plain
    # text on stderr (stdout empty), never a payloaded Fusion error.
    it "rejects empty input as a usage error (nothing to mark)" do
      out, err, status = run_cli("-!", "-e", "(n => n)")
      expect(out).to eq("")
      expect(err).to start_with("fusion: -! requires input to mark as an error, but stdin was empty")
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "the bang input mode" do
    it "reads plain JSON as a value" do
      out, _err, status = run_cli("--input", "bang", "-e", "(n => n)", stdin: "5")
      expect(out).to eq("5\n")
      expect(status.exitstatus).to eq(0)
    end

    it "reads a leading ! as an error value" do
      out, _err, status = run_cli("--input", "bang", "-e", "(!payload => payload)", stdin: '!"boom"')
      expect(out).to eq("\"boom\"\n")
      expect(status.exitstatus).to eq(0)
    end

    it "reads a lone ! as the error !null" do
      out, _err, status = run_cli("--input", "bang", "-e", '(!null => "caught bare error")', stdin: "!")
      expect(out).to eq("\"caught bare error\"\n")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "the array input mode" do
    it "unwraps [0, value] into the value" do
      out, _err, status = run_cli("--input", "array", "-e", "(n => n)", stdin: "[0, 5]")
      expect(out).to eq("5\n")
      expect(status.exitstatus).to eq(0)
    end

    it "unwraps [1, payload] into an error value" do
      out, _err, status = run_cli("--input", "array", "-e", "(!payload => payload)", stdin: '[1, "boom"]')
      expect(out).to eq("\"boom\"\n")
      expect(status.exitstatus).to eq(0)
    end

    it "turns a malformed envelope into a catchable argument_error" do
      out, err, status = run_cli("--input", "array", "-e", "(n => n)", stdin: "[2, 5]")
      expect(out).to eq("")
      expect(err).to eq(
        %({"kind":"argument_error","origin":"input","operation":"decoding input","status":0,"input":[2,5],"expected":["[0, _]","[1, _]"]}\n)
      )
      expect(status.exitstatus).to eq(1)
    end

    it "requires the tag to be exactly the integer 0 or 1" do
      _out, err, status = run_cli("--input", "array", "-e", "(n => n)", stdin: "[0.0, 5]")
      expect(err).to include('"kind":"argument_error"', '"input":[0.0,5]')
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "the object input mode" do
    it 'unwraps {"value": _} into the value' do
      out, _err, status = run_cli("--input", "object", "-e", "(n => n)", stdin: '{"value": 5}')
      expect(out).to eq("5\n")
      expect(status.exitstatus).to eq(0)
    end

    it 'unwraps {"error": _} into an error value' do
      out, _err, status = run_cli("--input", "object", "-e", "(!payload => payload)", stdin: '{"error": "boom"}')
      expect(out).to eq("\"boom\"\n")
      expect(status.exitstatus).to eq(0)
    end

    it "turns an envelope with extra keys into a catchable argument_error" do
      _out, err, status = run_cli("--input", "object", "-e", "(n => n)", stdin: '{"value": 1, "extra": 2}')
      expect(err).to eq(
        %({"kind":"argument_error","origin":"input","operation":"decoding input","status":0,"input":{"value":1,"extra":2},"expected":["{\\"value\\": _}","{\\"error\\": _}"]}\n)
      )
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "the bang output mode" do
    it "prints a value plainly and exits 0" do
      out, err, status = run_cli("--output", "bang", "-e", "(n => n)", stdin: "5")
      expect(out).to eq("5\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "prints an error as !payload on stdout and still exits 0" do
      out, err, status = run_cli("--output", "bang", "-e", "(p => p | @divide)", stdin: "[1,0]")
      expect(out).to eq("!#{division_by_zero}\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "keeps a serialization_error in-band" do
      out, err, status = run_cli("--output", "bang", "-e", "(n => (m => m))", stdin: "null")
      expect(out).to eq(
        %(!{"kind":"serialization_error","origin":"output","operation":"serializing result","status":0,"input":"<function>","message":"cannot serialize a function"}\n)
      )
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "the array output mode" do
    it "wraps a value as [0, value]" do
      out, _err, status = run_cli("--output", "array", "-e", "(n => n)", stdin: "5")
      expect(out).to eq("[0,5]\n")
      expect(status.exitstatus).to eq(0)
    end

    it "wraps an error as [1, payload]" do
      out, err, status = run_cli("--output", "array", "-e", "(p => p | @divide)", stdin: "[1,0]")
      expect(out).to eq("[1,#{division_by_zero}]\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "the object output mode" do
    it 'wraps a value as {"value": _}' do
      out, _err, status = run_cli("--output", "object", "-e", "(n => n)", stdin: "5")
      expect(out).to eq(%({"value":5}\n))
      expect(status.exitstatus).to eq(0)
    end

    it 'wraps an error as {"error": _}' do
      out, err, status = run_cli("--output", "object", "-e", "(p => p | @divide)", stdin: "[1,0]")
      expect(out).to eq(%({"error":#{division_by_zero}}\n))
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "keeps the top-level net's limit_error in-band" do
      out, err, status = run_cli("--output", "object", File.join(FIX, "loop.fsn"), stdin: "0")
      expect(out).to eq(
        %({"error":{"kind":"limit_error","origin":"interpreter","operation":"running the program","status":0,"input":null,"message":"stack level too deep"}}\n)
      )
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "mode independence" do
    it "combines --input array with --output object" do
      out, _err, status = run_cli(
        "--input", "array", "--output", "object", "-e", '(!payload => ["caught", payload])', stdin: '[1, "boom"]'
      )
      expect(out).to eq(%({"value":["caught","boom"]}\n))
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "--stream" do
    it "pipes each NDJSON line through the program and exits 0 (array, the default)" do
      out, err, status = run_cli("--stream", File.join(FIX, "double.fsn"), stdin: "[0,1]\n[0,2]\n[0,3]\n")
      expect(out).to eq("[0,2]\n[0,4]\n[0,6]\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "accepts both LF and CRLF line delimiters (NDJSON)" do
      out, _err, status = run_cli("--stream", File.join(FIX, "double.fsn"), stdin: "[0,1]\r\n[0,2]\n")
      expect(out).to eq("[0,2]\n[0,4]\n")
      expect(status.exitstatus).to eq(0)
    end

    it "echoes blank lines as blank output lines by default (no computation)" do
      out, _err, status = run_cli("--stream", File.join(FIX, "double.fsn"), stdin: "[0,1]\n\n[0,2]\n")
      expect(out).to eq("[0,2]\n\n[0,4]\n")
      expect(status.exitstatus).to eq(0)
    end

    it "drops blank lines with --skip-blank-lines" do
      out, _err, status = run_cli(
        "--stream", "--skip-blank-lines", File.join(FIX, "double.fsn"), stdin: "[0,1]\n\n[0,2]\n"
      )
      expect(out).to eq("[0,2]\n[0,4]\n")
      expect(status.exitstatus).to eq(0)
    end

    it "defaults both sides to the array mode" do
      out, _err, status = run_cli(
        "--stream", "-e", '(!payload => ["was", payload], n => n)', stdin: %([0,1]\n[1,"boom"]\n)
      )
      expect(out).to eq(%([0,1]\n[0,["was","boom"]]\n))
      expect(status.exitstatus).to eq(0)
    end

    it "keeps a per-record error in-band and continues the stream" do
      out, err, status = run_cli("--stream", "-e", "(p => p | @divide)", stdin: "[0,[4,2]]\n[0,[1,0]]\n[0,[9,3]]\n")
      expect(out).to eq("[0,2.0]\n[1,#{division_by_zero}]\n[0,3.0]\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "keeps a per-record stack overflow in-band and continues the stream" do
      limit_error =
        '{"kind":"limit_error","origin":"interpreter","operation":"running the program","status":0,"input":null,"message":"stack level too deep"}'
      out, err, status = run_cli("--stream", File.join(FIX, "loop.fsn"), stdin: "[0,0]\n[0,1]\n")
      expect(out).to eq("[1,#{limit_error}]\n[1,#{limit_error}]\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "still supports the bang mode as the cheapest Fusion-to-Fusion encoding" do
      out, _err, status = run_cli(
        "--stream", "--input", "bang", "--output", "bang",
        "-e", '(!payload => !["was", payload], n => n)', stdin: %(1\n!"boom"\n)
      )
      expect(out).to eq(%(1\n!["was","boom"]\n))
      expect(status.exitstatus).to eq(0)
    end

    it "combines --input array with --output object" do
      out, _err, status = run_cli(
        "--stream", "--input", "array", "--output", "object", "-e", "(!payload => payload, n => [n, 2] | @OP.product)",
        stdin: %([0,5]\n[1,"boom"]\n)
      )
      expect(out).to eq(%({"value":10}\n{"value":"boom"}\n))
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "UTF-8 input and output" do
    it "round-trips a non-ASCII string through the pipe, unescaped" do
      out, _err, status = run_cli("-e", "(s => s)", stdin: '"héllo ✓ 日本"')
      expect(out).to eq(%("héllo ✓ 日本"\n))
      expect(status.exitstatus).to eq(0)
    end

    it "decodes the input as UTF-8 characters, not bytes" do
      # "héllo ✓ 日本" is 10 characters but 17 bytes; @size must count characters.
      out, _err, status = run_cli("-e", "(s => s | @size)", stdin: '"héllo ✓ 日本"')
      expect(out).to eq("10\n")
      expect(status.exitstatus).to eq(0)
    end

    it "round-trips non-ASCII through the NDJSON stream" do
      out, _err, status = run_cli("--stream", "-e", "(s => s)", stdin: %([0,"日本 ✓"]\n))
      expect(out).to eq(%([0,"日本 ✓"]\n))
      expect(status.exitstatus).to eq(0)
    end
  end

  # The REPL's parse/evaluate/bind semantics are specced in-process (see
  # repl_spec.rb). These boundary tests confirm only what driving the real
  # Reline-backed binary proves: entries are read from stdin over one session,
  # results form a clean stdout stream, and the interactive UI lands on stderr.
  describe "--repl" do
    it "evaluates statements over one session, printing clean results to stdout" do
      out, _err, status = run_cli("--repl", stdin: "x = 5\ny = [x, 1] | @OP.sum\n")
      expect(out).to eq("5\n6\n")
      expect(status.exitstatus).to eq(0)
    end

    it "evaluates a bare expression" do
      out, _err, status = run_cli("--repl", stdin: "[1, 2, 3] | @size\n")
      expect(out).to eq("3\n")
      expect(status.exitstatus).to eq(0)
    end

    it "completes a multi-line entry once it parses (no terminator needed)" do
      out, _err, status = run_cli("--repl", stdin: "[\n  10,\n  20\n]\n")
      expect(out).to eq("[10,20]\n")
      expect(status.exitstatus).to eq(0)
    end

    it "keeps stdout clean and renders the prompts on stderr" do
      out, err, status = run_cli("--repl", stdin: "x = [\n  1\n]\n")
      expect(out).to eq("[1]\n")
      expect(strip_ansi(err)).to include("fsn> ", "...> ") # first line, then continuations
      expect(status.exitstatus).to eq(0)
    end
  end
end
