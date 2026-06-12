# frozen_string_literal: true

# === CLI tools ===

require_relative "cli/options"
require_relative "cli/parser"
require_relative "cli/serializer"
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
      interpreter = Fusion::Interpreter.new
      function = load(interpreter, options.inline_source, options.program_path)
      input = read_input(options)
      output = interpreter.apply(function, input)
      emit_output(output, output_mode: options.output_mode)
    end

    # stream: load the program once, then treat stdin/stdout as NDJSON streams —
    # one input per line, one output line per input. Errors stay in-band (the
    # unix mode is not available here), so the exit code is always 0.
    def run_stream(options)
      interpreter = Fusion::Interpreter.new
      function = load(interpreter, options.inline_source, options.program_path)
      $stdout.sync = true
      $stdin.each_line do |line|
        next if line.strip.empty?

        input = Parser.decode(line, mode: options.input_mode)
        output = apply_record(interpreter, function, input)
        _status, text = Serializer.encode(output, mode: options.output_mode)
        $stdout.puts(text)
      end
    end

    # Load the program / code / function
    def load(interpreter, inline, program_path)
      if inline
        ast = Fusion::Parser.parse_file(inline, location: "code <inline>")
        if ast.is_a?(Fusion::Interpreter::ErrorVal)
          ast # a parse error becomes the program value and propagates below
        else
          env = interpreter.root_env.child
          env.define("__dir__", Dir.pwd)
          interpreter.eval_expr(ast, env)
        end
      else
        interpreter.load_file(File.expand_path(program_path)).force
      end
    end

    # Read the one pipe input: the explicit argument wins, else stdin. Empty
    # input is null in every input mode; -! wraps the input as an error value.
    def read_input(options)
      input_text = options.explicit_input || ($stdin.tty? ? "" : $stdin.read)
      input = input_text.strip.empty? ? NULL : Parser.decode(input_text, mode: options.input_mode)

      if options.error_input? && !input.is_a?(Interpreter::ErrorVal)
        input = Interpreter::ErrorVal.new(input)
      end

      input
    end

    # Emit the one pipe output and exit. Only the unix mode uses stderr and the
    # exit code as the error channel; the other modes mark the error in-band.
    def emit_output(runtime_value, output_mode: :unix)
      status, text = Serializer.encode(runtime_value, mode: output_mode)
      if output_mode == :unix
        (status.zero? ? $stdout : $stderr).puts(text)
        exit status
      else
        $stdout.puts(text)
        exit 0
      end
    end

    private

    # Apply the program to one stream record behind a per-record safety net: a
    # Ruby-level failure (notably a stack overflow) becomes that record's error
    # output and the stream continues with the next line.
    def apply_record(interpreter, function, input)
      interpreter.apply(function, input)
    rescue Unreachable
      raise # an interpreter bug; allowed to surface (see design 4.2)
    rescue SystemStackError
      Interpreter::ErrorVal.internal(
        kind: "stack_error", location: "interpreter", operation: "running the program",
        input: NULL, message: "recursion too deep"
      )
    rescue StandardError => err
      Interpreter::ErrorVal.internal(
        kind: "type_error", location: "interpreter", operation: "running the program",
        input: NULL, message: err.message
      )
    end

    # Parse the input
    # Returns a runtime value
    def parse(json)
      Parser.parse(json)
    end

    # Serialize the output
    # Returns [exit_code, json]
    def serialize(runtime_value)
      Serializer.to_json(runtime_value)
    end
  end
end
