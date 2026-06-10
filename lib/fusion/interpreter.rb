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

    def initialize(env_vars: nil)
      @stdlib_dir = File.expand_path("../../stdlib", __dir__)
      raise Unreachable, "Couldn't find standard library" unless Dir.exist?(@stdlib_dir)

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

    # The error field `location` for code at `abspath`.
    def file_location(abspath)
      if abspath.start_with?(@stdlib_dir + File::SEPARATOR)
        "stdlib #{File.basename(abspath)}"
      else
        "code #{File.basename(abspath)}"
      end
    end

    # The error field `location` for code being evaluated under `env`.
    def code_location(env)
      f = env.lookup("__file__")
      if f == :__unbound__
        # Inline (`-e`) programs have no file, so they report as "code <inline>".
        "code <inline>"
      else
        file_location(f)
      end
    end

    def evaluate_file(abspath)
      loc = file_location(abspath)
      ast = (@ast_cache[abspath] ||= begin
        src = File.read(abspath)
        Parser.parse_file(src, location: loc)
      end)

      if ast.is_a?(ErrorVal) # a parse error (already a payloaded value)
        ast
      else
        # A file's value is evaluated in a fresh env whose parent is root (builtins),
        # plus knowledge of its own directory for resolving @refs.
        env = @root_env.child
        env.define("__dir__", File.dirname(abspath))
        env.define("__file__", abspath)
        eval_expr(ast, env)
      end
    rescue Errno::ENOENT
      ErrorVal.internal(kind: "reference_error", location: loc, operation: "reading file", input: abspath, message: "file not found")
    rescue SystemCallError => err # EISDIR, EACCES, ... — file-system access failures
      ErrorVal.internal(kind: "reference_error", location: loc, operation: "reading file", input: abspath, message: err.message)
    end

    # Resolve a bare "@name": sibling file > builtin (incl. load, ENV) > stdlib > !.
    # `location` is the "code X" of the referencing file (for the unresolved case).
    def resolve_name(name, dir, location)
      sibling_file = File.expand_path(name + ".fsn", dir)
      if File.exist?(sibling_file)
        return load_file(sibling_file).force
      end

      if name == "ENV"
        return @env_vars.dup
      end

      if name == "load"
        # @load is a builtin closure capturing the calling file's directory. It
        # loads a VERBATIM filename (no ".fsn" appended) so arbitrary names work.
        d = dir
        return NativeFunc.new("load", lambda do |v|
          unless v.is_a?(String)
            next ErrorVal.internal(kind: "type_error", location: "builtin load", operation: "@load", input: v, message: "expected a string")
          end

          target = File.expand_path(v, d)

          unless File.exist?(target)
            next ErrorVal.internal(kind: "reference_error", location: "builtin load", operation: "@load", input: v, message: "file not found")
          end

          load_file(target).force
        end)
      end

      if @builtins.key?(name)
        return @builtins[name]
      end

      stdlib_file = File.join(@stdlib_dir, name + ".fsn")
      if File.exist?(stdlib_file)
        return load_file(stdlib_file).force
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
        if node.payload.nil?
          # Bare `!` means `!null`
          ErrorVal.new(NULL)
        else
          payload = eval_expr(node.payload, env)

          if payload.is_a?(ErrorVal)
            # No nested errors. Propagate inner error.
            payload
          else
            ErrorVal.new(payload)
          end
        end
      when Expression::Ident
        value = env.lookup(node.name)

        if value == :__unbound__
          ErrorVal.internal(kind: "binding_error", location: code_location(env), operation: "reading identifier #{node.name}", input: node.name, message: "unbound identifier")
        else
          value
        end
      when Expression::FileRef
        dir = env.lookup("__dir__")
        dir = Dir.pwd if dir == :__unbound__
        case node.variety
        when :self
          # Bare `@` is the current file. NOTE: inline (`-e`) programs have no
          # current file, so `@` is unresolvable there today — but it *should*
          # refer to the whole inline program (tracked as a gap).
          file = env.lookup("__file__")

          if file == :__unbound__
            ErrorVal.internal(kind: "reference_error", location: code_location(env), operation: "resolving @", input: NULL, message: "no current file for self-reference")
          else
            load_file(file).force
          end
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
      else
        raise Unreachable, "Unknown AST node #{node.class}"
      end
    end

    # Array/object literals propagate any error encountered during construction.
    # Errors are not first-class: at any point during execution there is either
    # a value or an error in motion, never both.
    def eval_array(node, env)
      out = []

      node.elems.each do |elem|
        value = eval_expr(elem.value, env)

        if value.is_a?(ErrorVal)
          # Propagate errors
          return value
        end

        case elem
        when ArrayItem
          out.append(value)
        when ArraySpread
          if value.is_a?(Array)
            out.concat(value)
          else
            return ErrorVal.internal(kind: "type_error", location: code_location(env), operation: "[...] array spread", input: value, message: "expected an array")
          end
        else
          raise Unreachable, "Unknown array element #{elem.class}"
        end
      end

      out
    end

    def eval_object(node, env)
      out = {}

      node.members.each do |member|
        value = eval_expr(member.value, env)

        if value.is_a?(ErrorVal)
          # Propagate errors
          return value
        end

        case member
        when KeyValuePair
          out[member.key] = value
        when ObjectSpread
          if value.is_a?(Hash)
            out.merge!(value)
          else
            return ErrorVal.internal(kind: "type_error", location: code_location(env), operation: "{...} object spread", input: value, message: "expected an object")
          end
        else
          raise Unreachable, "Unknown object member #{member.class}"
        end
      end

      out
    end

    def eval_pipe(node, env)
      value = eval_expr(node.left, env)
      function = eval_expr(node.right, env)
      apply(function, value, code_location(env))
    end

    def eval_member(node, env)
      obj = eval_expr(node.obj, env)

      if obj.is_a?(ErrorVal)
        # Propagate errors
        return obj
      end

      loc = code_location(env)
      unless obj.is_a?(Hash)
        return ErrorVal.internal(kind: "type_error", location: loc, operation: ".#{node.key}", input: [obj, node.key], message: "expected an object")
      end

      unless obj.key?(node.key)
        return ErrorVal.internal(kind: "access_error", location: loc, operation: ".#{node.key}", input: [obj, node.key], message: "missing key")
      end

      obj[node.key]
    end

    def eval_index(node, env)
      obj = eval_expr(node.obj, env)

      if obj.is_a?(ErrorVal)
        # Propagate errors
        return obj
      end

      idx = eval_expr(node.idx, env)

      if idx.is_a?(ErrorVal)
        # Propagate errors
        return idx
      end

      loc = code_location(env)
      if obj.is_a?(Array) && idx.is_a?(Integer)
        i = idx >= 0 ? idx : obj.length + idx
        if i >= 0 && i < obj.length
          obj[i]
        else
          ErrorVal.internal(kind: "access_error", location: loc, operation: "[#{idx}]", input: [obj, idx], message: "index out of range")
        end
      elsif obj.is_a?(Hash) && idx.is_a?(String)
        if obj.key?(idx)
          obj[idx]
        else
          ErrorVal.internal(kind: "access_error", location: loc, operation: "[#{idx.inspect}]", input: [obj, idx], message: "missing key")
        end
      else
        ErrorVal.internal(kind: "type_error", location: loc, operation: "[index]", input: [obj, idx], message: "bad index type")
      end
    end

    # ---- Application & matching ------------------------------------------
    # `location` is the "code X" where the `|` lives, used if `f` is not a
    # function. It defaults to "interpreter" for apply calls with no code context
    # (e.g. the CLI applying the whole program).
    def apply(f, v, location = "interpreter")
      if f.is_a?(ErrorVal)
        # Propagate errors
        return f
      end

      if f.is_a?(NativeFunc)
        if v.is_a?(ErrorVal)
          # Uniform propagation: built-ins never receive errors as inputs.
          return v
        end

        # Safety net: a builtin that raises a Ruby error (e.g. a domain error)
        # becomes a payloaded error rather than a raw backtrace on stderr.
        begin
          f.fn.call(v)
        rescue StandardError => err
          kind = (err.is_a?(FloatDomainError) || err.is_a?(ZeroDivisionError)) ? "math_error" : "type_error"
          ErrorVal.internal(kind: kind, location: "builtin #{f.name}", operation: f.name, input: v, message: err.message)
        end
      elsif f.is_a?(Func)
        f.clauses.each do |clause|
          # Bindings are inserted directly into a fresh child env as the pattern
          # matches; a duplicate binder (e.g. `[a, a]`) trips Env#bind, which we
          # convert to a binding_error here. A failed/abandoned clause just drops
          # its env, so partial bindings never leak.
          clause_env = f.env.child
          m = begin
            match(clause.pattern, v, clause_env)
          rescue Env::DuplicateBinding => e
            return ErrorVal.internal(kind: "binding_error", location: code_location(clause_env), operation: "binding identifier #{e.name}", input: e.name, message: "identifier already bound")
          end

          if m.is_a?(ErrorVal)
            # A `?` predicate raised an error during matching: bubble it up as the
            # function's return value (no further clauses are tried).
            return m
          elsif m
            # Successful match
            return eval_expr(clause.body, clause_env)
          else
            # Try next pattern
            next
          end
        end
        # No clause matched. If the input was an error, it keeps propagating
        # (an unmatched error must never be silently swallowed). Otherwise the
        # lenient default is `null`.
        v.is_a?(ErrorVal) ? v : NULL
      else
        ErrorVal.internal(kind: "type_error", location: location, operation: "|", input: [v, f], message: "applied a non-function")
      end
    end

    # Binds matched sub-values into `env` as it goes. Returns true (match),
    # false (no match), or an ErrorVal (predicate errored). A duplicate binder
    # raises Env::DuplicateBinding, caught in #apply.
    def match(pattern, value, env)
      case pattern
      when Pattern::PLit
        deep_equal?(pattern.value, value)
      when Pattern::PErr
        if value.is_a?(ErrorVal)
          # The pattern.inner is always a non-`!` pattern (ensured by the parser)
          match(pattern.inner, value.payload, env)
        else
          false
        end
      when Pattern::PWild
        # `_` matches anything EXCEPT an error value.
        !value.is_a?(ErrorVal)
      when Pattern::PBind
        if value.is_a?(ErrorVal)
          # binders never capture an error
          false
        else
          env.bind(pattern.name, value)
          true
        end
      when Pattern::PArr
        match_array(pattern, value, env)
      when Pattern::PObj
        match_object(pattern, value, env)
      when Pattern::PGuard
        inner_res = match(pattern.inner, value, env)
        if !inner_res
          # The inner pattern didn't match
          false
        elsif inner_res.is_a?(ErrorVal)
          # The inner pattern produced an error
          inner_res
        else
          # The predicate evaluates in the clause's lexical env — `env.parent`, not
          # `env` — so it cannot see the pattern's own binders (including the one it
          # refines). `env` is the clause env created in #apply, threaded through
          # matching unchanged, so its parent is always that lexical env.
          lexical_env = env.parent

          pred = eval_expr(pattern.pred_expr, lexical_env)

          if pred.is_a?(ErrorVal)
            # The predicate expression itself errored, e.g. an unresolved @-reference.
            return pred
          end
          # The predicate sees whatever value reached this PGuard, which is
          # already the right value because `!pat ? pred` parses as
          # PErr(PGuard(pat, pred)) — by the time PGuard runs, the value is
          # already the payload.
          predicate_result = apply(pred, value, code_location(lexical_env))
          if predicate_result.is_a?(ErrorVal)
            # Predicate raised during application, propagate error
            return predicate_result
          else
            # Predicate clause matches, if predicate evaluates to "true"
            predicate_result == true
          end
        end
      else
        raise Unreachable, "Unknown pattern #{pattern.class}"
      end
    end

    def match_array(pattern, value, env)
      return false unless value.is_a?(Array)

      elems = pattern.elems
      rest_index = elems.index { |e| e.is_a?(PatternRest) }

      if rest_index.nil?
        return false unless value.length == elems.length

        elems.each_with_index do |elem, i|
          r = match(elem.pattern, value[i], env)
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        true
      else
        before = elems[0...rest_index]
        after  = elems[(rest_index + 1)..]
        return false if value.length < before.length + after.length
        before.each_with_index do |elem, i|
          r = match(elem.pattern, value[i], env)
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        after.each_with_index do |elem, k|
          vi = value.length - after.length + k
          r = match(elem.pattern, value[vi], env)
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        rest_name = elems[rest_index].name
        if rest_name
          mid = value[before.length...(value.length - after.length)]
          env.bind(rest_name, mid)
        end
        true
      end
    end

    def match_object(pattern, value, env)
      return false unless value.is_a?(Hash)

      matched_keys = []
      rest_name = :__none__
      pattern.members.each do |member|
        case member
        when PatternRest
          rest_name = member.name # may be nil (ignore) or a string
        when PatternPair
          return false unless value.key?(member.key)
          r = match(member.pattern, value[member.key], env)
          return r if r.is_a?(ErrorVal)
          return false unless r
          matched_keys << member.key
        else
          raise Unreachable, "Unknown object pattern member #{member.class}"
        end
      end
      case rest_name
      when :__none__
        # No `...rest`: the pattern is closed — a superfluous key means no match.
        return false unless value.size == matched_keys.size
      when nil
        # Bare `...`: extra keys are allowed but bound to nothing.
      else
        env.bind(rest_name, value.reject { |k, _| matched_keys.include?(k) })
      end
      true
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
