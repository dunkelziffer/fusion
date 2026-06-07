# frozen_string_literal: true

# === CLI tools ===

require_relative "cli/parser"
require_relative "cli/serializer"

module Fusion
  module CLI
    # Load the program / code / function
    def self.load(inline, program_path)
      stdlib = File.expand_path("../../stdlib", __dir__)
      interp = Fusion::Interpreter.new(stdlib_dir: (Dir.exist?(stdlib) ? stdlib : nil))

      if inline
        ast = Fusion::Parser.parse_file(inline, location: "code <inline>")
        if ast.is_a?(Fusion::Interpreter::ErrorVal)
          ast # a parse error becomes the program value and propagates below
        else
          env = interp.root_env.child
          env.define("__dir__", Dir.pwd)
          interp.eval_expr(ast, env)
        end
      else
        interp.load_file(File.expand_path(program_path)).force
      end
    end

    # Read input
    # Explicit arg wins, else stdin.
    def self.read_input(explicit_input)
      input_text = explicit_input || ($stdin.tty? ? "" : $stdin.read)
      input_text = "null" if input_text.nil? || input_text.strip.empty?

      parse(input_text)
    end

    # Parse the input
    # Returns a runtime value
    def self.parse(json)
      Parser.parse(json)
    end

    def self.apply(input, function)
      stdlib = File.expand_path("../../stdlib", __dir__)
      interp = Fusion::Interpreter.new(stdlib_dir: (Dir.exist?(stdlib) ? stdlib : nil))
      interp.apply(function, input)
    end

    # Serialize the output
    # Returns [exit_code, json]
    def self.serialize(runtime_value)
      Serializer.to_json(runtime_value)
    end

    # Emit the output
    def self.emit_output(runtime_value)
      status, json = serialize(runtime_value)
      (status.zero? ? $stdout : $stderr).puts json
      exit status
    end
  end
end
