#!/usr/bin/env ruby
# frozen_string_literal: true

# Fusion — a proof-of-concept interpreter.
#
# This file is the interpreter library; the CLI entrypoint lives in exe/fusion.
#
# A file contains exactly one value. A file is "executable" if that value is a
# function; the runtime computes  STDIN | thatFunction  and prints the result.
#
# Values are represented in Ruby as:
#   null   -> :null            (we avoid Ruby nil so "absent" is explicit)
#   !      -> ErrorVal (always carries a payload; bare `!` means `!null`)
#   bool   -> true / false
#   int    -> Integer
#   float  -> Float
#   string -> String
#   array  -> Array
#   object -> Hash (String keys, insertion-ordered as Ruby preserves)
#   func   -> Func (closure over an Env)

require_relative "fusion/version"

module Fusion
  # ---- Special singletons -------------------------------------------------
  NULL  = :null

  # An error value, always carrying a payload (any JSON-like Fusion value).
  # `mkerr(payload)` constructs one; a bare `!` in source means `!null`.
  class ErrorVal
    attr_reader :payload
    def initialize(payload) @payload = payload end
    def inspect = "!#{payload.inspect}"
    def to_s = inspect
  end
  def self.mkerr(payload = NULL) = ErrorVal.new(payload)
  def self.error?(v) = v.is_a?(ErrorVal)

  class FusionError < StandardError; end
  class ParseError < FusionError; end

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

      # "=>" and "..." handled specially ("#" line comments handled in skip_trivia)
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

  # =========================================================================
  # AST
  # =========================================================================
  # Expressions
  Lit       = Struct.new(:value)                 # atom literal (incl NULL)
  ErrLit    = Struct.new(:payload)               # !expr or bare ! (payload nil = !null)
  ArrLit    = Struct.new(:elems)                 # elems: [[:item|:spread, expr], ...]
  ObjLit    = Struct.new(:members)               # [[:kv, key, expr] | [:spread, expr]]
  FuncLit   = Struct.new(:clauses)               # [[pattern, expr], ...]
  Ident     = Struct.new(:name)                  # read a builtin/bound name
  FileRef   = Struct.new(:variety, :path)        # variety: :self|:name|:path
  Pipe      = Struct.new(:left, :right)          # left | right
  Member    = Struct.new(:obj, :key)             # obj.key
  Index     = Struct.new(:obj, :idx)             # obj[expr]

  # Patterns
  PLit      = Struct.new(:value)                 # literal pattern
  PErr      = Struct.new(:inner)                 # ! or !pat ; inner=nil matches any error
  PBind     = Struct.new(:name)                  # binds
  PWild     = Struct.new(:dummy)                 # _
  PArr      = Struct.new(:elems)                 # [[:pat,p]|[:rest,name_or_nil], ...]
  PObj      = Struct.new(:members)               # [[:kv,key,pat]|[:rest,name_or_nil]]
  PGuard    = Struct.new(:inner, :pred_expr)     # inner ? predicate

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
      left = parse_prefix
      while at?(:pipe)
        advance
        right = parse_prefix
        left = Pipe.new(left, right)
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
          ErrLit.new(parse_prefix)            # allow !!x to nest
        else
          ErrLit.new(nil)                     # bare ! -> !null
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
          node = Member.new(node, key)
        elsif at?(:lbracket)
          advance
          idx = parse_expr
          expect(:rbracket)
          node = Index.new(node, idx)
        else
          break
        end
      end
      node
    end

    def parse_primary
      t = peek
      case t.type
      when :number, :string then advance; Lit.new(t.value)
      when :true_kw, :false_kw, :null_kw then advance; Lit.new(t.value)
      when :lbracket then parse_array
      when :lbrace then parse_object
      when :lparen then parse_function_or_group
      when :ident then advance; Ident.new(t.value)
      when :at then parse_fileref
      else raise ParseError, "Unexpected token #{t.type} (#{t.value.inspect}) at #{t.pos}"
      end
    end

    def parse_fileref
      expect(:at)
      # Bare "@" = current file: not followed by something that can begin a path.
      nxt = peek
      starts_path = (nxt.type == :ident) || (nxt.type == :dot && peek(1)&.type == :dot)
      return FileRef.new(:self, nil) unless starts_path
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
      FileRef.new(bare ? :name : :path, parts.join("/"))
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
      ArrLit.new(elems)
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
      ObjLit.new(members)
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
        FuncLit.new(clauses)
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
        PErr.new(parse_guardedpat)            # "!" guardedpat
      else
        PErr.new(PWild.new(nil))               # bare "!" — matches any error, binds nothing
      end
    end

    def parse_guardedpat
      inner = parse_corepat
      if at?(:question)
        advance
        pred = parse_prefix
        PGuard.new(inner, pred)
      else
        inner
      end
    end

    def parse_corepat
      t = peek
      case t.type
      when :number, :string then advance; PLit.new(t.value)
      when :true_kw, :false_kw, :null_kw then advance; PLit.new(t.value)
      when :lbracket then parse_arraypat
      when :lbrace then parse_objectpat
      when :ident
        advance
        t.value == "_" ? PWild.new(nil) : PBind.new(t.value)
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
          elems << [:rest, name]
        else
          elems << [:pat, parse_guardedpat]
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbracket)
      PArr.new(elems)
    end

    def parse_objectpat
      # Object members are `guardedpat`s — they cannot be error patterns.
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
          members << [:kv, key, parse_guardedpat]
        end
        break unless at?(:comma)
        advance
      end
      expect(:rbrace)
      PObj.new(members)
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

  # =========================================================================
  # RUNTIME VALUES
  # =========================================================================
  # A function closes over the environment in which it was defined.
  class Func
    attr_reader :clauses, :env
    def initialize(clauses, env)
      @clauses = clauses # [[pattern, expr_ast], ...]
      @env = env
    end
    def inspect = "<func/#{clauses.length}>"
  end

  # Lazy, memoized reference to a file's value (a "thunk" / promise).
  class FileThunk
    def initialize(loader, abspath)
      @loader = loader
      @abspath = abspath
      @state = :unforced # :unforced | :forcing | :done
      @value = nil
    end

    def force
      case @state
      when :done then @value
      when :forcing
        # We are already evaluating this file and were asked for it again
        # without any intervening function boundary => non-productive data cycle.
        Fusion.mkerr({"kind" => "data_cycle", "path" => @abspath})
      else
        @state = :forcing
        @value = @loader.evaluate_file(@abspath)
        @state = :done
        @value
      end
    end
  end

  # Environment: maps names -> values, with a parent chain. Built-ins live at root.
  class Env
    def initialize(parent = nil)
      @vars = {}
      @parent = parent
    end

    def define(name, value)
      @vars[name] = value
      self
    end

    def lookup(name)
      if @vars.key?(name)
        @vars[name]
      elsif @parent
        @parent.lookup(name)
      else
        :__unbound__
      end
    end

    def child(bindings = {})
      e = Env.new(self)
      bindings.each { |k, v| e.define(k, v) }
      e
    end
  end

  # =========================================================================
  # EVALUATOR
  # =========================================================================
  class Interpreter
    attr_reader :root_env

    def initialize(stdlib_dir: nil, env_vars: nil)
      @stdlib_dir = stdlib_dir
      @env_vars = env_vars || ENV.to_h
      @file_cache = {} # abspath -> FileThunk
      @ast_cache = {}  # abspath -> AST
      @builtins = {}   # name -> NativeFunc  (consulted by @name, not via env)
      Builtins.install(@builtins, self)
      @root_env = Env.new # holds no builtins now; bare identifiers are holes only
    end

    # ---- File loading -----------------------------------------------------
    def load_file(abspath)
      @file_cache[abspath] ||= FileThunk.new(self, abspath)
    end

    def evaluate_file(abspath)
      ast = (@ast_cache[abspath] ||= begin
        src = File.read(abspath)
        Parser.parse_file(src)
      end)
      # A file's value is evaluated in a fresh env whose parent is root (builtins),
      # plus knowledge of its own directory for resolving @refs.
      env = @root_env.child
      env.define("__dir__", File.dirname(abspath))
      env.define("__file__", abspath)
      eval_expr(ast, env)
    rescue Errno::ENOENT
      warn "[fusion] file not found: #{abspath}" if ENV["FUSION_DEBUG"]
      Fusion.mkerr({"kind" => "file_not_found", "path" => abspath})
    rescue ParseError => err
      warn "[fusion] parse error in #{abspath}: #{err.message}" if ENV["FUSION_DEBUG"]
      Fusion.mkerr({"kind" => "parse_error", "path" => abspath, "message" => err.message})
    end

    # Resolve a bare "@name": sibling file > builtin (incl. load, ENV) > stdlib > !.
    def resolve_name(name, dir)
      sib = File.expand_path(name + ".fsn", dir)
      return load_file(sib).force if File.exist?(sib)
      if name == "ENV"
        return @env_vars.dup
      end
      if name == "load"
        # @load is a builtin closure capturing the calling file's directory. It
        # loads a VERBATIM filename (no ".fsn" appended) so arbitrary names work.
        d = dir
        return NativeFunc.new("load", lambda do |v|
          next Fusion.mkerr({"kind" => "load_bad_arg", "got" => v.class.name}) unless v.is_a?(String)
          target = File.expand_path(v, d)
          next Fusion.mkerr({"kind" => "file_not_found", "path" => target}) unless File.exist?(target)
          load_file(target).force
        end)
      end
      return @builtins[name] if @builtins.key?(name)
      if @stdlib_dir
        std = File.join(@stdlib_dir, name + ".fsn")
        return load_file(std).force if File.exist?(std)
      end
      Fusion.mkerr({"kind" => "unresolved_ref", "name" => name})
    end

    # Resolve a pure path "@dir/a" or "@../a": file only, never builtin/stdlib.
    def resolve_path(relpath, dir)
      load_file(File.expand_path(relpath + ".fsn", dir)).force
    end

    # ---- Expression evaluation -------------------------------------------
    def eval_expr(node, env)
      case node
      when Lit then node.value
      when ErrLit
        # Bare `!` means `!null`; `!expr` wraps expr's value as an error.
        # If the payload expression itself errors, propagate THAT error rather
        # than wrapping it -- prevents accidental error-burying.
        if node.payload.nil?
          Fusion.mkerr(NULL)
        else
          p = eval_expr(node.payload, env)
          Fusion.error?(p) ? p : Fusion.mkerr(p)
        end
      when Ident
        v = env.lookup(node.name)
        v == :__unbound__ ? Fusion.mkerr({"kind" => "unbound", "name" => node.name}) : v
      when FileRef
        dir = env.lookup("__dir__")
        dir = Dir.pwd if dir == :__unbound__
        case node.variety
        when :self
          f = env.lookup("__file__")
          f == :__unbound__ ? Fusion.mkerr({"kind" => "no_current_file"}) : load_file(f).force
        when :name
          resolve_name(node.path, dir)
        else # :path
          resolve_path(node.path, dir)
        end
      when ArrLit then eval_array(node, env)
      when ObjLit then eval_object(node, env)
      when FuncLit then Func.new(node.clauses, env)
      when Pipe then eval_pipe(node, env)
      when Member then eval_member(node, env)
      when Index then eval_index(node, env)
      else raise FusionError, "Cannot evaluate node #{node.class}"
      end
    end

    # Array/object literals propagate any error encountered during construction.
    # Errors are not first-class: at any point during execution there is either
    # a value or an error in motion, never both.
    def eval_array(node, env)
      out = []
      node.elems.each do |kind, expr|
        v = eval_expr(expr, env)
        return v if Fusion.error?(v)
        if kind == :spread
          return Fusion.mkerr({"kind" => "spread_non_array", "got" => v.class.name}) unless v.is_a?(Array)
          out.concat(v)
        else
          out << v
        end
      end
      out
    end

    def eval_object(node, env)
      out = {}
      node.members.each do |m|
        if m[0] == :spread
          v = eval_expr(m[1], env)
          return v if Fusion.error?(v)
          return Fusion.mkerr({"kind" => "spread_non_object", "got" => v.class.name}) unless v.is_a?(Hash)
          out.merge!(v)
        else
          _, key, expr = m
          v = eval_expr(expr, env)
          return v if Fusion.error?(v)
          out[key] = v
        end
      end
      out
    end

    def eval_pipe(node, env)
      v = eval_expr(node.left, env)
      f = eval_expr(node.right, env)
      apply(f, v)
    end

    def eval_member(node, env)
      obj = eval_expr(node.obj, env)
      return obj if Fusion.error?(obj)
      return Fusion.mkerr({"kind" => "member_on_non_object", "key" => node.key}) unless obj.is_a?(Hash)
      return Fusion.mkerr({"kind" => "missing_key", "key" => node.key}) unless obj.key?(node.key)
      obj[node.key]
    end

    def eval_index(node, env)
      obj = eval_expr(node.obj, env)
      return obj if Fusion.error?(obj)
      idx = eval_expr(node.idx, env)
      return idx if Fusion.error?(idx)
      if obj.is_a?(Array) && idx.is_a?(Integer)
        i = idx >= 0 ? idx : obj.length + idx
        return obj[i] if i >= 0 && i < obj.length
        return Fusion.mkerr({"kind" => "index_out_of_range", "index" => idx, "length" => obj.length})
      elsif obj.is_a?(Hash) && idx.is_a?(String)
        return obj[idx] if obj.key?(idx)
        return Fusion.mkerr({"kind" => "missing_key", "key" => idx})
      end
      Fusion.mkerr({"kind" => "bad_index", "obj" => obj.class.name, "idx" => idx.class.name})
    end

    # ---- Application & matching ------------------------------------------
    def apply(f, v)
      # An errored function value propagates as-is (more useful than a generic
      # "applied a non-function" wrapper).
      return f if Fusion.error?(f)
      if f.is_a?(NativeFunc)
        # Uniform propagation: built-ins never receive errors as inputs.
        return v if Fusion.error?(v)
        return f.fn.call(v)
      end
      unless f.is_a?(Func)
        return Fusion.mkerr({"kind" => "apply_non_function", "got" => f.class.name})
      end
      f.clauses.each do |pattern, body|
        bindings = {}
        m = match(pattern, v, bindings, f.env)
        # A `?` predicate raised an error during matching: bubble it up as the
        # function's return value (no further clauses are tried).
        return m if Fusion.error?(m)
        if m
          return eval_expr(body, f.env.child(bindings))
        end
      end
      # No clause matched. If the input was an error, it keeps propagating
      # (an unmatched error must never be silently swallowed). Otherwise the
      # lenient default is `null`.
      Fusion.error?(v) ? v : NULL
    end

    # Returns true (match), false (no match), or an ErrorVal (predicate errored).
    def match(pattern, value, bindings, env)
      case pattern
      when PLit
        deep_equal?(pattern.value, value)
      when PErr
        # If the value is an error, match the inner pattern against its
        # payload. The inner is always a non-`!` pattern (the parser ensures
        # that), so for a bare `!` we synthesized PWild as the inner.
        return false unless Fusion.error?(value)
        match(pattern.inner, value.payload, bindings, env)
      when PWild
        # `_` matches anything EXCEPT an error value.
        !Fusion.error?(value)
      when PBind
        return false if Fusion.error?(value)    # binders never capture an error
        bindings[pattern.name] = value
        true
      when PArr
        match_array(pattern, value, bindings, env)
      when PObj
        match_object(pattern, value, bindings, env)
      when PGuard
        inner_res = match(pattern.inner, value, bindings, env)
        return inner_res if Fusion.error?(inner_res)
        return false unless inner_res
        pred = eval_expr(pattern.pred_expr, env)
        return pred if Fusion.error?(pred)       # predicate expression itself errored
        # The predicate sees whatever value reached this PGuard, which is
        # already the right value because `!pat ? pred` parses as
        # PErr(PGuard(pat, pred)) — by the time PGuard runs, the value is
        # already the payload.
        r = apply(pred, value)
        return r if Fusion.error?(r)             # predicate raised during application
        r == true
      else
        raise FusionError, "Unknown pattern #{pattern.class}"
      end
    end

    def match_array(pattern, value, bindings, env)
      return false unless value.is_a?(Array)
      elems = pattern.elems
      rest_index = elems.index { |e| e[0] == :rest }

      if rest_index.nil?
        return false unless value.length == elems.length
        elems.each_with_index do |(_, p), i|
          r = match(p, value[i], bindings, env)
          return r if Fusion.error?(r)
          return false unless r
        end
        true
      else
        before = elems[0...rest_index]
        after  = elems[(rest_index + 1)..]
        return false if value.length < before.length + after.length
        before.each_with_index do |(_, p), i|
          r = match(p, value[i], bindings, env)
          return r if Fusion.error?(r)
          return false unless r
        end
        after.each_with_index do |(_, p), k|
          vi = value.length - after.length + k
          r = match(p, value[vi], bindings, env)
          return r if Fusion.error?(r)
          return false unless r
        end
        rest_name = elems[rest_index][1]
        if rest_name
          mid = value[before.length...(value.length - after.length)]
          bindings[rest_name] = mid
        end
        true
      end
    end

    def match_object(pattern, value, bindings, env)
      return false unless value.is_a?(Hash)
      matched_keys = []
      rest_name = :__none__
      pattern.members.each do |m|
        if m[0] == :rest
          rest_name = m[1] # may be nil (ignore) or a string
        else
          _, key, p = m
          return false unless value.key?(key)
          r = match(p, value[key], bindings, env)
          return r if Fusion.error?(r)
          return false unless r
          matched_keys << key
        end
      end
      if rest_name != :__none__ && rest_name
        remaining = value.reject { |k, _| matched_keys.include?(k) }
        bindings[rest_name] = remaining
      end
      true
    end

    # ---- Equality & helpers ----------------------------------------------
    def error?(v) = Fusion.error?(v)

    def deep_equal?(a, b)
      return true if a.equal?(b)
      return false if a.class != b.class
      case a
      when Array
        a.length == b.length && a.each_index.all? { |i| deep_equal?(a[i], b[i]) }
      when Hash
        a.length == b.length && a.all? { |k, v| b.key?(k) && deep_equal?(v, b[k]) }
      else
        a == b
      end
    end
  end

  # =========================================================================
  # BUILT-INS  (Tier 0 primitives; everything else is written in Fusion)
  # =========================================================================
  module Builtins
    def self.install(table, interp)
      # Helper to construct an informative error from a builtin context.
      err = ->(fn, msg) { Fusion.mkerr("#{fn}: #{msg}") }
      define = ->(name, fn) { table[name] = NativeFunc.new(name, fn) }

      # --- arithmetic on a pair [a, b] (or unary for negate) ---
      pair_num = lambda do |v|
        return nil unless v.is_a?(Array) && v.length == 2
        a, b = v
        return nil unless a.is_a?(Numeric) && !(a == true || a == false) &&
                          b.is_a?(Numeric) && !(b == true || b == false)
        [a, b]
      end
      isnum = ->(x) { x.is_a?(Numeric) && !(x == true || x == false) }

      define.call("add", ->(v) {
        p = pair_num.call(v); p ? p[0] + p[1] : err.call("add", "expected a pair of numbers")
      })
      define.call("subtract", ->(v) {
        p = pair_num.call(v); p ? p[0] - p[1] : err.call("subtract", "expected a pair of numbers")
      })
      define.call("multiply", ->(v) {
        p = pair_num.call(v); p ? p[0] * p[1] : err.call("multiply", "expected a pair of numbers")
      })
      define.call("divide", lambda do |v|
        p = pair_num.call(v)
        next err.call("divide", "expected a pair of numbers") unless p
        next err.call("divide", "division by zero") if p[1] == 0
        if p[0].is_a?(Integer) && p[1].is_a?(Integer) && (p[0] % p[1] == 0)
          p[0] / p[1]
        else
          p[0].to_f / p[1]
        end
      end)
      define.call("mod", lambda do |v|
        p = pair_num.call(v)
        next err.call("mod", "expected a pair of numbers") unless p
        next err.call("mod", "modulo by zero") if p[1] == 0
        p[0] % p[1]
      end)
      define.call("negate", ->(v) {
        isnum.call(v) ? -v : err.call("negate", "expected a number")
      })
      define.call("floor", ->(v) {
        isnum.call(v) ? v.floor : err.call("floor", "expected a number")
      })

      # --- comparison ---
      define.call("equals", lambda do |v|
        next err.call("equals", "expected a pair") unless v.is_a?(Array) && v.length == 2
        interp.deep_equal?(v[0], v[1])
      end)
      define.call("lessThan", lambda do |v|
        next err.call("lessThan", "expected two numbers or two strings") unless v.is_a?(Array) && v.length == 2
        a, b = v
        if isnum.call(a) && isnum.call(b) then a < b
        elsif a.is_a?(String) && b.is_a?(String) then a < b
        else err.call("lessThan", "expected two numbers or two strings") end
      end)

      # --- boolean ---
      define.call("and", lambda do |v|
        unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x == true || x == false }
          next err.call("and", "expected a pair of booleans")
        end
        v[0] && v[1]
      end)
      define.call("or", lambda do |v|
        unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x == true || x == false }
          next err.call("or", "expected a pair of booleans")
        end
        v[0] || v[1]
      end)
      define.call("not", ->(v) {
        (v == true || v == false) ? !v : err.call("not", "expected a boolean")
      })

      # --- strings / structure bridges ---
      define.call("length", lambda do |v|
        case v
        when String then v.length
        when Array then v.length
        when Hash then v.length
        else err.call("length", "expected a string, array, or object") end
      end)
      define.call("concat", lambda do |v|
        unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x.is_a?(String) }
          next err.call("concat", "expected a pair of strings")
        end
        v[0] + v[1]
      end)
      define.call("chars", ->(v) {
        v.is_a?(String) ? v.chars : err.call("chars", "expected a string")
      })
      define.call("join", lambda do |v|
        next err.call("join", "expected [array-of-strings, separator-string]") unless v.is_a?(Array) && v.length == 2
        arr, sep = v
        unless arr.is_a?(Array) && sep.is_a?(String) && arr.all? { |x| x.is_a?(String) }
          next err.call("join", "expected [array-of-strings, separator-string]")
        end
        arr.join(sep)
      end)
      define.call("toString", lambda do |v|
        case v
        when String then v
        when Integer, Float then v.to_s
        when true then "true"
        when false then "false"
        when NULL then "null"
        else err.call("toString", "cannot stringify this value type")
        end
      end)
      define.call("parseNumber", lambda do |v|
        next err.call("parseNumber", "expected a string") unless v.is_a?(String)
        if v =~ /\A-?\d+\z/ then v.to_i
        elsif v =~ /\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/ then v.to_f
        else err.call("parseNumber", "not a numeric string")
        end
      end)

      # --- object key enumeration (Tier 0: patterns can't enumerate unknown keys) ---
      define.call("keys", ->(v) { v.is_a?(Hash) ? v.keys : err.call("keys", "expected an object") })
      define.call("values", ->(v) { v.is_a?(Hash) ? v.values : err.call("values", "expected an object") })

      # --- type predicates (return false on any non-matching value; propagate on error like every other builtin) ---
      define.call("Integer", ->(v) { v.is_a?(Integer) && !(v == true || v == false) })
      define.call("Float", ->(v) { v.is_a?(Float) })
      define.call("Number", ->(v) { isnum.call(v) })
      define.call("String", ->(v) { v.is_a?(String) })
      define.call("Boolean", ->(v) { v == true || v == false })
      define.call("Array", ->(v) { v.is_a?(Array) })
      define.call("Object", ->(v) { v.is_a?(Hash) })
      define.call("Null", ->(v) { v == NULL })
    end
  end

  # A native (Ruby-implemented) function. Apply treats it like a Func.
  class NativeFunc
    attr_reader :name, :fn
    def initialize(name, fn)
      @name = name
      @fn = fn
    end
    def inspect = "<builtin #{name}>"
  end

  # =========================================================================
  # JSON I/O  (minimal, with NULL and ErrorVal handling)
  # =========================================================================
  module Serializer
    def self.to_json(v)
      case v
      when NULL then "null"
      when true then "true"
      when false then "false"
      when Integer then v.to_s
      when Float then v.to_s
      when String then string_json(v)
      when Array then "[" + v.map { |x| to_json(x) }.join(",") + "]"
      when Hash then "{" + v.map { |k, x| "#{string_json(k.to_s)}:#{to_json(x)}" }.join(",") + "}"
      when Func, NativeFunc then '"<function>"'
      when ErrorVal
        # Errors render as `!<payload-json>`. This form is NOT valid JSON; the CLI
        # prints the payload (as JSON) to stderr and nothing to stdout on error.
        "!" + to_json(v.payload)
      else
        v.inspect
      end
    end

    def self.string_json(s)
      out = +'"'
      s.each_char do |c|
        out << case c
               when '"' then '\\"'
               when "\\" then "\\\\"
               when "\n" then "\\n"
               when "\t" then "\\t"
               when "\r" then "\\r"
               else c
               end
      end
      out << '"'
      out
    end
  end

  module JsonInput
    # Parse JSON text into Fusion values (null -> NULL).
    def self.parse(text)
      require "json"
      raw = JSON.parse(text)
      convert(raw)
    rescue JSON::ParserError
      Fusion.mkerr({"kind" => "stdin_not_json"})
    end

    def self.convert(x)
      case x
      when nil then NULL
      when Array then x.map { |e| convert(e) }
      when Hash then x.each_with_object({}) { |(k, v), h| h[k] = convert(v) }
      else x
      end
    end
  end
end
