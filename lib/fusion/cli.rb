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
require_relative "interpreter"
require_relative "cli/serializer"
require_relative "cli/encoder"

require_relative "cli/repl"

module Fusion
  module CLI
    extend self

    def prepare!
      $stdout.sync = true
      $stderr.sync = true
      $stdin.set_encoding(Encoding::UTF_8)
      $stdout.set_encoding(Encoding::UTF_8)
      $stderr.set_encoding(Encoding::UTF_8)
    end

    def run(options)
      case options.use_case
      when :pipe
        run_pipe(options)
      when :stream
        run_stream(options)
      when :repl
        Repl.new.run
      else
        raise Unreachable, "Unknown use case #{options.use_case}"
      end
    end

    def run_pipe(options)
      prepare!

      program = load_program(options)

      input = load_input(options)
      output = if input.nil?
        program
      else
        apply(parse(input), program)
      end

      emit_output(serialize(output), output_mode: options.output_mode)
    end

    def run_stream(options)
      prepare!

      program = load_program(options)

      $stdin.each_line do |line|
        record = line.chomp

        if record.strip.empty?
          $stdout.puts unless options.skip_blank_lines?
        else
          input = decode(record, mode: options.input_mode)
          output = apply(parse(input), program)
          $stdout.puts(encode(serialize(output), mode: options.output_mode))
        end
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

    # runtime value + runtime value -> runtime value
    # input | function -> output
    def apply(input, function)
      Interpreter.safe_apply(function, input)
    end

    # expression (AST) -> runtime value
    # Mutates environment (REPL variable binding)
    def evaluate(expression, environment)
      Interpreter.safe_evaluate(expression, environment)
    end

    # runtime value -> WirePair
    # CAUTION: resolves "internal" error status, only use for final output
    def serialize(runtime_value)
      Serializer.serialize(runtime_value)
    end

    # WirePair -> String
    # Doesn't support mode `:unix`
    def encode(wire_pair, mode:)
      Encoder.encode(wire_pair, mode:)
    end

    private

    # stdin -> WirePair
    def load_input(options)
      text = $stdin.tty? ? "" : $stdin.read.strip

      if text.empty?
        # "-!" promises that stdin carries an error payload. CLI contract violation.
        raise Options::UsageError, "-! requires input to mark as an error, but stdin was empty" if options.error_input?

        nil
      elsif options.input_mode == :unix
        WirePair.new(status: options.error_input? ? 1 : 0, data: text)
      else
        decode(text, mode: options.input_mode)
      end
    end

    # WirePair -> stdout/stderr
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

    # file/inline -> runtime value
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
  end
end
