# frozen_string_literal: true

# === Value ===
#
# An atomic runtime value.

require_relative "typed_data"
require_relative "null"

module Fusion
  # A scalar literal value: the JSON atoms plus NULL (everything the lexer
  # emits as a token value, see Lexer#lex_number and #lex_word).
  Atom = ->(v) {
    v == NULL ||  v == true || v == false ||
      v.is_a?(Integer) || v.is_a?(Float) || v.is_a?(String)
  }
end
