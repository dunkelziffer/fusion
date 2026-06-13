# frozen_string_literal: true

# === Transformation ===
#
# Input: String (source code)
# Output: Array<Token>

require_relative "token"
require_relative "null"

module Fusion
  class Lexer
    PUNCT = {
      "(" => :lparen, ")" => :rparen,
      "[" => :lbracket, "]" => :rbracket,
      "{" => :lbrace, "}" => :rbrace,
      "," => :comma, ":" => :colon,
      "|" => :pipe, "?" => :question, "." => :dot,
      "@" => :at, "/" => :slash,
      "=" => :equals,
    }.freeze

    def initialize(src)
      @src = src
      @i = 0
      @n = src.length
    end

    def tokens
      out = []
      loop do
        t = next_token
        out << t
        break if t.type == :eof
      end
      out
    end

    private

    def peek(o = 0) = @i + o < @n ? @src[@i + o] : nil

    def next_token
      skip_trivia
      start = @i
      c = peek
      return Token.new(type: :eof, value: nil, pos: start) if c.nil?

      # "=>" and "..." handled specially ("#" line comments handled in skip_trivia)
      if c == "=" && peek(1) == ">"
        @i += 2
        return Token.new(type: :arrow, value: "=>", pos: start)
      end
      if c == "." && peek(1) == "." && peek(2) == "."
        @i += 3
        return Token.new(type: :spread, value: "...", pos: start)
      end
      if c == "!"
        @i += 1
        return Token.new(type: :bang, value: "!", pos: start)
      end
      if c == '"'
        return lex_string(start)
      end
      if digit?(c) || (c == "-" && digit?(peek(1)))
        return lex_number(start)
      end
      if ident_start?(c)
        return lex_word(start)
      end
      if (type = PUNCT[c])
        @i += 1
        return Token.new(type: type, value: c, pos: start)
      end
      raise ParseError, "Unexpected character #{c.inspect} at #{start}"
    end

    def skip_trivia
      loop do
        c = peek
        if c == " " || c == "\t" || c == "\n" || c == "\r"
          @i += 1
        elsif c == "#" && at_line_start?
          # A line is a comment iff its first non-whitespace char is "#".
          # This also covers shebang lines (#!) for free.
          @i += 1 until peek.nil? || peek == "\n"
        else
          break
        end
      end
    end

    # True when only whitespace precedes @i on the current physical line.
    def at_line_start?
      j = @i - 1
      j -= 1 while j >= 0 && (@src[j] == " " || @src[j] == "\t")
      j < 0 || @src[j] == "\n" || @src[j] == "\r"
    end

    def lex_string(start)
      @i += 1 # opening quote
      buf = +""
      while (c = peek)
        if c == '"'
          @i += 1
          return Token.new(type: :string, value: buf, pos: start)
        elsif c == "\\"
          @i += 1
          e = peek
          buf << case e
                 when '"' then '"'
                 when "\\" then "\\"
                 when "/" then "/"
                 when "n" then "\n"
                 when "t" then "\t"
                 when "r" then "\r"
                 when "b" then "\b"
                 when "f" then "\f"
                 when "u"
                   hex = @src[@i + 1, 4]
                   @i += 4
                   code_point = hex.to_i(16)
                   # Reject surrogates and out-of-range code points up front:
                   # pack("U") would otherwise build an invalid-encoding string
                   # whose malformed-UTF-8 error surfaces far downstream.
                   if code_point.between?(0xD800, 0xDFFF) || code_point > 0x10FFFF
                     raise ParseError, "Invalid unicode escape \\u#{hex}"
                   end
                   [code_point].pack("U")
                 else
                   raise ParseError, "Bad escape \\#{e}"
                 end
          @i += 1
        elsif c == "\n" || c == "\r"
          raise ParseError, "Raw newline in string starting at #{start}; use \\n"
        else
          buf << c
          @i += 1
        end
      end
      raise ParseError, "Unterminated string starting at #{start}"
    end

    def lex_number(start)
      j = @i
      j += 1 if @src[j] == "-"
      j += 1 while j < @n && digit?(@src[j])
      is_float = false
      if @src[j] == "." && digit?(@src[j + 1])
        is_float = true
        j += 1
        j += 1 while j < @n && digit?(@src[j])
      end
      if (@src[j] == "e" || @src[j] == "E")
        is_float = true
        j += 1
        j += 1 if (@src[j] == "+" || @src[j] == "-")
        j += 1 while j < @n && digit?(@src[j])
      end
      text = @src[@i...j]
      @i = j
      val = is_float ? text.to_f : text.to_i
      Token.new(type: :number, value: val, pos: start)
    end

    def lex_word(start)
      j = @i
      j += 1 while j < @n && ident_part?(@src[j])
      text = @src[@i...j]
      @i = j
      case text
      when "true"  then Token.new(type: :true_kw, value: true, pos: start)
      when "false" then Token.new(type: :false_kw, value: false, pos: start)
      when "null"  then Token.new(type: :null_kw, value: NULL, pos: start)
      else Token.new(type: :ident, value: text, pos: start)
      end
    end

    def digit?(c) = c && c >= "0" && c <= "9"
    def ident_start?(c) = c && (c =~ /[A-Za-z_]/)
    def ident_part?(c) = c && (c =~ /[A-Za-z0-9_]/)
  end
end
