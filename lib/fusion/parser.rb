# frozen_string_literal: true

# === Transformation ===
#
# Recursive descent parser following the EBNF
#
# Input: Array<Token>
# Output: AST::Expression

require_relative "token"
require_relative "ast"
require_relative "interpreter/error_val"

module Fusion
  class Parser
    include AST

    def initialize(tokens)
      @toks = tokens
      @i = 0
    end

    # Parse a complete program. The lexer and parser report failures by raising
    # ParseError; this single entry point rescues them and returns a standardized
    # syntax_error value, so no caller ever sees a raw Ruby error. `location` is the
    # syntax_error's "code X" / "code <inline>" context.
    def self.parse_file(src, location:)
      toks = Lexer.new(src).tokens
      p = new(toks)
      expr = p.parse_expr
      p.expect(:eof)
      expr
    rescue ParseError => err
      Interpreter::ErrorVal.internal(kind: "syntax_error", location: location, operation: "parsing", input: src, message: err.message)
    end

    def parse_expr
      parse_pipe
    end

    def parse_pipe
      left = parse_prefix
      while at?(:pipe)
        advance
        right = parse_prefix
        left = Expression::Pipe.new(left: left, right: right)
      end
      left
    end

    # Tokens that can begin a primary expression (used by parse_prefix to decide
    # whether `!` is followed by an operand).
    PRIMARY_STARTERS = %i[number string true_kw false_kw null_kw bang
                          lbracket lbrace lparen ident at].freeze

    # `!` is a prefix operator that constructs an error from its operand. A bare
    # `!` (no operand follows) is shorthand for `!null`. Binds tighter than `|`
    # so `!x | f` is `(!x) | f`; looser than postfix so `!x.foo` is `!(x.foo)`.
    def parse_prefix
      if at?(:bang)
        advance
        if PRIMARY_STARTERS.include?(peek.type)
          Expression::ErrLit.new(payload: parse_prefix)   # allow !!x to nest
        else
          Expression::ErrLit.new(payload: nil)            # bare ! -> !null
        end
      else
        parse_postfix
      end
    end

    def parse_postfix
      node = parse_primary
      loop do
        if at?(:dot)
          advance
          key = expect(:ident).value
          node = Expression::Member.new(obj: node, key: key)
        elsif at?(:lbracket)
          advance
          idx = parse_expr
          expect(:rbracket)
          node = Expression::Index.new(obj: node, idx: idx)
        else
          break
        end
      end
      node
    end

    def parse_primary
      t = peek
      case t.type
      when :number, :string then advance; Expression::Lit.new(value: t.value)
      when :true_kw, :false_kw, :null_kw then advance; Expression::Lit.new(value: t.value)
      when :lbracket then parse_array
      when :lbrace then parse_object
      when :lparen then parse_function_or_group
      when :ident then advance; Expression::Ident.new(name: t.value)
      when :at then parse_fileref
      else raise ParseError, "Unexpected token #{t.type} (#{t.value.inspect}) at #{t.pos}"
      end
    end

    def parse_fileref
      expect(:at)
      # Bare "@" = current file: not followed by something that can begin a path.
      nxt = peek
      starts_path = (nxt.type == :ident) || (nxt.type == :dot && peek(1)&.type == :dot)
      return Expression::FileRef.new(variety: :self, path: nil) unless starts_path
      # refpath: { "../" } segment { "/" segment }
      parts = []
      has_dotdot = false
      while at?(:dot) && peek(1)&.type == :dot
        advance; advance # consume the two dots of ..
        parts << ".."
        expect(:slash)
        has_dotdot = true
      end
      parts << expect(:ident).value
      while at?(:slash)
        advance
        parts << expect(:ident).value
      end
      # A reference is eligible for builtin/stdlib fallback (:name) iff it does NOT
      # contain "../". Downward paths like "dir/a" are still eligible; only "../"
      # (escaping upward) forces pure file-path (:path) resolution.
      bare = !has_dotdot
      Expression::FileRef.new(variety: bare ? :name : :path, path: parts.join("/"))
    end

    def parse_array
      expect(:lbracket)
      elems = []
      until at?(:rbracket)
        if at?(:spread)
          advance
          elems << ArraySpread.new(value: parse_expr)
        else
          elems << ArrayItem.new(value: parse_expr)
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbracket)
      Expression::ArrLit.new(elems: elems)
    end

    def parse_object
      expect(:lbrace)
      members = []
      until at?(:rbrace)
        if at?(:spread)
          advance
          members << ObjectSpread.new(value: parse_expr)
        else
          key = expect(:string).value
          expect(:colon)
          members << KeyValuePair.new(key: key, value: parse_expr)
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbrace)
      Expression::ObjLit.new(members: members)
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
          clauses << Clause.new(pattern: pat, body: body)
          if at?(:comma)
            advance
            break if at?(:rparen) # trailing comma
          else
            break
          end
        end
        expect(:rparen)
        Expression::FuncLit.new(clauses: clauses)
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
    # ---- Pattern grammar (mirrors reference.md §2.5 EBNF) ------------------
    #   pattern    = errpat | guardedpat
    #   errpat     = "!" | "!" guardedpat
    #   guardedpat = corepat [ "?" predicate ]
    #   corepat    = literalpat | bindpat | wildcard | arraypat | objectpat
    # Note: `corepat` does NOT include errpat. The "no nested !pat" property
    # falls out of the grammar shape — `errpat` is only reachable from `pattern`
    # (a clause's top level), never from inside arrays, objects, or another
    # error's payload. No flag-threading is needed.
    def parse_pattern
      at?(:bang) ? parse_errpat : parse_guardedpat
    end

    # Tokens that can begin a `guardedpat` (used to detect whether `!` is
    # followed by a payload pattern or stands alone).
    GUARDEDPAT_STARTERS = %i[number string true_kw false_kw null_kw
                             lbracket lbrace ident].freeze

    def parse_errpat
      expect(:bang)
      if GUARDEDPAT_STARTERS.include?(peek.type)
        Pattern::PErr.new(inner: parse_guardedpat)               # "!" guardedpat
      else
        Pattern::PErr.new(inner: Pattern::PWild.new(dummy: nil)) # bare "!" — matches any error, binds nothing
      end
    end

    def parse_guardedpat
      inner = parse_corepat
      if at?(:question)
        advance
        pred = parse_prefix
        Pattern::PGuard.new(inner: inner, pred_expr: pred)
      else
        inner
      end
    end

    def parse_corepat
      t = peek
      case t.type
      when :number, :string then advance; Pattern::PLit.new(value: t.value)
      when :true_kw, :false_kw, :null_kw then advance; Pattern::PLit.new(value: t.value)
      when :lbracket then parse_arraypat
      when :lbrace then parse_objectpat
      when :ident
        advance
        t.value == "_" ? Pattern::PWild.new(dummy: nil) : Pattern::PBind.new(name: t.value)
      when :bang
        # `!pat` is only valid as a clause's top-level pattern, never inside an
        # array element, object member, or error payload.
        raise ParseError, "`!pat` may only appear as a clause's top-level pattern (at #{t.pos})"
      else
        raise ParseError, "Unexpected token in pattern: #{t.type} at #{t.pos}"
      end
    end

    def parse_arraypat
      # Array elements are `guardedpat`s — they cannot be error patterns.
      expect(:lbracket)
      elems = []
      until at?(:rbracket)
        if at?(:spread)
          advance
          name = at?(:ident) ? advance.value : nil
          elems << PatternRest.new(name: name)
        else
          elems << PatternItem.new(pattern: parse_guardedpat)
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbracket)
      Pattern::PArr.new(elems: elems)
    end

    def parse_objectpat
      # Object members are `guardedpat`s — they cannot be error patterns.
      expect(:lbrace)
      members = []
      until at?(:rbrace)
        if at?(:spread)
          advance
          name = at?(:ident) ? advance.value : nil
          members << PatternRest.new(name: name)
        else
          key = expect(:string).value
          expect(:colon)
          members << PatternPair.new(key: key, pattern: parse_guardedpat)
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbrace)
      Pattern::PObj.new(members: members)
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
