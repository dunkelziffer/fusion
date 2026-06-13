# frozen_string_literal: true

# === CLI tools ===
#
# Core data types:
# - WirePair
# - Fusion runtime value

require_relative "wire_pair"
require_relative "cli/options"

require_relative "cli/decoder"
require_relative "cli/parser"
require_relative "cli/serializer"
require_relative "cli/encoder"

require_relative "cli/repl"

module Fusion
  module CLI
    extend self

    # Run the use case selected on the command line.
    def run(options)
      case options.use_case
      when :pipe then run_pipe(options)
      when :stream then run_stream(options)
      when :repl then Repl.new.run
      else raise Unreachable, "Unknown use case #{options.use_case}"
      end
    end

    # pipe: load the program, pipe one input through it, emit one output.
    def run_pipe(options)
      function = load_program(options)
      input    = parse(load_input(options))
      output   = apply(function, input)
      emit_output(serialize(output), output_mode: options.output_mode)
    end

    # stream: load the program once, then treat stdin/stdout as NDJSON streams —
    # one input per line, one output line per input. Errors stay in-band (the
    # unix mode is unavailable here), so the exit code is always 0.
    def run_stream(options)
      function = load_program(options)
      $stdout.sync = true
      $stdin.each_line do |line|
        next if line.strip.empty?

        input  = parse(decode(line, mode: options.input_mode))
        output = apply(function, input)
        $stdout.puts(encode(serialize(output), mode: options.output_mode))
      end
    end

    # String -> WirePair
    # Doesn't support mode `:unix`
    def decode(string, mode:)
      Decoder.decode(string, mode:)
    end

    # WirePair -> runtime value
    def parse(wire_pair)
      Parser.parse(wire_pair)
    end

    # runtime value -> WirePair
    def serialize(runtime_value)
      Serializer.serialize(runtime_value)
    end

    # WirePair -> String
    # Doesn't support mode `:unix`
    def encode(wire_pair, mode:)
      Encoder.encode(wire_pair, mode:)
    end

    # === Utilities ===

    private

    # input -> WirePair
    def load_input(options)
      text = options.explicit_input || ($stdin.tty? ? "" : $stdin.read)
      empty = text.strip.empty?

      if options.input_mode == :unix || empty
        WirePair.new(
          status: options.error_input? ? 1 : 0,
          data: empty ? "null" : text
        )
      else
        decode(text, mode: options.input_mode)
      end
    end

    # WirePair -> output
    def emit_output(wire_pair, output_mode:)
      if output_mode == :unix
        channel = wire_pair.status.zero? ? $stdout : $stderr
        channel.puts(wire_pair.data)
        exit(wire_pair.status)
      else
        $stdout.puts(encode(wire_pair, mode: output_mode))
        exit 0
      end
    end

    # Load the program (a `.fsn` file or an inline `-e` source) into the runtime
    # value it evaluates to — usually a function. A parse error or a non-function
    # value flows on as the program value and surfaces when `apply` runs it.
    def load_program(options)
      interpreter = Fusion::Interpreter.new
      if options.inline_source
        ast = Fusion::Parser.parse_file(options.inline_source, location: "code <inline>")
        return ast if ast.is_a?(Fusion::Interpreter::ErrorVal) # a parse error

        env = interpreter.root_env.child
        env.define("__dir__", Dir.pwd)
        interpreter.eval_expr(ast, env)
      else
        interpreter.load_file(File.expand_path(options.program_path)).force
      end
    end

    # Apply the program to one input behind a safety net: a Ruby-level failure
    # (notably a stack overflow) becomes a payloaded error rather than a raw
    # backtrace, so the stdout/stderr contract always holds. In the stream the
    # error is one record's output and the next line continues.
    def apply(function, input)
      interpreter = Fusion::Interpreter.new
      interpreter.apply(function, input)
    rescue SystemExit, Unreachable
      # exit/abort and the interpreter's own assertions are allowed through.
      raise
    rescue SystemStackError
      Interpreter::ErrorVal.internal(
        kind: "stack_error", location: "interpreter", operation: "running the program",
        input: NULL, message: "recursion too deep"
      )
    rescue Exception => err # rubocop:disable Lint/RescueException
      # Final net: any other escaped Ruby error becomes a payloaded error too.
      Interpreter::ErrorVal.internal(
        kind: "type_error", location: "interpreter", operation: "running the program",
        input: NULL, message: err.message
      )
    end
  end
end
