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

      root = root_environment(jail: jail_root(options))
      program = load_program(options, root)

      input = load_input(options)
      output = if input.nil?
        program
      else
        apply(parse(input), program, environment: root)
      end

      emit_output(serialize(output), output_mode: options.output_mode)
    end

    def run_stream(options)
      prepare!

      root = root_environment(jail: jail_root(options))
      program = load_program(options, root)

      $stdin.each_line do |line|
        record = line.chomp

        if record.strip.empty?
          $stdout.puts unless options.skip_blank_lines?
        else
          input = decode(record, mode: options.input_mode)
          output = apply(parse(input), program, environment: root)
          $stdout.puts(encode(serialize(output), mode: options.output_mode))
        end
      end
    end

    def run_repl(options)
      Repl.new(root_env: root_environment(jail: jail_root(options))).run
    end

    # String (treated as stdin) -> WirePair
    # Doesn't support mode `:unix`
    def decode(string, mode:)
      Decoder.decode(string, mode:)
    end

    # WirePair -> runtime value
    def parse(wire_pair)
      Parser.parse(wire_pair)
    end

    # A binding-free root environment
    def root_environment(jail: Dir.pwd)
      Interpreter::Env.new.set_context(:jail, jail)
    end

    # String (treated as inline source) -> runtime value
    def load_source(inline_source, root_env)
      ast = Fusion::Parser.parse_file(inline_source, origin: { location: "code", file: nil })
      return ast if ast.is_a?(Fusion::Interpreter::ErrorVal) # a parse error

      inline_env = root_env.child.set_context(:dir, Dir.pwd)
      Fusion::Interpreter.new(inline_env).evaluate_unit(ast)
    end

    # relative path -> runtime_value
    def load_file(rel_path, root_env)
      Fusion::Interpreter.new(root_env).load_file(File.expand_path(rel_path)).force
    end

    # runtime value + runtime value -> runtime value
    # input | function -> output
    # Confines @-resolution to the environment's jail.
    # Ignores the environment's bindings. The function carries its own closure.
    def apply(input, function, environment:)
      Interpreter.safe_apply(function, input, environment)
    end

    # expression (AST) -> runtime value
    # Mutates environment if given an assignment statement.
    # Confines @-resolution to the environment's jail.
    # Has access to the environment's bindings.
    def evaluate(ast, environment)
      case ast
      when AST::Statement::Assignment
        value = Interpreter.safe_evaluate(ast.expression, environment)
        environment.bind(ast.name, value, checked: false)
        value
      when AST::Expression
        Interpreter.safe_evaluate(ast, environment)
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
    def load_program(options, root_env)
      if options.inline_source
        load_source(options.inline_source, root_env)
      else
        load_file(options.program_path, root_env)
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
