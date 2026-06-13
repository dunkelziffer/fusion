# frozen_string_literal: true

# === Data Structure ===
#
# An AST::Expression is
# - output of the parser
# - input of the interpreter

require_relative "typed_data"
require_relative "atom"

module Fusion
  module AST
    # A syntactic identifier: a bound/looked-up name, a `.key`, or a `...rest`
    # binder. Mirrors the lexer's ident rule (Lexer#ident_start? / #ident_part?).
    # Object *keys* are arbitrary strings, not identifiers, so they stay `String`.
    Identifier = /\A[A-Za-z_][A-Za-z0-9_]*\z/

    # Expression and Pattern nodes each form a closed family, declared up front
    # (empty) so a member of either may reference the other. Each module is
    # mixed into all of its members at the bottom of its body, so the module
    # doubles as a marker: a field typed `Expression` accepts any expression
    # node, `Pattern` any pattern node.
    module Expression; end
    module Pattern; end
    module Statement; end

    # Auxiliary typed parts: the elements a collection node holds. NOT themselves
    # expressions or patterns, so they live outside the marker families and never
    # satisfy an `Expression`/`Pattern` field.
    ArrayItem    = TypedData.define(value: Expression)                            # an array element
    ArraySpread  = TypedData.define(value: Expression)                            # ...expr inside an array
    KeyValuePair = TypedData.define(key: String, value: Expression)               # "k": expr inside an object
    ObjectSpread = TypedData.define(value: Expression)                            # ...expr inside an object
    Clause       = TypedData.define(pattern: Pattern, body: Expression)           # one  pattern => body  of a function
    PatternItem  = TypedData.define(pattern: Pattern)                             # a sub-pattern of an array pattern
    PatternPair  = TypedData.define(key: String, pattern: Pattern)                # "k": pat inside an object pattern
    PatternRest  = TypedData.define(name: ->(v) { Identifier === v || v.nil? })   # ...name (name nil = ignore) in either

    module Expression
      Lit       = TypedData.define(value: Atom)                                                      # atom literal (incl NULL)
      ErrLit    = TypedData.define(payload: ->(v) { Expression === v || v.nil? })                    # !expr or bare ! (payload nil = !null)
      ArrLit    = TypedData.define(items: ->(v) { v.is_a?(Array) && v.all? { |e| ArrayItem === e || ArraySpread === e } })
      ObjLit    = TypedData.define(pairs: ->(v) {                                                    # [KeyValuePair|ObjectSpread], distinct fixed keys
        v.is_a?(Array) &&
          v.all? { |m| KeyValuePair === m || ObjectSpread === m } &&
          v.filter_map { |m| m.key if KeyValuePair === m }.then { |keys| keys.uniq.size == keys.size }
      })
      FuncLit   = TypedData.define(clauses: ->(v) { v.is_a?(Array) && v.all? { |c| Clause === c } }) # [] = the empty function
      Ident     = TypedData.define(name: Identifier)                                                 # read a builtin/bound name
      FileRef   = TypedData.define(variety: ->(v) { %i[self name path].include?(v) }, path: ->(v) { String === v || v.nil? })
      Pipe      = TypedData.define(left: Expression, right: Expression)                              # left | right
      Member    = TypedData.define(obj: Expression, key: Identifier)                                 # obj.key
      Index     = TypedData.define(obj: Expression, idx: Expression)                                 # obj[expr]

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end

    module Pattern
      PLit      = TypedData.define(value: Atom)                                                     # literal pattern
      PErr      = TypedData.define(inner: Pattern)                                                  # ! or !pat ; inner=PWild matches any error
      PBind     = TypedData.define(name: Identifier)                                                # binds
      PWild     = TypedData.define(dummy: NilClass)                                                 # _
      PArr      = TypedData.define(items: ->(v) {                                                   # [PatternItem|PatternRest], at most one rest
        v.is_a?(Array) &&
          v.all? { |e| PatternItem === e || PatternRest === e } &&
          v.count { |e| PatternRest === e } <= 1
      })
      PObj      = TypedData.define(pairs: ->(v) {                                                   # [PatternPair|PatternRest], one rest, distinct keys
        v.is_a?(Array) &&
          v.all? { |m| PatternPair === m || PatternRest === m } &&
          v.count { |m| PatternRest === m } <= 1 &&
          v.filter_map { |m| m.key if PatternPair === m }.then { |keys| keys.uniq.size == keys.size }
      })
      PGuard    = TypedData.define(inner: Pattern, pred_expr: Expression)                           # inner ? predicate

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end

    module Statement
      # The only statement. Only allowed in the REPL. `name = expression`.
      Assignment = TypedData.define(name: Identifier, expression: Expression)

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end
  end
end
