# frozen_string_literal: true

# === CLI internals ===
#
# The interactive use case: read one entry at a time from the terminal, evaluate
# it in one shared session, and print the result. An entry is either
#   - an expression — evaluated and printed; or
#   - a statement `identifier = expression` — evaluated, printed, and bound to
#     the identifier for later entries.
# There is no input/output mode and the exit code is always 0; everything is for
# a human, not a pipeline.
#
# Line editing is Reline's job (multi-line entries, backspace to the previous
# line). The prompt, the echoed input, and all terminal control codes go to
# stderr — like bash's prompt — so stdout stays a clean stream of results.

require_relative "serializer"
require_relative "encoder"

module Fusion
  module CLI
    class Repl
      PROMPT = "fsn> "
      CONTINUATION_PROMPT = "...> "

      # REPL entries report errors with the same location as inline (`-e`) code.
      LOCATION = "code <inline>"

      def initialize
        @interpreter = Fusion::Interpreter.new
        @session_env = @interpreter.root_env.child
        @session_env.define("__dir__", Dir.pwd)
      end

      def run
        require "reline"
        $stdout.sync = true
        Reline.output = $stderr
        Reline.prompt_proc = proc do |lines|
          lines.each_index.map { |i| i.zero? ? PROMPT : CONTINUATION_PROMPT }
        end

        loop do
          entry =
            begin
              Reline.readmultiline(PROMPT, true) { |buffer| complete?(buffer) }
            rescue Interrupt
              $stderr.puts("^C") # discard the half-typed entry and re-prompt
              next
            end

          break if entry.nil? # Ctrl-D on an empty line ends the session
          next if entry.strip.empty?

          runtime_value = evaluate_entry(entry)
          wire_pair = Serializer.serialize(runtime_value, lenient: true)
          $stdout.puts(Encoder.encode(wire_pair, mode: :bang))
        end
      end

      # Whether `buffer` is ready to evaluate. The termination check for Reline's
      # multi-line editing: complete iff it is blank (submitted, then skipped) or
      # parses as a whole statement/expression. An incomplete *or* otherwise
      # invalid buffer is "not complete", so Reline keeps the entry open for the
      # user to finish or correct (see docs/user/reference.md §9.6).
      def complete?(buffer)
        return true if buffer.strip.empty?

        !Fusion::Parser.parse_repl(buffer, location: LOCATION).is_a?(Interpreter::ErrorVal)
      end

      # returns the REPL output string
      def evaluate_entry(buffer)
        entry = Fusion::Parser.parse_repl(buffer, location: LOCATION)

        case entry
        when Interpreter::ErrorVal
          # Reline checks with `complete?` and should therefore never hand a "syntax_error" to us.
          raise Unreachable, "Unhandled AST node #{entry.class}"
        when AST::Expression
          evaluate(entry)
        when AST::Statement::Assignment
          value = evaluate(entry.expression)

          # TODO: Decide, whether we want this. Why should we prevent errors from being stored in variables?
          @session_env.define(entry.name, value) unless value.is_a?(Interpreter::ErrorVal)

          value
        else
          raise Unreachable, "Unhandled AST node #{entry.class}"
        end
      end

      private

      # Evaluate an expression behind the same per-run safety net as
      # exe/fusion, so a Ruby-level failure becomes a printed payload and the
      # session survives it. A statement carries its expression; a bare
      # expression entry is the expression itself.
      def evaluate(expression)
        @interpreter.eval_expr(expression, @session_env)
      rescue Unreachable
        raise # an interpreter bug; allowed to surface (see design 4.2)
      rescue SystemStackError
        Interpreter::ErrorVal.internal(
          kind: "stack_error", location: "interpreter", operation: "running the entry",
          input: NULL, message: "recursion too deep"
        )
      rescue StandardError => err
        Interpreter::ErrorVal.internal(
          kind: "type_error", location: "interpreter", operation: "running the entry",
          input: NULL, message: err.message
        )
      end
    end
  end
end
