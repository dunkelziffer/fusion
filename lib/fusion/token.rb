# frozen_string_literal: true

# === Data Structure ===
#
# Array<Token> is
# - output of the lexer
# - input of the parser

require_relative "typed_data"
require_relative "atom"

module Fusion
  # type:  one of the lexer's token-type symbols (:number, :ident, :lparen, ...).
  # value: the token's payload — a scalar for literals/keywords, the matched
  #        text for punctuation/identifiers, or nil for :eof.
  # pos:   the token's source offset.
  Token = TypedData.define(
    type: Symbol,
    value: ->(v) { Atom === v || v.nil? },
    pos: Integer,
  )
end
