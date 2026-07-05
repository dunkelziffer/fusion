# frozen_string_literal: true

require "stringio"

# Unit tests for `Fusion::CLI` — the programmatic interface for embedding Fusion
# as a library. The end-to-end behavior of the real `exe/fusion` binary (flag
# parsing, the stdout/stderr/exit contract) lives in cli_subprocess_spec.rb; here
# each public method is exercised directly against its own input/output types.
RSpec.describe Fusion::CLI do
  def parse_entry(source) = Fusion::Parser.parse_repl(source, site: { origin: "code", file: "<inline>" })

  # Run a block with `$stdin`/`$stdout` swapped for in-memory streams; returns
  # whatever was written to `$stdout`.
  def with_stdio(stdin:)
    original_in = $stdin
    original_out = $stdout
    $stdin = StringIO.new(stdin)
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdin = original_in
    $stdout = original_out
  end

  describe ".prepare!" do
    it "enables sync and sets UTF-8 on the standard streams" do
      was_sync = $stdout.sync
      $stdout.sync = false

      described_class.prepare!

      expect($stdout.sync).to be(true)
      expect($stderr.sync).to be(true)
      expect($stdin.external_encoding).to eq(Encoding::UTF_8)
    ensure
      $stdout.sync = was_sync
    end
  end

  describe ".run" do
    it "routes the :pipe use case to #run_pipe" do
      options = Fusion::CLI::Options.parse(["-e", "(n => n)"])
      expect(described_class).to receive(:run_pipe).with(options)
      described_class.run(options)
    end

    it "routes the :stream use case to #run_stream" do
      options = Fusion::CLI::Options.parse(["--stream", "-e", "(n => n)"])
      expect(described_class).to receive(:run_stream).with(options)
      described_class.run(options)
    end

    it "routes the :repl use case to #run_repl" do
      options = Fusion::CLI::Options.parse(["--repl"])
      expect(described_class).to receive(:run_repl).with(options)
      described_class.run(options)
    end

    it "raises Unreachable for an unknown use case" do
      expect { described_class.run(double(use_case: :bogus)) }.to raise_error(Fusion::Unreachable)
    end
  end

  describe ".run_pipe" do
    before { allow(described_class).to receive(:prepare!) }

    it "applies the program to the decoded stdin and emits the result" do
      options = Fusion::CLI::Options.parse(["-e", "(n => [n, 1] | @OP.sum)"])
      allow(described_class).to receive(:load_input).and_return(Fusion::WirePair.new(status: 0, data: "5"))
      emitted = nil
      allow(described_class).to receive(:emit_output) { |wire, **| emitted = wire }

      described_class.run_pipe(options)

      expect(emitted.data).to eq("6")
    end

    it "emits the program's own value when there is no input" do
      options = Fusion::CLI::Options.parse(["-e", "[1, [2, 3] | @OP.sum]"])
      allow(described_class).to receive(:load_input).and_return(nil)
      emitted = nil
      allow(described_class).to receive(:emit_output) { |wire, **| emitted = wire }

      described_class.run_pipe(options)

      expect(emitted.data).to eq("[1,5]")
    end
  end

  describe ".run_stream" do
    it "transforms each NDJSON record through the program" do
      options = Fusion::CLI::Options.parse(["--stream", "-e", "(n => [n, 1] | @OP.sum)"])
      allow(described_class).to receive(:prepare!)

      output = with_stdio(stdin: "[0,5]\n[0,9]\n") { described_class.run_stream(options) }

      expect(output).to eq("[0,6]\n[0,10]\n")
    end
  end

  describe ".run_repl" do
    it "starts a REPL on a root environment jailed to the working directory" do
      options = Fusion::CLI::Options.parse(["--repl"])
      repl = instance_double(Fusion::CLI::Repl, run: nil)
      root = nil
      expect(Fusion::CLI::Repl).to receive(:new) { |root_env:|
        root = root_env
        repl
      }

      described_class.run_repl(options)

      expect(root.context(:jail)).to eq(Dir.pwd)
    end
  end

  describe ".decode" do
    it "decodes an array-mode value record into a WirePair" do
      wire = described_class.decode("[0,5]", mode: :array)
      expect([wire.status, wire.data]).to eq([0, "5"])
    end

    it "decodes a bang-mode error record into a status-1 WirePair" do
      wire = described_class.decode(%(!"boom"), mode: :bang)
      expect([wire.status, wire.data]).to eq([1, %("boom")])
    end
  end

  describe ".parse" do
    it "parses a value WirePair into a runtime value" do
      expect(described_class.parse(Fusion::WirePair.new(status: 0, data: "5"))).to eq(5)
    end

    it "parses an error WirePair into an error value" do
      result = described_class.parse(Fusion::WirePair.new(status: 1, data: %("boom")))
      expect(result).to be_a(Fusion::Interpreter::ErrorVal)
    end
  end

  describe ".root_environment" do
    it "returns a binding-free root carrying the given jail" do
      env = described_class.root_environment(jail: "/some/dir")
      expect(env.context(:jail)).to eq("/some/dir")
      expect(env.parent).to be_nil
      expect(env.lookup("anything")).to eq(:__unbound__)
    end

    it "defaults the jail to the working directory" do
      expect(described_class.root_environment.context(:jail)).to eq(Dir.pwd)
    end
  end

  describe ".load_source" do
    it "evaluates inline source to a runtime value" do
      result = described_class.load_source("[1, [2, 3] | @OP.sum]", described_class.root_environment)
      expect(result).to eq([1, 5])
    end

    it "returns a syntax_error value for unparseable source" do
      result = described_class.load_source("(_ => @", described_class.root_environment)
      expect(described_class.serialize(result).data).to include('"kind":"syntax_error"')
    end
  end

  describe ".load_file" do
    it "loads a file's value, resolving the path against the working directory" do
      result = described_class.load_file("spec/fixtures/ref/data.config.fsn", described_class.root_environment)
      expect(described_class.serialize(result).data).to eq('{"setting":"on"}')
    end

    # The top-level program is loaded by the runtime itself, not via an @-reference,
    # so a read failure here reports the runtime's own operation — "loading code" —
    # with the path it was asked to load as `input` (and no `file`: no code referred
    # to it). This is the one place that operation surfaces.
    it "reports an unreadable program as a 'loading code' reference_error naming the path" do
      result = described_class.load_file("spec/fixtures/does_not_exist.fsn", described_class.root_environment)
      expect(described_class.serialize(result).data).to eq(
        '{"kind":"reference_error","origin":"code","operation":"loading code","status":0,"input":"spec/fixtures/does_not_exist.fsn","message":"file not found"}',
      )
    end
  end

  # A function is applied in its *own* closure. The environment passed to #apply
  # supplies the run's root (for file isolation) and the jail — not bindings.
  # Making the passed environment's bindings visible would be a new feature; these
  # specs pin down that it does not happen today.
  describe ".apply" do
    it "applies the function in its own closure, ignoring the passed environment's bindings" do
      closure = described_class.root_environment
      closure.bind("x", 1, checked: false)             # captured where the function is defined
      fn = described_class.evaluate(parse_entry("(_ => x)"), closure)

      environment = described_class.root_environment
      environment.bind("x", 2, checked: false)         # passed to #apply, but not consulted

      expect(described_class.apply(Fusion::NULL, fn, environment: environment)).to eq(1)
    end

    it "does not resolve a function's free identifier from the passed environment" do
      fn = described_class.evaluate(parse_entry("(_ => y)"), described_class.root_environment)

      environment = described_class.root_environment
      environment.bind("y", 99, checked: false)        # binds y, but #apply won't see it

      result = described_class.apply(Fusion::NULL, fn, environment: environment)

      expect(described_class.serialize(result).data).to eq(
        '{"kind":"binding_error","origin":"code","file":"<inline>","operation":"reading identifier y","status":0,"input":"y","message":"unbound identifier"}',
      )
    end

    # The mirror of the above: bindings come from the closure, but the *jail* comes
    # from the passed environment. The function is defined in an unconfined closure,
    # so the block below can only come from the jailed environment passed to #apply.
    it "confines @-resolution with the passed environment's jail, not the closure's" do
      fn = described_class.evaluate(
        parse_entry('(_ => "/nope/x.fsn" | @load)'),
        described_class.root_environment(jail: nil), # unconfined closure
      )

      jailed = described_class.root_environment(jail: Dir.pwd) # tight jail: the working dir
      result = described_class.apply(Fusion::NULL, fn, environment: jailed)

      expect(described_class.serialize(result).data).to eq(
        '{"kind":"reference_error","origin":"builtin","file":"<inline>","operation":"@load","status":0,"input":"/nope/x.fsn","message":"outside the jail"}',
      )
    end
  end

  describe ".evaluate" do
    it "evaluates an expression to a value" do
      result = described_class.evaluate(parse_entry("[1, 2, 3] | @size"), described_class.root_environment)
      expect(result).to eq(3)
    end

    it "binds an assignment's name on the environment and returns the value" do
      environment = described_class.root_environment
      expect(described_class.evaluate(parse_entry("x = 5"), environment)).to eq(5)
      expect(environment.lookup("x")).to eq(5)
    end

    it "raises Unreachable for a node that is neither an expression nor an assignment" do
      expect { described_class.evaluate(Object.new, described_class.root_environment) }
        .to raise_error(Fusion::Unreachable)
    end
  end

  describe ".serialize" do
    it "serializes a value into a status-0 WirePair" do
      wire = described_class.serialize(5)
      expect([wire.status, wire.data]).to eq([0, "5"])
    end

    it "serializes an error into a status-1 WirePair carrying its payload" do
      error = described_class.evaluate(parse_entry("[1, 0] | @math.divide"), described_class.root_environment)
      wire = described_class.serialize(error)
      expect(wire.status).to eq(1)
      expect(wire.data).to include('"kind":"math_error"')
    end
  end

  describe ".encode" do
    it "encodes a value WirePair in array mode" do
      expect(described_class.encode(Fusion::WirePair.new(status: 0, data: "5"), mode: :array)).to eq("[0,5]")
    end

    it "encodes an error WirePair in object mode" do
      expect(described_class.encode(Fusion::WirePair.new(status: 1, data: %("e")), mode: :object)).to eq(%({"error":"e"}))
    end

    it "encodes an error WirePair in bang mode" do
      expect(described_class.encode(Fusion::WirePair.new(status: 1, data: %("e")), mode: :bang)).to eq(%(!"e"))
    end
  end
end
