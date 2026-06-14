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

    # Run the use case selected on the command line.
    def run(options)
      case options.use_case
      when :pipe then run_pipe(options)
      when :stream then run_stream(options)
      when :repl then Repl.new.run
      else raise Unreachable, "Unknown use case #{options.use_case}"
      end
    end

    # pipe: load the program, then either pipe one input through it or — when no
    # input is supplied — emit the program's own value. The no-input case lets a
    # .fsn file double as enriched JSON data (computations, @ENV, @-references).
    def run_pipe(options)
      program = load_program(options)
      input   = load_input(options)
      output  = input.nil? ? program : apply(parse(input), program)
      emit_output(serialize(output), output_mode: options.output_mode)
    end

    # stream: load the program once, then treat stdin/stdout as NDJSON streams —
    # one input per line, one output line per input. Errors stay in-band (the
    # unix mode is unavailable here), so the exit code is always 0.
    #
    # NDJSON conformance: UTF-8 throughout; "\n" and "\r\n" are both accepted as
    # input delimiters (chomp); every output record is a single-line JSON text
    # (JSON.generate never emits newlines) terminated by "\n". Blank input lines
    # are skipped — the one deviation the spec permits, documented in §9.5.
    def run_stream(options)
      program = load_program(options)
      $stdout.sync = true
      $stdin.set_encoding(Encoding::UTF_8)
      $stdout.set_encoding(Encoding::UTF_8)
      $stdin.each_line do |line|
        record = line.chomp
        next if record.strip.empty?

        input  = parse(decode(record, mode: options.input_mode))
        output = apply(input, program)
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

    # input | function -> output
    def apply(input, function)
      Interpreter.safe_apply(function, input)
    end

    # expression -> runtime value
    # Mutates environment (REPL variable binding)
    def evaluate(expression, environment)
      Interpreter.safe_evaluate(expression, environment)
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

    private

    # Read stdin into the input WirePair, or nil when no input was supplied (so
    # the program's own value becomes the result — see run_pipe). Empty stdin
    # counts as "no input", except under -!, which always supplies an error value
    # (empty stdin becomes !null, mirroring the language's bare !).
    def load_input(options)
      text  = $stdin.tty? ? "" : $stdin.read
      empty = text.strip.empty?

      if options.error_input?
        WirePair.new(status: 1, data: empty ? "null" : text)
      elsif empty
        nil
      elsif options.input_mode == :unix
        WirePair.new(status: 0, data: text)
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
  end
end
