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
# (e.g. a_string_including(...)) is allowed in the payload slot. A program that
# fails to parse is not an exception — it is a payloaded syntax_error, asserted
# with `.out("❌", ...)` like any other failure. `.env(CI: "1")` supplies
# variables visible to @ENV.
#
# Both input and output are (marker, payload) pairs mirroring the CLI (see
# exe/fusion): "✅" for exit 0 (a value), "❌" for exit 1 (an error payload).

module FusionHelpers
  FIXTURES = File.expand_path("../fixtures", __dir__)

  OK = "✅"
  ERR = "❌"

  def expect_pipe
    PipeExpectation.new(self)
  end

  # Chainable builder
  class PipeExpectation
    def initialize(example)
      @example  = example
      @env_vars = {}
      @jail     = :default # :default (the program's dir) | nil (no jail) | absolute path
      @input    = [OK, "null"]
      @code     = nil
      @used     = []
    end

    def env(**env_vars)
      claim!(:env)
      @env_vars = env_vars.transform_keys(&:to_s)
      self
    end

    # Mirrors the CLI's `--jail`, but adjusts paths to the spec fixtures.
    # Without a call, the jail defaults to the program's directory, exactly as the CLI does.
    def jail(dir)
      claim!(:jail)
      @jail = dir == "*" ? nil : File.join(FIXTURES, dir)
      self
    end

    def in(status, json)
      claim!(:in)
      @input = [status, json]
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
      claim!(:assertion, "out")
      actual = run
      expected = [status, json]
      @example.instance_exec { expect(actual).to match(expected) }
    end

    # Evaluate the program against the input, mapping the result to
    # (marker, payload) exactly as exe/fusion does.
    def run
      interp = Fusion::Interpreter.new(env_vars: @env_vars, jail_root: resolved_jail)
      value = interp.apply(program(interp), input_value)
      pair = Fusion::CLI.serialize(value)
      [pair.status.zero? ? OK : ERR, pair.data]
    end

    private

    # The default jail is the program's directory — FIXTURES for inline `.code`,
    # mirroring the CLI's cwd default — so specs run jailed just like real use.
    def resolved_jail
      return @jail unless @jail == :default

      @file_path ? File.dirname(File.join(FIXTURES, @file_path)) : FIXTURES
    end

    # Record that a builder slot has been filled, rejecting a second use.
    def claim!(slot, label = slot)
      raise ArgumentError, "`#{label}` may be used only once per expect_pipe" if @used.include?(slot)
      @used << slot
    end

    def program(interp)
      if @file_path
        interp.load_file(File.join(FIXTURES, @file_path)).force
      else
        ast = Fusion::Parser.parse_file(@code, location: "code <inline>")
        return ast if ast.is_a?(Fusion::Interpreter::ErrorVal) # a parse error
        env = interp.root_env.child
        env.set_context(:dir, FIXTURES)
        interp.evaluate_unit(ast, env)
      end
    end

    # An input may itself be an error ("❌"); all current specs use "✅". The
    # (marker, payload) pair mirrors the CLI's wire pair, so `parse` does the
    # error-wrapping from the status.
    def input_value
      marker, payload = @input
      Fusion::CLI.parse(Fusion::WirePair.new(status: marker == ERR ? 1 : 0, data: payload))
    end
  end
end
