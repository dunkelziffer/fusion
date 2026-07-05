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
    IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/

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

    # An array element
    ArrayItem = TypedData.define(value: Expression)

    # `...expr` inside an array
    ArraySpread = TypedData.define(value: Expression)

    # `"k": expr` inside an object
    KeyValuePair = TypedData.define(key: String, value: Expression)

    # `...expr` inside an object
    ObjectSpread = TypedData.define(value: Expression)

    # One `pattern => body` of a function
    Clause = TypedData.define(pattern: Pattern, body: Expression)

    # A sub-pattern of an array pattern
    PatternItem = TypedData.define(pattern: Pattern)

    # `"k": pat` inside an object pattern
    PatternPair = TypedData.define(key: String, pattern: Pattern)

    # `...name` in array/object pattern. (name nil = don't bind)
    PatternRest = TypedData.define(name: ->(v) { IDENTIFIER === v || v.nil? })

    module Expression
      # Atom literal (incl NULL)
      Lit = TypedData.define(value: Atom)

      # `!expr` or bare `!` (payload nil = !null)
      ErrLit = TypedData.define(payload: ->(v) { Expression === v || v.nil? })

      ArrLit = TypedData.define(items: ->(v) { v.is_a?(Array) && v.all? { |e| ArrayItem === e || ArraySpread === e } })

      # [KeyValuePair|ObjectSpread], distinct fixed keys
      ObjLit = TypedData.define(pairs: ->(v) {
        v.is_a?(Array) &&
          v.all? { |m| KeyValuePair === m || ObjectSpread === m } &&
          v.filter_map { |m| m.key if KeyValuePair === m }.then { |keys| keys.uniq.size == keys.size }
      })

      # [] = the empty function
      FuncLit = TypedData.define(clauses: ->(v) { v.is_a?(Array) && v.all? { |c| Clause === c } })

      # Read a builtin/bound name
      Ident = TypedData.define(name: IDENTIFIER)

      FileRef = TypedData.define(variety: ->(v) { [:self, :super, :super_name, :name, :path].include?(v) }, path: ->(v) { String === v || v.nil? })

      # `left | right`
      Pipe = TypedData.define(left: Expression, right: Expression)

      # `obj.key`
      Member = TypedData.define(obj: Expression, key: IDENTIFIER)

      # `obj[expr]`
      Index = TypedData.define(obj: Expression, idx: Expression)

      # `obj[expr = expr]`
      IndexSet = TypedData.define(obj: Expression, idx: Expression, value: Expression)

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end

    module Pattern
      # literal pattern
      PLit = TypedData.define(value: Atom)

      # `!` or `!pat` ; inner=PWild matches any error
      PErr = TypedData.define(inner: Pattern)

      # binds
      PBind = TypedData.define(name: IDENTIFIER)

      # `_`
      PWild = TypedData.define(dummy: NilClass)

      # [PatternItem|PatternRest], at most one rest
      PArr = TypedData.define(items: ->(v) {
        v.is_a?(Array) &&
          v.all? { |e| PatternItem === e || PatternRest === e } &&
          v.count { |e| PatternRest === e } <= 1
      })

      # [PatternPair|PatternRest], one rest, distinct keys
      PObj = TypedData.define(pairs: ->(v) {
        v.is_a?(Array) &&
          v.all? { |m| PatternPair === m || PatternRest === m } &&
          v.count { |m| PatternRest === m } <= 1 &&
          v.filter_map { |m| m.key if PatternPair === m }.then { |keys| keys.uniq.size == keys.size }
      })

      # `inner ? predicate`
      PGuard = TypedData.define(inner: Pattern, pred_expr: Expression)

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end

    module Statement
      # The only statement. Only allowed in the REPL. `name = expression`.
      Assignment = TypedData.define(name: IDENTIFIER, expression: Expression)

      constants.each do |name|
        node = const_get(name)
        node.include(self) if node.is_a?(Class) && node < Data
      end
    end
  end
end
