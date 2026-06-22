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

    # Parse one REPL entry — a statement (`identifier "=" expr`) or a bare
    # expression — returning an AST::Statement::Assignment / AST::Expression, or, like
    # parse_file, a standardized syntax_error value instead of ever raising. The
    # REPL uses the error/non-error distinction to tell "keep editing" (didn't
    # parse yet) from "evaluate now" (a complete statement or expression).
    def self.parse_repl(src, location:)
      toks = Lexer.new(src).tokens
      p = new(toks)
      entry = p.parse_repl_entry
      p.expect(:eof)
      entry
    rescue ParseError => err
      Interpreter::ErrorVal.internal(kind: "syntax_error", location: location, operation: "parsing", input: src, message: err.message)
    end

    # A leading `identifier =` marks a statement; anything else is an expression.
    # (A bare identifier is itself a valid expression, so the `=` is the decider.)
    def parse_repl_entry
      if at?(:ident) && peek(1)&.type == :equals
        parse_statement
      else
        parse_expr
      end
    end

    # statement = identifier "=" expr   (REPL only; files contain one expr)
    def parse_statement
      name = expect(:ident).value
      expect(:equals)
      AST::Statement::Assignment.new(name: name, expression: parse_expr)
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
      when :atat then advance; Expression::FileRef.new(variety: :super, path: nil)
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
      items = []
      until at?(:rbracket)
        if at?(:spread)
          advance
          items << ArraySpread.new(value: parse_expr)
        else
          items << ArrayItem.new(value: parse_expr)
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbracket)
      Expression::ArrLit.new(items: items)
    end

    # Fixed keys must be distinct (the ObjLit data rule); a repeat is a clean
    # syntax_error. Keys arriving via `...spread` are dynamic and not checked.
    def parse_object
      expect(:lbrace)
      pairs = []
      keys = []
      until at?(:rbrace)
        if at?(:spread)
          advance
          pairs << ObjectSpread.new(value: parse_expr)
        else
          key_tok = expect(:string)
          key = key_tok.value
          raise ParseError, "duplicate key #{key.inspect} (at #{key_tok.pos})" if keys.include?(key)
          keys << key
          expect(:colon)
          pairs << KeyValuePair.new(key: key, value: parse_expr)
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbrace)
      Expression::ObjLit.new(pairs: pairs)
    end

    # A "(" begins a grouped expression, a function literal, or — when empty —
    # the clause-less function `()`. A function is a comma-separated list of
    # `pattern => expr`; we detect one by scanning for a top-level `=>` before the
    # matching `)`. `()` matches nothing (so it yields null for any normal input
    # and propagates errors).
    def parse_function_or_group
      expect(:lparen)
      if at?(:rparen)
        advance
        return Expression::FuncLit.new(clauses: [])
      end
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
    #   pattern   = p_error | p_guarded
    #   p_error   = "!" | "!" p_guarded
    #   p_guarded = p_core [ "?" predicate ]
    #   p_core    = p_literal | p_bind | p_wildcard | p_array | p_object
    # Note: `p_core` does NOT include p_error. The "no nested !pat" property
    # falls out of the grammar shape — `p_error` is only reachable from `pattern`
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
        # A predicate is a full pipe so it may chain functions: `a ? b | c` tests
        # `a | b | c`. It stops at `=>`, `,`, `]`, `}`, `)` like any expression.
        pred = parse_pipe
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

    # p_array (reference.md §2.5). Items are `p_guarded`s — never error patterns.
    # The grammar's two arms (with / without a rest) become two phases: the loop
    # parses leading items up to an optional single `...rest`; once a rest is
    # consumed, the inner loop parses trailing items only, so a second `...` lands
    # in `parse_guardedpat` as an unexpected token. There is no `seen_rest` flag —
    # "at most one rest" is enforced by the shape of the loop.
    def parse_arraypat
      expect(:lbracket)
      items = []
      until at?(:rbracket)
        if at?(:spread)
          items << parse_pattern_rest
          while at?(:comma)
            advance
            break if at?(:rbracket) # trailing comma
            raise ParseError, "a pattern may contain at most one `...rest` (at #{peek.pos})" if at?(:spread)
            items << PatternItem.new(pattern: parse_guardedpat)
          end
          break
        end
        items << PatternItem.new(pattern: parse_guardedpat)
        break unless at?(:comma)
        advance
      end
      expect(:rbracket)
      Pattern::PArr.new(items: items)
    end

    # p_object (reference.md §2.5). Leading pairs up to an optional single
    # `...rest`, which must come last — only a trailing comma may follow it. Keys
    # must be distinct (the PObj data rule); a repeat is a clean syntax_error.
    def parse_objectpat
      expect(:lbrace)
      pairs = []
      keys = []
      until at?(:rbrace)
        if at?(:spread)
          pairs << parse_pattern_rest
          advance if at?(:comma) && peek(1)&.type == :rbrace # trailing comma
          unless at?(:rbrace)
            raise ParseError, "in an object pattern, `...rest` must come last (at #{peek.pos})"
          end
          break
        end
        key_pos = peek.pos
        pair = parse_pattern_pair
        raise ParseError, "duplicate key #{pair.key.inspect} (at #{key_pos})" if keys.include?(pair.key)
        keys << pair.key
        pairs << pair
        break unless at?(:comma)
        advance
      end
      expect(:rbrace)
      Pattern::PObj.new(pairs: pairs)
    end

    # p_rest = "..." [ identifier ] — the single rest binder, shared by array and
    # object patterns. Callers parse it only at a rest position and then continue
    # with items/pairs only, which is what holds a pattern to one rest.
    def parse_pattern_rest
      expect(:spread)
      name = at?(:ident) ? advance.value : nil
      PatternRest.new(name: name)
    end

    # p_pair = string ":" p_guarded
    def parse_pattern_pair
      key = expect(:string).value
      expect(:colon)
      PatternPair.new(key: key, pattern: parse_guardedpat)
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
