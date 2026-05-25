module Fusion
  # =========================================================================
  # LEXER
  # =========================================================================
  Token = Struct.new(:type, :value, :pos)

  class Lexer
    PUNCT = {
      "(" => :lparen, ")" => :rparen,
      "[" => :lbracket, "]" => :rbracket,
      "{" => :lbrace, "}" => :rbrace,
      "," => :comma, ":" => :colon,
      "|" => :pipe, "?" => :question, "." => :dot,
      "@" => :at, "/" => :slash,
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
      return Token.new(:eof, nil, start) if c.nil?

      # "=>" and "..." and "//" handled specially
      if c == "=" && peek(1) == ">"
        @i += 2
        return Token.new(:arrow, "=>", start)
      end
      if c == "." && peek(1) == "." && peek(2) == "."
        @i += 3
        return Token.new(:spread, "...", start)
      end
      if c == "!"
        @i += 1
        return Token.new(:bang, "!", start)
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
        return Token.new(type, c, start)
      end
      raise ParseError, "Unexpected character #{c.inspect} at #{start}"
    end

    def skip_trivia
      loop do
        c = peek
        if c == " " || c == "\t" || c == "\n" || c == "\r"
          @i += 1
        elsif c == "/" && peek(1) == "/"
          @i += 2
          @i += 1 until peek.nil? || peek == "\n"
        elsif c == "/" && peek(1) == "*"
          @i += 2
          @i += 1 until peek.nil? || (peek == "*" && peek(1) == "/")
          @i += 2 unless peek.nil?
        else
          break
        end
      end
    end

    def lex_string(start)
      @i += 1 # opening quote
      buf = +""
      while (c = peek)
        if c == '"'
          @i += 1
          return Token.new(:string, buf, start)
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
                   [hex.to_i(16)].pack("U")
                 else
                   raise ParseError, "Bad escape \\#{e}"
                 end
          @i += 1
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
      Token.new(:number, val, start)
    end

    def lex_word(start)
      j = @i
      j += 1 while j < @n && ident_part?(@src[j])
      text = @src[@i...j]
      @i = j
      case text
      when "true"  then Token.new(:true_kw, true, start)
      when "false" then Token.new(:false_kw, false, start)
      when "null"  then Token.new(:null_kw, NULL, start)
      else Token.new(:ident, text, start)
      end
    end

    def digit?(c) = c && c >= "0" && c <= "9"
    def ident_start?(c) = c && (c =~ /[A-Za-z_]/)
    def ident_part?(c) = c && (c =~ /[A-Za-z0-9_]/)
  end
end
