# frozen_string_literal: true

# === Data Structure ===
#
# An AST::Expression is
# - output of the parser
# - input of the interpreter

require_relative "typed_data"
require_relative "interpreter/null"

module Fusion
  module AST
    # The scalar values a literal node can carry: the JSON atoms plus NULL
    # (everything the lexer emits as a token value, see Lexer#lex_number and
    # #lex_word).
    Value = TypedData::Union.new(Integer, Float, String, true, false, Interpreter::NULL)

    # Expression and Pattern nodes each form a closed family. The module below
    # doubles as a marker mixed into every one of its members (see the loop at
    # the end), so a field that holds a sub-node is typed simply by naming the
    # module: `left: Expression` means "any expression", `inner: Pattern` means
    # "any pattern".
    module Expression
      Lit       = TypedData.define(value: Value)                                  # atom literal (incl NULL)
      ErrLit    = TypedData.define(payload: TypedData::Union.new(Expression, nil)) # !expr or bare ! (payload nil = !null)
      ArrLit    = TypedData.define(elems: TypedData._Array(Array))                # elems: [[:item|:spread, expr], ...]
      ObjLit    = TypedData.define(members: TypedData._Array(Array))              # [[:kv, key, expr] | [:spread, expr]]
      FuncLit   = TypedData.define(clauses: TypedData._Array(Array))              # [[pattern, expr], ...]
      Ident     = TypedData.define(name: String)                                 # read a builtin/bound name
      FileRef   = TypedData.define(variety: TypedData::Union.new(:self, :name, :path), path: TypedData::Union.new(String, nil))
      Pipe      = TypedData.define(left: Expression, right: Expression)     # left | right
      Member    = TypedData.define(obj: Expression, key: String)           # obj.key
      Index     = TypedData.define(obj: Expression, idx: Expression)       # obj[expr]

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end

    module Pattern
      PLit      = TypedData.define(value: Value)                            # literal pattern
      PErr      = TypedData.define(inner: Pattern)                          # ! or !pat ; inner=PWild matches any error
      PBind     = TypedData.define(name: String)                           # binds
      PWild     = TypedData.define(dummy: nil)                              # _
      PArr      = TypedData.define(elems: TypedData._Array(Array))          # [[:pat,p]|[:rest,name_or_nil], ...]
      PObj      = TypedData.define(members: TypedData._Array(Array))        # [[:kv,key,pat]|[:rest,name_or_nil]]
      PGuard    = TypedData.define(inner: Pattern, pred_expr: Expression)   # inner ? predicate

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end
  end
end
