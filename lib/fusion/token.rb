# frozen_string_literal: true

# === Data Structure ===
#
# Array<Token> is
# - output of the lexer
# - input of the parser

module Fusion
  Token = Struct.new(:type, :value, :pos)
end
