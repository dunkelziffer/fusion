# frozen_string_literal: true

# === CLI tools ===

require_relative "cli/parser"
require_relative "cli/serializer"

module Fusion
  module CLI
    extend self

    # Load the program / code / function
    def load(inline, program_path)
      interp = Fusion::Interpreter.new

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
    def read_input(explicit_input)
      input_text = explicit_input || ($stdin.tty? ? "" : $stdin.read)
      input_text = "null" if input_text.nil? || input_text.strip.empty?

      parse(input_text)
    end

    # Returns output
    def apply(input, function)
      Fusion::Interpreter.new.apply(function, input)
    end

    # Emit the output
    def emit_output(runtime_value)
      status, json = serialize(runtime_value)
      (status.zero? ? $stdout : $stderr).puts json
      exit status
    end

    private

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
