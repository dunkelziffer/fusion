# frozen_string_literal: true

# === CLI internals ===
#
# The interactive use case: read `identifier = expression ;` statements from
# stdin, evaluate each in one shared session, print each result, and bind the
# identifier for later statements. A statement may span lines and ends at ";".
# There is no input/output mode and the exit code is always 0; everything is
# printed to stdout for a human, not for a pipeline.

module Fusion
  module CLI
    class Repl
      PROMPT = "fsn> "
      CONTINUATION_PROMPT = "...> "

      def initialize
        @interpreter = Fusion::Interpreter.new
        @session_env = @interpreter.root_env.child
        @session_env.define("__dir__", Dir.pwd)
        @interactive = $stdin.tty?
      end

      def run
        $stdout.sync = true
        buffer = +""
        loop do
          $stdout.print(buffer.empty? ? PROMPT : CONTINUATION_PROMPT) if @interactive
          line = $stdin.gets
          break if line.nil?

          buffer << line
          buffer = +"" if buffer.strip.empty? # a blank entry is not a statement
          next unless statement_complete?(buffer)

          execute(buffer)
          buffer = +""
        end
        $stdout.puts if @interactive # end the prompt line after Ctrl-D
      rescue Interrupt
        $stdout.puts if @interactive
      end

      private

      # A statement is terminated by ";". This check lexes, so a ";" inside a
      # string is not a terminator. A buffer that does not even lex can never
      # become valid by appending lines (strings cannot span lines), so it
      # counts as complete and the parse in #execute reports the syntax_error.
      def statement_complete?(buffer)
        Fusion::Lexer.new(buffer).tokens.any? { |token| token.type == :semicolon }
      rescue ParseError
        true
      end

      def execute(buffer)
        statements = Fusion::Parser.parse_statements(buffer, location: "code <inline>")
        if statements.is_a?(Interpreter::ErrorVal)
          $stdout.puts Serializer.render(statements)
          return
        end

        statements.each do |statement|
          value = evaluate(statement)
          $stdout.puts Serializer.render(value)
          # An error never binds — mirroring patterns, where a binder never
          # captures an error. The session continues either way.
          @session_env.define(statement.name, value) unless value.is_a?(Interpreter::ErrorVal)
        end
      end

      # Evaluate with the same per-run safety net as exe/fusion, but per
      # statement, so a Ruby-level failure becomes a printed payload and the
      # session survives it.
      def evaluate(statement)
        @interpreter.eval_expr(statement.expression, @session_env)
      rescue Unreachable
        raise # an interpreter bug; allowed to surface (see design 4.2)
      rescue SystemStackError
        Interpreter::ErrorVal.internal(
          kind: "stack_error", location: "interpreter", operation: "running the statement",
          input: NULL, message: "recursion too deep"
        )
      rescue StandardError => err
        Interpreter::ErrorVal.internal(
          kind: "type_error", location: "interpreter", operation: "running the statement",
          input: NULL, message: err.message
        )
      end
    end
  end
end
