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
        run_repl(options)
      else
        raise Unreachable, "Unknown use case #{options.use_case}"
      end
    end

    def run_pipe(options)
      prepare!

      jail = jail_root(options)
      program = load_program(options, jail)

      input = load_input(options)
      output = if input.nil?
        program
      else
        apply(parse(input), program, jail_root: jail)
      end

      emit_output(serialize(output), output_mode: options.output_mode)
    end

    def run_stream(options)
      prepare!

      jail = jail_root(options)
      program = load_program(options, jail)

      $stdin.each_line do |line|
        record = line.chomp

        if record.strip.empty?
          $stdout.puts unless options.skip_blank_lines?
        else
          input = decode(record, mode: options.input_mode)
          output = apply(parse(input), program, jail_root: jail)
          $stdout.puts(encode(serialize(output), mode: options.output_mode))
        end
      end
    end

    def run_repl(options)
      Repl.new(jail_root: jail_root(options)).run
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
    def apply(input, function, jail_root: Dir.pwd)
      Interpreter.safe_apply(function, input, jail_root: jail_root)
    end

    # expression (AST) -> runtime value
    # Mutates environment if given an assignment statement.
    def evaluate(ast, environment, jail_root: Dir.pwd)
      case ast
      when AST::Statement::Assignment
        value = Interpreter.safe_evaluate(ast.expression, environment, jail_root: jail_root)
        environment.bind(ast.name, value, checked: false)
        value
      when AST::Expression
        Interpreter.safe_evaluate(ast, environment, jail_root: jail_root)
      else
        raise Unreachable, "Unhandled AST node #{ast.class}"
      end
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
    def load_program(options, jail_root)
      interpreter = Fusion::Interpreter.new(jail_root: jail_root)
      if options.inline_source
        ast = Fusion::Parser.parse_file(options.inline_source, location: "code <inline>")
        return ast if ast.is_a?(Fusion::Interpreter::ErrorVal) # a parse error

        env = interpreter.root_env.child
        env.set_context(:dir, Dir.pwd)
        interpreter.evaluate_unit(ast, env)
      else
        interpreter.load_file(File.expand_path(options.program_path)).force
      end
    end

     # The jail root for this run: the program's directory by default (cwd for
    # inline `-e` and the REPL), or `--jail DIR` resolved against that base.
    # `--jail '*'` opts out of confinement entirely (nil = unconfined).
    def jail_root(options)
      return nil if options.jail == "*"

      base = options.program_path ? File.dirname(File.expand_path(options.program_path)) : Dir.pwd
      root = options.jail ? File.expand_path(options.jail, base) : base
      raise Options::UsageError, "jail directory not found: #{options.jail}" unless File.directory?(root)

      root
    end
  end
end
