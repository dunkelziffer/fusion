module Fusion
  # =========================================================================
  # EVALUATOR
  # =========================================================================
  class Interpreter
    attr_reader :root_env

    def initialize(stdlib_dir: nil)
      @stdlib_dir = stdlib_dir
      @file_cache = {} # abspath -> FileThunk
      @ast_cache = {}  # abspath -> AST
      @root_env = Env.new
      Builtins.install(@root_env, self)
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
      eval_expr(ast, env)
    rescue Errno::ENOENT
      warn "[fusion] file not found: #{abspath}" if ENV["FUSION_DEBUG"]
      ERROR
    rescue ParseError => err
      warn "[fusion] parse error in #{abspath}: #{err.message}" if ENV["FUSION_DEBUG"]
      ERROR
    end

    def resolve_ref(path, dir)
      # path like "a", "../a", "dir/a", "std/map"
      if path.start_with?("std/") && @stdlib_dir
        File.join(@stdlib_dir, path.sub(%r{\Astd/}, "")) + ".fsn"
      else
        File.expand_path(path + ".fsn", dir)
      end
    end

    # ---- Expression evaluation -------------------------------------------
    def eval_expr(node, env)
      case node
      when Expression::Literal then node.value
      when Expression::Identifier
        v = env.lookup(node.name)
        v == :__unbound__ ? ERROR : v
      when Expression::FileReference
        dir = env.lookup("__dir__")
        dir = Dir.pwd if dir == :__unbound__
        abspath = resolve_ref(node.path, dir)
        load_file(abspath).force
      when Expression::ArrayLiteral then eval_array(node, env)
      when Expression::ObjectLiteral then eval_object(node, env)
      when Expression::FunctionLiteral then Func.new(node.clauses, env)
      when Expression::Pipe then eval_pipe(node, env)
      when Expression::Member then eval_member(node, env)
      when Expression::Index then eval_index(node, env)
      else raise FusionError, "Cannot evaluate node #{node.class}"
      end
    end

    def eval_array(node, env)
      out = []
      node.elems.each do |kind, expr|
        v = eval_expr(expr, env)
        if kind == :spread
          return ERROR unless v.is_a?(Array)
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
          return ERROR unless v.is_a?(Hash)
          out.merge!(v)
        else
          _, key, expr = m
          out[key] = eval_expr(expr, env)
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
      return ERROR unless obj.is_a?(Hash)
      obj.key?(node.key) ? obj[node.key] : ERROR
    end

    def eval_index(node, env)
      obj = eval_expr(node.obj, env)
      idx = eval_expr(node.idx, env)
      if obj.is_a?(Array) && idx.is_a?(Integer)
        i = idx >= 0 ? idx : obj.length + idx
        (i >= 0 && i < obj.length) ? obj[i] : ERROR
      elsif obj.is_a?(Hash) && idx.is_a?(String)
        obj.key?(idx) ? obj[idx] : ERROR
      else
        ERROR
      end
    end

    # ---- Application & matching ------------------------------------------
    def apply(f, v)
      if f.is_a?(NativeFunc)
        # Built-in operations propagate `!` (they have no clauses to catch it).
        return ERROR if error?(v)
        return f.fn.call(v)
      end
      unless f.is_a?(Func)
        # Applying a non-function is an error.
        return ERROR
      end
      # Error propagation: if the input is `!`, it propagates automatically UNLESS
      # some clause explicitly matches `!` (an `! => ...` handler). This makes `!`
      # flow through every function by default and be caught only on purpose.
      if error?(v) && !f.clauses.any? { |p, _| p.is_a?(Pattern::Literal) && p.value.equal?(ERROR) }
        return ERROR
      end
      f.clauses.each do |pattern, body|
        bindings = {}
        if match(pattern, v, bindings, f.env)
          return eval_expr(body, f.env.child(bindings))
        end
      end
      # No clause matched: lenient default -> null.
      # (Strict functions include a final `_ => !` clause, handled above.)
      NULL
    end

    # Returns true and fills `bindings` if `pattern` matches `value`.
    # `env` is the function's closure env, used to evaluate `?` predicates.
    def match(pattern, value, bindings, env)
      case pattern
      when Pattern::Literal
        deep_equal?(pattern.value, value)
      when Pattern::Wildcard
        # `_` matches anything EXCEPT the error value.
        !error?(value)
      when Pattern::Binding
        return false if error?(value) # binders never capture `!`
        bindings[pattern.name] = value
        true
      when Pattern::Array
        match_array(pattern, value, bindings, env)
      when Pattern::Object
        match_object(pattern, value, bindings, env)
      when Pattern::Guard
        return false unless match(pattern.inner, value, bindings, env)
        pred = eval_expr(pattern.pred_expr, env)
        # Predicate sees ONLY the value matched by this subtree.
        apply(pred, value) == true
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
          return false unless match(p, value[i], bindings, env)
        end
        true
      else
        before = elems[0...rest_index]
        after  = elems[(rest_index + 1)..]
        return false if value.length < before.length + after.length
        before.each_with_index do |(_, p), i|
          return false unless match(p, value[i], bindings, env)
        end
        after.each_with_index do |(_, p), k|
          vi = value.length - after.length + k
          return false unless match(p, value[vi], bindings, env)
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
          return false unless match(p, value[key], bindings, env)
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
    def error?(v) = v.equal?(ERROR)

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
