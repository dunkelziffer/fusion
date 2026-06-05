# frozen_string_literal: true

# Helpers for driving the Fusion interpreter from specs.
#
# A Fusion program is a single value; an "executable" file is one whose value is
# a function. Specs describe a run as a pipe — input | program = output — via a
# small chainable builder:
#
#   expect_pipe
#     .in("✅", "1")             # input: exit-code marker + JSON value
#     .file_path("test.fsn")     # program: a fixture file …
#     .out("❌", "42")           # … or .code("(x => …)") for inline source
#
# `.out(marker, payload)` runs the pipe and asserts the result; a matcher object
# (e.g. a_string_including(...)) is allowed in the payload slot. `.raises(Err)`
# instead asserts the program fails to parse/evaluate. `.env(CI: "1")` supplies
# variables visible to @ENV.
#
# Both input and output are (marker, payload) pairs mirroring the CLI (see
# exe/fusion): "✅" for exit 0 (a value), "❌" for exit 1 (an error payload).
module FusionHelpers
  STDLIB   = File.expand_path("../../stdlib", __dir__)
  FIXTURES = File.expand_path("../fixtures", __dir__)

  OK = "✅"
  ERR = "❌"

  def expect_pipe
    PipeExpectation.new(self)
  end

  # Chainable builder; see the module comment for usage. Each builder step may be
  # used at most once, and the code/file_path and out/raises pairs are mutually
  # exclusive — misuse raises immediately rather than silently last-wins.
  class PipeExpectation
    def initialize(example)
      @example  = example
      @input    = [OK, "null"]
      @env_vars = {}
      @used     = []
    end

    def in(status, json)
      claim!(:in)
      @input = [status, json]
      self
    end

    def env(**env_vars)
      claim!(:env)
      @env_vars = env_vars.transform_keys(&:to_s)
      self
    end

    def code(source)
      claim!(:program, "code/file_path")
      @code = source
      self
    end

    def file_path(path)
      claim!(:program, "code/file_path")
      @file_path = path
      self
    end

    # Run the pipe and assert the (marker, payload) result.
    def out(status, json)
      claim!(:assertion, "out/raises")
      actual = run
      expected = [status, json]
      @example.instance_exec { expect(actual).to match(expected) }
    end

    # Assert the program fails to parse/evaluate instead of producing a result.
    def raises(error_class)
      claim!(:assertion, "out/raises")
      pipe = self
      @example.instance_exec { expect { pipe.run }.to raise_error(error_class) }
    end

    # Evaluate the program against the input, mapping the result to
    # (marker, payload) exactly as exe/fusion does. Public so .raises can defer
    # it inside an `expect { }` block.
    def run
      interp = Fusion::Interpreter.new(stdlib_dir: STDLIB, env_vars: @env_vars)
      value = interp.apply(program(interp), input_value)
      if value.is_a?(Fusion::Interpreter::ErrorVal)
        [ERR, Fusion::CLI.serialize(value.payload)]
      elsif !Fusion::CLI.serializable?(value)
        # Mirror exe/fusion: a function result can't be emitted as JSON.
        payload = Fusion::Errors.make(kind: "serialization_error", location: "output",
                                      operation: "serializing result", input: value,
                                      message: "cannot serialize a function").payload
        [ERR, Fusion::CLI.serialize(payload)]
      else
        [OK, Fusion::CLI.serialize(value)]
      end
    end

    private

    # Record that a builder slot has been filled, rejecting a second use.
    def claim!(slot, label = slot)
      raise ArgumentError, "`#{label}` may be used only once per expect_pipe" if @used.include?(slot)
      @used << slot
    end

    def program(interp)
      if @file_path
        interp.load_file(File.join(FIXTURES, @file_path)).force
      else
        ast = Fusion::Parser.parse_file(@code)
        env = interp.root_env.child
        env.define("__dir__", FIXTURES)
        interp.eval_expr(ast, env)
      end
    end

    # An input may itself be an error ("❌"); all current specs use "✅".
    def input_value
      marker, payload = @input
      parsed = Fusion::CLI.parse(payload)
      marker == ERR ? Fusion::Interpreter::ErrorVal.new(parsed) : parsed
    end
  end
end
