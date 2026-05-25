module Fusion
  # =========================================================================
  # PARSER  (recursive descent following the EBNF)
  # =========================================================================
  class Parser
    def initialize(tokens)
      @toks = tokens
      @i = 0
    end

    def self.parse_file(src)
      toks = Lexer.new(src).tokens
      p = new(toks)
      expr = p.parse_expr
      p.expect(:eof)
      expr
    end

    def parse_expr = parse_pipe

    def parse_pipe
      left = parse_postfix
      while at?(:pipe)
        advance
        right = parse_postfix
        left = Expression::Pipe.new(left, right)
      end
      left
    end

    def parse_postfix
      node = parse_primary
      loop do
        if at?(:dot)
          advance
          key = expect(:ident).value
          node = Expression::Member.new(node, key)
        elsif at?(:lbracket)
          advance
          idx = parse_expr
          expect(:rbracket)
          node = Expression::Index.new(node, idx)
        else
          break
        end
      end
      node
    end

    def parse_primary
      t = peek
      case t.type
      when :number, :string then advance; Expression::Literal.new(t.value)
      when :true_kw, :false_kw, :null_kw then advance; Expression::Literal.new(t.value)
      when :bang then advance; Expression::Literal.new(ERROR)
      when :lbracket then parse_array
      when :lbrace then parse_object
      when :lparen then parse_function_or_group
      when :ident then advance; Expression::Identifier.new(t.value)
      when :at then parse_fileref
      else raise ParseError, "Unexpected token #{t.type} (#{t.value.inspect}) at #{t.pos}"
      end
    end

    def parse_fileref
      expect(:at)
      # refpath: { "../" } segment { "/" segment }
      parts = []
      while at?(:dot) && peek(1)&.type == :dot
        # ".." then "/"
        advance; advance # consume the two dots of ..
        parts << ".."
        expect(:slash)
      end
      parts << expect(:ident).value
      while at?(:slash)
        advance
        parts << expect(:ident).value
      end
      Expression::FileReference.new(parts.join("/"))
    end

    def parse_array
      expect(:lbracket)
      elems = []
      until at?(:rbracket)
        if at?(:spread)
          advance
          elems << [:spread, parse_expr]
        else
          elems << [:item, parse_expr]
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbracket)
      Expression::ArrayLiteral.new(elems)
    end

    def parse_object
      expect(:lbrace)
      members = []
      until at?(:rbrace)
        if at?(:spread)
          advance
          members << [:spread, parse_expr]
        else
          key = expect(:string).value
          expect(:colon)
          members << [:kv, key, parse_expr]
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbrace)
      Expression::ObjectLiteral.new(members)
    end

    # A "(" can begin either a grouped expression or a function literal.
    # Distinguish by trying to parse a clause: a function is a comma-separated
    # list of `pattern => expr`. We detect a function by scanning for `=>`
    # before the matching `)` at depth 0.
    def parse_function_or_group
      expect(:lparen)
      if looks_like_function?
        clauses = []
        loop do
          pat = parse_pattern
          expect(:arrow)
          body = parse_expr
          clauses << [pat, body]
          if at?(:comma)
            advance
            break if at?(:rparen) # trailing comma
          else
            break
          end
        end
        expect(:rparen)
        Expression::FunctionLiteral.new(clauses)
      else
        e = parse_expr
        expect(:rparen)
        e
      end
    end

    # Look ahead from current position (just after "(") to decide if this is a
    # function literal: is there a top-level "=>" before the matching ")"?
    def looks_like_function?
      depth = 0
      j = @i
      while j < @toks.length
        t = @toks[j]
        case t.type
        when :lparen, :lbracket, :lbrace then depth += 1
        when :rparen, :rbracket, :rbrace
          return false if depth.zero? # hit our closing ) first
          depth -= 1
        when :arrow
          return true if depth.zero?
        when :eof
          return false
        end
        j += 1
      end
      false
    end

    # ---- Patterns ----
    def parse_pattern
      inner = parse_corepat
      if at?(:question)
        advance
        pred = parse_postfix # predicate is a postfix-level expr (fn value)
        Pattern::Guard.new(inner, pred)
      else
        inner
      end
    end

    def parse_corepat
      t = peek
      case t.type
      when :number, :string then advance; Pattern::Literal.new(t.value)
      when :true_kw, :false_kw, :null_kw then advance; Pattern::Literal.new(t.value)
      when :bang then advance; Pattern::Literal.new(ERROR)
      when :lbracket then parse_arraypat
      when :lbrace then parse_objectpat
      when :ident
        advance
        t.value == "_" ? Pattern::Wildcard.new(nil) : Pattern::Binding.new(t.value)
      else
        raise ParseError, "Unexpected token in pattern: #{t.type} at #{t.pos}"
      end
    end

    def parse_arraypat
      expect(:lbracket)
      elems = []
      until at?(:rbracket)
        if at?(:spread)
          advance
          name = at?(:ident) ? advance.value : nil
          elems << [:rest, name]
        else
          elems << [:pat, parse_pattern]
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbracket)
      Pattern::Array.new(elems)
    end

    def parse_objectpat
      expect(:lbrace)
      members = []
      until at?(:rbrace)
        if at?(:spread)
          advance
          name = at?(:ident) ? advance.value : nil
          members << [:rest, name]
        else
          key = expect(:string).value
          expect(:colon)
          members << [:kv, key, parse_pattern]
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbrace)
      Pattern::Object.new(members)
    end

    # ---- token helpers ----
    def peek(o = 0) = @toks[@i + o]
    def at?(type) = peek.type == type
    def advance = (@toks[@i].tap { @i += 1 })
    def expect(type)
      t = peek
      raise ParseError, "Expected #{type} but got #{t.type} (#{t.value.inspect}) at #{t.pos}" unless t.type == type
      advance
    end
  end
end
