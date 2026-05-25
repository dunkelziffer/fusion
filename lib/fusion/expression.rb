module Fusion
  module Expression
    # =========================================================================
    # AST
    # =========================================================================

    # Expressions
    Literal         = Struct.new(:value)          # atom literal (incl NULL/ERROR)
    ArrayLiteral    = Struct.new(:elems)          # elems: [[:item|:spread, expr], ...]
    ObjectLiteral   = Struct.new(:members)        # [[:kv, key, expr] | [:spread, expr]]
    FunctionLiteral = Struct.new(:clauses)        # [[pattern, expr], ...]
    Identifier      = Struct.new(:name)           # read a builtin/bound name
    FileReference   = Struct.new(:path)           # @path  (string like "../a/b")
    Pipe            = Struct.new(:left, :right)   # left | right
    Member          = Struct.new(:obj, :key)      # obj.key
    Index           = Struct.new(:obj, :idx)      # obj[expr]
  end
end
