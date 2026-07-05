# frozen_string_literal: true

# Helpers for driving Fusion from specs.
# Composed from the public `Fusion::CLI` building blocks.
#
# A Fusion program is a single value; an "executable" file is one whose value is
# a function. Specs describe a run as a pipe — input | program = output — via a
# small chainable builder:
#
#   expect_pipe
#     .env(CI: "1")              # supplies variables visible to @ENV, optional
#     .in("✅", "1")             # input: exit-code marker + JSON value
#     .file_path("test.fsn")     # program: a fixture file or .code("(x => …)") for inline source
#     .out("❌", "42")           # output: exit-code marker + JSON value, runs the pipe and asserts the result.
#
# The payload slot takes the exact JSON string where it is stable. When parts of
# that string are machine-dependent, use the `a_string_including`-matcher.
# That matcher supports string AND `Regexp`. Use a string for all stable key-value
# pairs. Use a `Regexp` matcher for variable key-value pairs. If the value of a
# key-value pair is allowed to be an arbitrary string, only assert the key via
# '"key":'.
#
# A program that fails to parse is not an exception. It is a payloaded syntax_error,
# asserted with `.out("❌", ...)` like any other failure.
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
      @input    = nil
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

    private

    # Evaluate the program against the input with the `Fusion::CLI` building
    # blocks, composed as in `run_pipe`, mapping the result to (marker, payload)
    # exactly as exe/fusion does.
    def run
      @example.instance_exec(@env_vars) { |variables| stub_const("ENV", variables) }

      root = Fusion::CLI.root_environment(jail: resolved_jail)
      program = program(root)

      output = if @input.nil?
        program
      else
        Fusion::CLI.apply(spec_input(*@input), program, environment: root)
      end

      spec_output(output)
    end

    # The default jail is the program's directory — FIXTURES for inline `.code`,
    # mirroring the CLI's cwd default — so specs run jailed just like real use.
    def resolved_jail
      raw = if @jail == :default
        @file_path ? File.dirname(File.join(FIXTURES, @file_path)) : FIXTURES
      else
        @jail
      end
      raw && File.expand_path(raw)
    end

    # Record that a builder slot has been filled, rejecting a second use.
    def claim!(slot, label = slot)
      # :nocov: only fires on spec-author misuse
      raise ArgumentError, "`#{label}` may be used only once per expect_pipe" if @used.include?(slot)
      # :nocov:

      @used << slot
    end

    # The program value, loaded with the CLI's own building blocks. Inline
    # source is loaded from the fixtures directory — like a user launching
    # `fusion -e` there — so its @-references resolve against the fixtures.
    def program(root_environment)
      if @file_path
        Fusion::CLI.load_file(File.join(FIXTURES, @file_path), root_environment)
      else
        Dir.chdir(FIXTURES) { Fusion::CLI.load_source(@code, root_environment) }
      end
    end

    # (marker, payload) -> runtime_value
    def spec_input(marker, payload)
      Fusion::CLI.parse(Fusion::WirePair.new(status: marker == ERR ? 1 : 0, data: payload))
    end

    # runtime_value -> (marker, payload)
    def spec_output(output)
      wire_pair = Fusion::CLI.serialize(output)
      [wire_pair.status.zero? ? OK : ERR, wire_pair.data]
    end
  end
end
