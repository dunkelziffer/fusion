module Fusion
  # =========================================================================
  # RUNTIME VALUES
  # =========================================================================

  # A function closes over the environment in which it was defined.
  class Func
    attr_reader :clauses, :env
    def initialize(clauses, env)
      @clauses = clauses # [[pattern, expr_ast], ...]
      @env = env
    end
    def inspect = "<func/#{clauses.length}>"
  end
end
