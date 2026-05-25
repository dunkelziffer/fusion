module Fusion
  module Pattern
    # =========================================================================
    # AST
    # =========================================================================

    # Patterns
    Literal  = Struct.new(:value)               # literal pattern (incl ! and null)
    Binding  = Struct.new(:name)                # binds
    Wildcard = Struct.new(:dummy)               # _
    Array    = Struct.new(:elems)               # [[:pat,p]|[:rest,name_or_nil], ...]
    Object   = Struct.new(:members)             # [[:kv,key,pat]|[:rest,name_or_nil]]
    Guard    = Struct.new(:inner, :pred_expr)   # inner ? predicate
  end
end
