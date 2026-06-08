# frozen_string_literal: true

# === Interpreter internals ===
#
# A function closes over the environment in which it was defined.

module Fusion
  class Interpreter
    class Func
      attr_reader :clauses, :env

      def initialize(clauses, env)
        @clauses = clauses # [AST::Clause, ...]
        @env = env
      end

      def inspect
        "<func/#{clauses.length}>"
      end
    end
  end
end
