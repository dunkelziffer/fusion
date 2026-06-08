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
    Value = TypedData::Union(Integer, Float, String, true, false, Interpreter::NULL)

    # Expression and Pattern nodes each form a closed family. They are declared
    # up front (empty) so a member of either may reference the other — e.g. a
    # function Clause holds a Pattern and an Expression. Each module is mixed
    # into all of its members at the bottom of its body, so the module doubles
    # as a marker: a field typed `Expression` accepts any expression node,
    # `Pattern` any pattern node.
    module Expression; end
    module Pattern; end

    # Auxiliary typed parts: the elements a collection node holds. These are NOT
    # themselves expressions or patterns, so they live here, outside the marker
    # families, and never satisfy an `Expression`/`Pattern` field.
    ArrayItem    = TypedData.define(value: Expression)                          # an array element
    ArraySpread  = TypedData.define(value: Expression)                          # ...expr inside an array
    KeyValuePair = TypedData.define(key: String, value: Expression)            # "k": expr inside an object
    ObjectSpread = TypedData.define(value: Expression)                          # ...expr inside an object
    Clause       = TypedData.define(pattern: Pattern, body: Expression)        # one  pattern => body  of a function
    PatternItem  = TypedData.define(pattern: Pattern)                          # a sub-pattern of an array pattern
    PatternPair  = TypedData.define(key: String, pattern: Pattern)            # "k": pat inside an object pattern
    PatternRest  = TypedData.define(name: TypedData::Union(String, nil))      # ...name (name nil = ignore) in either

    module Expression
      Lit       = TypedData.define(value: Value)                                                    # atom literal (incl NULL)
      ErrLit    = TypedData.define(payload: TypedData::Union(Expression, nil))                       # !expr or bare ! (payload nil = !null)
      ArrLit    = TypedData.define(elems: TypedData::ArrayOf(TypedData::Union(ArrayItem, ArraySpread)))
      ObjLit    = TypedData.define(members: TypedData::ArrayOf(TypedData::Union(KeyValuePair, ObjectSpread)))
      FuncLit   = TypedData.define(clauses: TypedData::ArrayOf(Clause))
      Ident     = TypedData.define(name: String)                                                    # read a builtin/bound name
      FileRef   = TypedData.define(variety: TypedData::Union(:self, :name, :path), path: TypedData::Union(String, nil))
      Pipe      = TypedData.define(left: Expression, right: Expression)                              # left | right
      Member    = TypedData.define(obj: Expression, key: String)                                    # obj.key
      Index     = TypedData.define(obj: Expression, idx: Expression)                                # obj[expr]

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end

    module Pattern
      PLit      = TypedData.define(value: Value)                                                     # literal pattern
      PErr      = TypedData.define(inner: Pattern)                                                   # ! or !pat ; inner=PWild matches any error
      PBind     = TypedData.define(name: String)                                                     # binds
      PWild     = TypedData.define(dummy: nil)                                                       # _
      PArr      = TypedData.define(elems: TypedData::ArrayOf(TypedData::Union(PatternItem, PatternRest)))
      PObj      = TypedData.define(members: TypedData::ArrayOf(TypedData::Union(PatternPair, PatternRest)))
      PGuard    = TypedData.define(inner: Pattern, pred_expr: Expression)                            # inner ? predicate

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end
  end
end
