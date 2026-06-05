# frozen_string_literal: true

# === Transformation ===
#
# Tree-walking interpreter
#
# Input: AST::Expression
# Output: AST::Expression

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

require_relative "ast"
require_relative "interpreter/null"
require_relative "interpreter/error_val"
require_relative "interpreter/func"
require_relative "interpreter/native_func"
require_relative "interpreter/builtins"
require_relative "interpreter/env"
require_relative "interpreter/file_thunk"

module Fusion
  class Interpreter
    include AST

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

    # The `location` string for code at `abspath`: "stdlib X" for stdlib files,
    # "code X" for everything else.
    def file_location(abspath)
      if @stdlib_dir && abspath.start_with?(@stdlib_dir + File::SEPARATOR)
        "stdlib #{File.basename(abspath)}"
      else
        "code #{File.basename(abspath)}"
      end
    end

    # The `location` for code being evaluated under `env`. Inline (`-e`) programs
    # have no file, so they report as "code <inline>".
    def code_location(env)
      f = env.lookup("__file__")
      f == :__unbound__ ? "code <inline>" : file_location(f)
    end

    def evaluate_file(abspath)
      loc = file_location(abspath)
      ast = (@ast_cache[abspath] ||= begin
        src = File.read(abspath)
        Parser.parse_file(src, location: loc)
      end)
      return ast if ast.is_a?(ErrorVal) # a parse error (already a payloaded value)
      # A file's value is evaluated in a fresh env whose parent is root (builtins),
      # plus knowledge of its own directory for resolving @refs.
      env = @root_env.child
      env.define("__dir__", File.dirname(abspath))
      env.define("__file__", abspath)
      eval_expr(ast, env)
    rescue Errno::ENOENT
      warn "[fusion] file not found: #{abspath}" if ENV["FUSION_DEBUG"]
      ErrorVal.internal(kind: "reference_error", location: loc, operation: "reading file", input: abspath, message: "file not found")
    rescue SystemCallError => err # EISDIR, EACCES, ... — file-system access failures
      warn "[fusion] cannot read #{abspath}: #{err.message}" if ENV["FUSION_DEBUG"]
      ErrorVal.internal(kind: "reference_error", location: loc, operation: "reading file", input: abspath, message: err.message)
    end

    # Resolve a bare "@name": sibling file > builtin (incl. load, ENV) > stdlib > !.
    # `location` is the "code X" of the referencing file (for the unresolved case).
    def resolve_name(name, dir, location)
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
          next ErrorVal.internal(kind: "type_error", location: "builtin load", operation: "@load", input: v, message: "expected a string") unless v.is_a?(String)
          target = File.expand_path(v, d)
          next ErrorVal.internal(kind: "reference_error", location: "builtin load", operation: "@load", input: v, message: "file not found") unless File.exist?(target)
          load_file(target).force
        end)
      end
      return @builtins[name] if @builtins.key?(name)
      if @stdlib_dir
        std = File.join(@stdlib_dir, name + ".fsn")
        return load_file(std).force if File.exist?(std)
      end
      ErrorVal.internal(kind: "reference_error", location: location, operation: "resolving @#{name}", input: name, message: "unresolved reference")
    end

    # Resolve a pure path "@dir/a" or "@../a": file only, never builtin/stdlib.
    def resolve_path(relpath, dir)
      load_file(File.expand_path(relpath + ".fsn", dir)).force
    end

    # ---- Expression evaluation -------------------------------------------
    def eval_expr(node, env)
      case node
      when Expression::Lit then node.value
      when Expression::ErrLit
        # Bare `!` means `!null`; `!expr` wraps expr's value as an error.
        # If the payload expression itself errors, propagate THAT error rather
        # than wrapping it -- prevents accidental error-burying.
        if node.payload.nil?
          ErrorVal.new(NULL)
        else
          p = eval_expr(node.payload, env)
          p.is_a?(ErrorVal) ? p : ErrorVal.new(p)
        end
      when Expression::Ident
        v = env.lookup(node.name)
        v == :__unbound__ ? ErrorVal.internal(kind: "binding_error", location: code_location(env), operation: "reading identifier #{node.name}", input: node.name, message: "unbound identifier") : v
      when Expression::FileRef
        dir = env.lookup("__dir__")
        dir = Dir.pwd if dir == :__unbound__
        case node.variety
        when :self
          # Bare `@` is the current file. NOTE: inline (`-e`) programs have no
          # current file, so `@` is unresolvable there today — but it *should*
          # refer to the whole inline program (tracked as a gap).
          f = env.lookup("__file__")
          f == :__unbound__ ? ErrorVal.internal(kind: "reference_error", location: code_location(env), operation: "resolving @", input: NULL, message: "no current file for self-reference") : load_file(f).force
        when :name
          resolve_name(node.path, dir, code_location(env))
        else # :path
          resolve_path(node.path, dir)
        end
      when Expression::ArrLit then eval_array(node, env)
      when Expression::ObjLit then eval_object(node, env)
      when Expression::FuncLit then Func.new(node.clauses, env)
      when Expression::Pipe then eval_pipe(node, env)
      when Expression::Member then eval_member(node, env)
      when Expression::Index then eval_index(node, env)
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
        return v if v.is_a?(ErrorVal)
        if kind == :spread
          return ErrorVal.internal(kind: "type_error", location: code_location(env), operation: "[...] array spread", input: v, message: "expected an array") unless v.is_a?(Array)
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
          return v if v.is_a?(ErrorVal)
          return ErrorVal.internal(kind: "type_error", location: code_location(env), operation: "{...} object spread", input: v, message: "expected an object") unless v.is_a?(Hash)
          out.merge!(v)
        else
          _, key, expr = m
          v = eval_expr(expr, env)
          return v if v.is_a?(ErrorVal)
          out[key] = v
        end
      end
      out
    end

    def eval_pipe(node, env)
      v = eval_expr(node.left, env)
      f = eval_expr(node.right, env)
      apply(f, v, code_location(env))
    end

    def eval_member(node, env)
      obj = eval_expr(node.obj, env)
      return obj if obj.is_a?(ErrorVal)
      loc = code_location(env)
      return ErrorVal.internal(kind: "type_error", location: loc, operation: ".#{node.key}", input: [obj, node.key], message: "expected an object") unless obj.is_a?(Hash)
      return ErrorVal.internal(kind: "access_error", location: loc, operation: ".#{node.key}", input: [obj, node.key], message: "missing key") unless obj.key?(node.key)
      obj[node.key]
    end

    def eval_index(node, env)
      obj = eval_expr(node.obj, env)
      return obj if obj.is_a?(ErrorVal)
      idx = eval_expr(node.idx, env)
      return idx if idx.is_a?(ErrorVal)
      loc = code_location(env)
      if obj.is_a?(Array) && idx.is_a?(Integer)
        i = idx >= 0 ? idx : obj.length + idx
        return obj[i] if i >= 0 && i < obj.length
        return ErrorVal.internal(kind: "access_error", location: loc, operation: "[#{idx}]", input: [obj, idx], message: "index out of range")
      elsif obj.is_a?(Hash) && idx.is_a?(String)
        return obj[idx] if obj.key?(idx)
        return ErrorVal.internal(kind: "access_error", location: loc, operation: "[#{idx.inspect}]", input: [obj, idx], message: "missing key")
      end
      ErrorVal.internal(kind: "type_error", location: loc, operation: "[index]", input: [obj, idx], message: "bad index type")
    end

    # ---- Application & matching ------------------------------------------
    # `location` is the "code X" where the `|` lives, used if `f` is not a
    # function. It defaults to "interpreter" for apply calls with no code context
    # (e.g. the CLI applying the whole program).
    def apply(f, v, location = "interpreter")
      # An errored function value propagates as-is (more useful than a generic
      # "applied a non-function" wrapper).
      return f if f.is_a?(ErrorVal)
      if f.is_a?(NativeFunc)
        # Uniform propagation: built-ins never receive errors as inputs.
        return v if v.is_a?(ErrorVal)
        # Safety net: a builtin that raises a Ruby error (e.g. a domain error)
        # becomes a payloaded error rather than a raw backtrace on stderr.
        begin
          return f.fn.call(v)
        rescue StandardError => err
          kind = (err.is_a?(FloatDomainError) || err.is_a?(ZeroDivisionError)) ? "math_error" : "type_error"
          return ErrorVal.internal(kind: kind, location: "builtin #{f.name}", operation: f.name, input: v, message: err.message)
        end
      end
      unless f.is_a?(Func)
        return ErrorVal.internal(kind: "type_error", location: location, operation: "|", input: [v, f], message: "applied a non-function")
      end
      f.clauses.each do |pattern, body|
        bindings = {}
        m = match(pattern, v, bindings, f.env)
        # A `?` predicate raised an error during matching: bubble it up as the
        # function's return value (no further clauses are tried).
        return m if m.is_a?(ErrorVal)
        if m
          return eval_expr(body, f.env.child(bindings))
        end
      end
      # No clause matched. If the input was an error, it keeps propagating
      # (an unmatched error must never be silently swallowed). Otherwise the
      # lenient default is `null`.
      v.is_a?(ErrorVal) ? v : NULL
    end

    # Returns true (match), false (no match), or an ErrorVal (predicate errored).
    def match(pattern, value, bindings, env)
      case pattern
      when Pattern::PLit
        deep_equal?(pattern.value, value)
      when Pattern::PErr
        # If the value is an error, match the inner pattern against its
        # payload. The inner is always a non-`!` pattern (the parser ensures
        # that), so for a bare `!` we synthesized PWild as the inner.
        return false unless value.is_a?(ErrorVal)
        match(pattern.inner, value.payload, bindings, env)
      when Pattern::PWild
        # `_` matches anything EXCEPT an error value.
        !value.is_a?(ErrorVal)
      when Pattern::PBind
        return false if value.is_a?(ErrorVal)    # binders never capture an error
        e = bind(bindings, pattern.name, value, env)
        e.nil? ? true : e
      when Pattern::PArr
        match_array(pattern, value, bindings, env)
      when Pattern::PObj
        match_object(pattern, value, bindings, env)
      when Pattern::PGuard
        inner_res = match(pattern.inner, value, bindings, env)
        return inner_res if inner_res.is_a?(ErrorVal)
        return false unless inner_res
        pred = eval_expr(pattern.pred_expr, env)
        return pred if pred.is_a?(ErrorVal)       # predicate expression itself errored
        # The predicate sees whatever value reached this PGuard, which is
        # already the right value because `!pat ? pred` parses as
        # PErr(PGuard(pat, pred)) — by the time PGuard runs, the value is
        # already the payload.
        r = apply(pred, value, code_location(env))
        return r if r.is_a?(ErrorVal)             # predicate raised during application
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
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        true
      else
        before = elems[0...rest_index]
        after  = elems[(rest_index + 1)..]
        return false if value.length < before.length + after.length
        before.each_with_index do |(_, p), i|
          r = match(p, value[i], bindings, env)
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        after.each_with_index do |(_, p), k|
          vi = value.length - after.length + k
          r = match(p, value[vi], bindings, env)
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        rest_name = elems[rest_index][1]
        if rest_name
          mid = value[before.length...(value.length - after.length)]
          e = bind(bindings, rest_name, mid, env)
          return e if e
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
          return r if r.is_a?(ErrorVal)
          return false unless r
          matched_keys << key
        end
      end
      if rest_name != :__none__ && rest_name
        remaining = value.reject { |k, _| matched_keys.include?(k) }
        e = bind(bindings, rest_name, remaining, env)
        return e if e
      end
      true
    end

    # Record a pattern binding, or return a binding_error if `name` is already
    # bound in this clause. Duplicate binders (e.g. `[a, a]`) are rejected, not
    # treated as a non-linear "must be equal" match. Returns nil on success.
    def bind(bindings, name, value, env)
      if bindings.key?(name)
        return ErrorVal.internal(kind: "binding_error", location: code_location(env),
                                 operation: "binding identifier #{name}", input: name,
                                 message: "identifier already bound")
      end
      bindings[name] = value
      nil
    end

    # ---- Equality & helpers ----------------------------------------------
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
end
