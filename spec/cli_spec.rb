# frozen_string_literal: true

require "open3"
require "rbconfig"

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
    '{"kind":"math_error","location":"builtin divide","operation":"divide","input":[1,0],"message":"division by zero"}'
  end

  # Run the binary with the given args and stdin; returns [stdout, stderr, status].
  def run_cli(*args, stdin: "")
    Open3.capture3(RbConfig.ruby, EXE, *args, stdin_data: stdin)
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

  describe "the top-level Ruby-error net" do
    it "converts a stack overflow (SystemStackError) into a stack_error payload" do
      out, err, status = run_cli(File.join(FIX, "loop.fsn"), stdin: "0")
      expect(out).to eq("")
      expect(err).to include(
        '"kind":"stack_error"', '"location":"interpreter"', '"message":"recursion too deep"'
      )
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "boundary conversions also reachable in-process" do
    it "converts an inline parse error" do
      _out, err, status = run_cli("-e", "(_ => @", stdin: "null")
      expect(err).to include('"kind":"syntax_error"', '"location":"code <inline>"')
      expect(status.exitstatus).to eq(1)
    end

    it "reports a function result as a serialization_error" do
      _out, err, status = run_cli("-e", "(n => (m => m))", stdin: "null")
      expect(err).to include('"kind":"serialization_error"', '"location":"output"')
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "usage errors (plain text, before the input/output contract)" do
    it "rejects a missing program" do
      out, err, status = run_cli
      expect(out).to eq("")
      expect(err).to start_with("fusion: missing program")
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

    it "rejects an input argument for --stream" do
      _out, err, status = run_cli("--stream", "-e", "(n => n)", "1")
      expect(err).to start_with("fusion: --stream reads its input from stdin")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects a program, input, or modes for --repl" do
      _out, err, status = run_cli("--repl", "-e", "(n => n)")
      expect(err).to start_with("fusion: --repl takes no program, no input, and no modes")
      expect(status.exitstatus).to eq(1)
    end

    it "rejects -! when the input mode is not unix" do
      _out, err, status = run_cli("-!", "--input", "bang", "-e", "(n => n)", "1")
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
      out, err, status = run_cli("-!", "-e", "(!payload => payload)", "42")
      expect(out).to eq("42\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "propagates the input error when no clause catches it (binders never capture errors)" do
      out, err, status = run_cli("-!", "-e", "(n => n)", "42")
      expect(out).to eq("")
      expect(err).to eq("42\n")
      expect(status.exitstatus).to eq(1)
    end

    it "turns empty input into the error !null" do
      out, _err, status = run_cli("-!", "-e", '(!null => "caught bare error")')
      expect(out).to eq("\"caught bare error\"\n")
      expect(status.exitstatus).to eq(0)
    end

    it "still accepts a negative number as the input argument" do
      out, _err, status = run_cli("-e", "(n => n)", "-5")
      expect(out).to eq("-5\n")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "the bang input mode" do
    it "reads plain JSON as a value" do
      out, _err, status = run_cli("--input", "bang", "-e", "(n => n)", stdin: "5")
      expect(out).to eq("5\n")
      expect(status.exitstatus).to eq(0)
    end

    it "reads a leading ! as an error value" do
      out, _err, status = run_cli("--input", "bang", "-e", "(!payload => payload)", '!"boom"')
      expect(out).to eq("\"boom\"\n")
      expect(status.exitstatus).to eq(0)
    end

    it "reads a lone ! as the error !null" do
      out, _err, status = run_cli("--input", "bang", "-e", '(!null => "caught bare error")', "!")
      expect(out).to eq("\"caught bare error\"\n")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "the array input mode" do
    it "unwraps [0, value] into the value" do
      out, _err, status = run_cli("--input", "array", "-e", "(n => n)", "[0, 5]")
      expect(out).to eq("5\n")
      expect(status.exitstatus).to eq(0)
    end

    it "unwraps [1, payload] into an error value" do
      out, _err, status = run_cli("--input", "array", "-e", "(!payload => payload)", '[1, "boom"]')
      expect(out).to eq("\"boom\"\n")
      expect(status.exitstatus).to eq(0)
    end

    it "turns a malformed envelope into a catchable argument_error" do
      out, err, status = run_cli("--input", "array", "-e", "(n => n)", "[2, 5]")
      expect(out).to eq("")
      expect(err).to eq(
        %({"kind":"argument_error","location":"input","operation":"decoding input","input":[2,5],"message":"expected [0, _] or [1, _]"}\n)
      )
      expect(status.exitstatus).to eq(1)
    end

    it "requires the tag to be exactly the integer 0 or 1" do
      _out, err, status = run_cli("--input", "array", "-e", "(n => n)", "[0.0, 5]")
      expect(err).to include('"kind":"argument_error"', '"input":[0.0,5]')
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "the object input mode" do
    it 'unwraps {"value": _} into the value' do
      out, _err, status = run_cli("--input", "object", "-e", "(n => n)", '{"value": 5}')
      expect(out).to eq("5\n")
      expect(status.exitstatus).to eq(0)
    end

    it 'unwraps {"error": _} into an error value' do
      out, _err, status = run_cli("--input", "object", "-e", "(!payload => payload)", '{"error": "boom"}')
      expect(out).to eq("\"boom\"\n")
      expect(status.exitstatus).to eq(0)
    end

    it "turns an envelope with extra keys into a catchable argument_error" do
      _out, err, status = run_cli("--input", "object", "-e", "(n => n)", '{"value": 1, "extra": 2}')
      expect(err).to eq(
        %({"kind":"argument_error","location":"input","operation":"decoding input","input":{"value":1,"extra":2},"message":"expected {\\"value\\": _} or {\\"error\\": _}"}\n)
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
        %(!{"kind":"serialization_error","location":"output","operation":"serializing result","input":"<function>","message":"cannot serialize a function"}\n)
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

    it "keeps the top-level net's stack_error in-band" do
      out, err, status = run_cli("--output", "object", File.join(FIX, "loop.fsn"), stdin: "0")
      expect(out).to eq(
        %({"error":{"kind":"stack_error","location":"interpreter","operation":"running the program","input":null,"message":"recursion too deep"}}\n)
      )
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "mode independence" do
    it "combines --input array with --output object" do
      out, _err, status = run_cli(
        "--input", "array", "--output", "object", "-e", '(!payload => ["caught", payload])', '[1, "boom"]'
      )
      expect(out).to eq(%({"value":["caught","boom"]}\n))
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "--stream" do
    it "pipes each NDJSON line through the program and exits 0" do
      out, err, status = run_cli("--stream", File.join(FIX, "double.fsn"), stdin: "1\n2\n3\n")
      expect(out).to eq("2\n4\n6\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "skips blank lines" do
      out, _err, status = run_cli("--stream", File.join(FIX, "double.fsn"), stdin: "1\n\n2\n")
      expect(out).to eq("2\n4\n")
      expect(status.exitstatus).to eq(0)
    end

    it "defaults both sides to the bang mode" do
      out, _err, status = run_cli("--stream", "-e", '(!payload => !["was", payload], n => n)', stdin: %(1\n!"boom"\n))
      expect(out).to eq(%(1\n!["was","boom"]\n))
      expect(status.exitstatus).to eq(0)
    end

    it "keeps a per-record error in-band and continues the stream" do
      out, err, status = run_cli("--stream", "-e", "(p => p | @divide)", stdin: "[4,2]\n[1,0]\n[9,3]\n")
      expect(out).to eq("2\n!#{division_by_zero}\n3\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "keeps a per-record stack overflow in-band and continues the stream" do
      stack_error =
        '{"kind":"stack_error","location":"interpreter","operation":"running the program","input":null,"message":"recursion too deep"}'
      out, err, status = run_cli("--stream", File.join(FIX, "loop.fsn"), stdin: "0\n1\n")
      expect(out).to eq("!#{stack_error}\n!#{stack_error}\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "combines --input array with --output object" do
      out, _err, status = run_cli(
        "--stream", "--input", "array", "--output", "object", "-e", "(!payload => payload, n => [n, 2] | @multiply)",
        stdin: %([0,5]\n[1,"boom"]\n)
      )
      expect(out).to eq(%({"value":10}\n{"value":"boom"}\n))
      expect(status.exitstatus).to eq(0)
    end
  end

  describe "--repl" do
    it "evaluates each statement, prints its value, and binds the identifier" do
      out, err, status = run_cli("--repl", stdin: "x = 5;\ny = [x, 1] | @add;\n")
      expect(out).to eq("5\n6\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "renders a function leniently" do
      out, _err, status = run_cli("--repl", stdin: "double = (n => [n, 2] | @multiply);\n")
      expect(out).to eq("\"<function>\"\n")
      expect(status.exitstatus).to eq(0)
    end

    it "lets a statement span lines until the terminating semicolon" do
      out, _err, status = run_cli("--repl", stdin: "x = [\n  1,\n  2\n];\n")
      expect(out).to eq("[1,2]\n")
      expect(status.exitstatus).to eq(0)
    end

    it "supports recursion through the bound name" do
      statements = <<~REPL
        fact = (
          0 => 1,
          n => [n, [n, 1] | @subtract | fact] | @multiply
        );
        x = 5 | fact;
      REPL
      out, _err, status = run_cli("--repl", stdin: statements)
      expect(out).to eq("\"<function>\"\n120\n")
      expect(status.exitstatus).to eq(0)
    end

    it "prints an error without binding the identifier" do
      out, err, status = run_cli("--repl", stdin: "bad = [1, 0] | @divide;\nprobe = bad;\n")
      expect(out).to eq(
        "!#{division_by_zero}\n" +
        %(!{"kind":"binding_error","location":"code <inline>","operation":"reading identifier bad","input":"bad","message":"unbound identifier"}\n)
      )
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "allows rebinding a name" do
      out, _err, status = run_cli("--repl", stdin: "x = 1;\nx = 2;\ny = x;\n")
      expect(out).to eq("1\n2\n2\n")
      expect(status.exitstatus).to eq(0)
    end

    it "recovers from a syntax error and continues the session" do
      out, _err, status = run_cli("--repl", stdin: "x = ;\nx = 1;\n")
      lines = out.lines
      expect(lines[0]).to include('"kind":"syntax_error"', '"location":"code <inline>"')
      expect(lines[1]).to eq("1\n")
      expect(status.exitstatus).to eq(0)
    end

    it "rejects a bare expression (only statements are accepted)" do
      out, _err, status = run_cli("--repl", stdin: "[1, 2] | @length;\n")
      expect(out).to include('"kind":"syntax_error"')
      expect(status.exitstatus).to eq(0)
    end

    it "survives a stack overflow and continues the session" do
      out, err, status = run_cli("--repl", stdin: "loop = (n => n | loop);\na = 1 | loop;\nb = \"alive\";\n")
      expect(out).to eq(
        "\"<function>\"\n" +
        %(!{"kind":"stack_error","location":"interpreter","operation":"running the statement","input":null,"message":"recursion too deep"}\n) +
        "\"alive\"\n"
      )
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end
  end
end
