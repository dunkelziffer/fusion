# frozen_string_literal: true

# === Data Structure ===
#
# An AST::Expression is
# - output of the parser
# - input of the interpreter

module Fusion
  module AST
    module Expression
      Lit       = Struct.new(:value)                 # atom literal (incl NULL)
      ErrLit    = Struct.new(:payload)               # !expr or bare ! (payload nil = !null)
      ArrLit    = Struct.new(:elems)                 # elems: [[:item|:spread, expr], ...]
      ObjLit    = Struct.new(:members)               # [[:kv, key, expr] | [:spread, expr]]
      FuncLit   = Struct.new(:clauses)               # [[pattern, expr], ...]
      Ident     = Struct.new(:name)                  # read a builtin/bound name
      FileRef   = Struct.new(:variety, :path)        # variety: :self|:name|:path
      Pipe      = Struct.new(:left, :right)          # left | right
      Member    = Struct.new(:obj, :key)             # obj.key
      Index     = Struct.new(:obj, :idx)             # obj[expr]
    end

    module Pattern
      PLit      = Struct.new(:value)                 # literal pattern
      PErr      = Struct.new(:inner)                 # ! or !pat ; inner=nil matches any error
      PBind     = Struct.new(:name)                  # binds
      PWild     = Struct.new(:dummy)                 # _
      PArr      = Struct.new(:elems)                 # [[:pat,p]|[:rest,name_or_nil], ...]
      PObj      = Struct.new(:members)               # [[:kv,key,pat]|[:rest,name_or_nil]]
      PGuard    = Struct.new(:inner, :pred_expr)     # inner ? predicate
    end
  end
end
