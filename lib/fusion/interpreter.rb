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

require "pathname"

require_relative "ast"
require_relative "null"
require_relative "interpreter/error_val"
require_relative "interpreter/func"
require_relative "interpreter/native_func"
require_relative "interpreter/builtins"
require_relative "interpreter/env"
require_relative "interpreter/thunk"

module Fusion
  class Interpreter
    include AST

    # The binding-free root the run is built on — computed on demand. Loaded
    # files are isolated against it (see evaluate_file).
    def root_env
      @env.root
    end

    # `env` is the run's environment, passed in externally and stored as `@env`.
    # Its `:jail` context confines @-resolution, and its topmost ancestor
    # (`@env.root`) is the binding-free root that loaded files are isolated against.
    # The stdlib always stays reachable.
    def initialize(env, env_vars: nil)
      @stdlib_dir = File.expand_path("../../stdlib", __dir__)
      raise Unreachable, "Couldn't find standard library" unless Dir.exist?(@stdlib_dir)

      @env = env
      @env_vars = env_vars || ENV.to_h
      @file_cache = {} # abspath -> Thunk
      @ast_cache = {}  # abspath -> AST
      @builtins = {}   # name -> NativeFunc  (consulted by @name, not via env)
      Builtins.install(@builtins, self)
    end

    # Apply the program to one input behind a safety net: a Ruby-level failure
    # (notably a stack overflow) becomes a payloaded error rather than a raw
    # backtrace, so the stdout/stderr contract always holds. In the stream the
    # error is one record's output and the next line continues.
    def self.safe_apply(function, input, environment)
      safe do
        new(environment).apply(function, input)
      end
    end

    # Evaluate an expression behind the same per-run safety net as
    # exe/fusion, so a Ruby-level failure becomes a printed payload and the
    # session survives it. A statement carries its expression; a bare
    # expression entry is the expression itself.
    def self.safe_evaluate(expression, environment)
      safe do
        new(environment).evaluate_unit(expression)
      end
    end

    def self.safe
      yield
    rescue Unreachable
      # An interpreter bug. Allowed to surface.
      raise
    rescue StandardError => err
      Interpreter::ErrorVal.from_runtime(
        kind: "internal_error", origin: "interpreter", operation: "running the program",
        input: NULL, message: err.message
      )
    rescue SystemExit
      # Let exit/abort through.
      raise
    rescue SystemStackError
      Interpreter::ErrorVal.from_runtime(
        kind: "limit_error", origin: "interpreter", operation: "running the program",
        input: NULL, message: "stack level too deep"
      )
    rescue Exception => err # rubocop:disable Lint/RescueException
      # Final net: any other escaped Ruby error becomes a payloaded error too.
      Interpreter::ErrorVal.from_runtime(
        kind: "internal_error", origin: "interpreter", operation: "running the program",
        input: NULL, message: err.message
      )
    end

    # ---- File loading -----------------------------------------------------
    # The thunk is forced through the `@`-reference that reaches it (see Thunk#force):
    # its `operation`/`input`/`site` describe that reference and are used only for an
    # error about reaching this file (a read failure, a load cycle) — never for a
    # syntax error *inside* the file, which is attributed to the file itself.
    def load_file(abspath)
      @file_cache[abspath] ||= Thunk.new do |operation, input, site|
        evaluate_file(abspath, operation, input, site)
      end
    end

    # A file path for error payloads: relative to the working directory, so a
    # payload carries no machine-specific absolute prefix (and stays stable when
    # a whole project is moved together).
    def display_path(abspath)
      Pathname.new(abspath).relative_path_from(Dir.pwd).to_s
    rescue ArgumentError
      abspath # no relative path exists (e.g. different roots) — keep the absolute
    end

    # The error site (`{origin:, file?:}`) for code at `abspath`. stdlib is part
    # of the core language, so its internal filenames are never exposed; only
    # user `code` carries a `file`.
    def file_site(abspath)
      if abspath.start_with?(@stdlib_dir + File::SEPARATOR)
        { origin: "stdlib" }
      else
        { origin: "code", file: display_path(abspath) }
      end
    end

    # The error fields `{origin:, file:}` for code being evaluated under `env`.
    def code_site(env)
      f = env.context(:file)
      if f == :__unbound__
        # Inline (`-e`) programs and REPL entries report a "<inline>" file.
        { origin: "code", file: "<inline>" }
      else
        file_site(f)
      end
    end

    # The `file` an error here should carry: the innermost *user-code* file on the
    # dynamic call chain. When stdlib code runs, it borrows the user call site that
    # reached it (injected as `:call_site` in #apply); user/inline code is its own
    # file (derived from `code_site`); above any user code, the runtime: "<fusion>".
    def call_site(env)
      injected = env.context(:call_site)
      return injected unless injected == :__unbound__

      site = code_site(env)
      site[:origin] == "code" ? site[:file] : "<fusion>"
    end

    # `operation`/`input`/`site` describe the reference that reached this file (see
    # load_file); a *read* failure reports them unchanged — the failing @-reference
    # as a single operation. A syntax error in the file's own source is attributed
    # to the file itself.
    def evaluate_file(abspath, operation, input, site)
      ast = (@ast_cache[abspath] ||= begin
        src = File.read(abspath)
        Parser.parse_file(src, site: file_site(abspath))
      end)

      if ast.is_a?(ErrorVal) # a parse error (already a payloaded value)
        ast
      else
        env = root_env.child
        env.set_context(:dir, File.dirname(abspath)) # for resolving @-refs
        env.set_context(:file, abspath) # for error sites
        env.set_context(:self, load_file(abspath)) # for `@` self-recursion
        eval_expr(ast, env)
      end
    rescue Errno::ENOENT
      ErrorVal.from_runtime(kind: "reference_error", **site, operation: operation, input: input, message: "file not found")
    rescue SystemCallError => err # EISDIR, EACCES, ... — file-system access failures
      # Reduce the strerror to its lowercase core ("is a directory"), dropping
      # Ruby's "@ io_fread - <path>" tail (the path is the reference's own concern).
      ErrorVal.from_runtime(kind: "reference_error", **site, operation: operation, input: input, message: err.message.split(" @ ").first.downcase)
    end

    # Evaluate a top-level unit that has no file of its own:
    # - inline source (`-e`)
    # - REPL entries
    def evaluate_unit(ast)
      # Evaluate in a child of `@env`, so we don't mutate it. The child inherits
      # `@env`'s bindings (only non-empty in the REPL), `:dir`, and jail.
      unit_env = @env.child

      thunk = Thunk.new { |_operation, _input, _site| eval_expr(ast, unit_env) }
      unit_env.set_context(:self, thunk) # for `@` self-recursion
      # A cycle here is closed by a bare `@` re-entry, which forces with its own
      # `@`/site; this outer force only seeds the unit and never reports the cycle.
      thunk.force(operation: "@", input: NULL, site: code_site(unit_env))
    end

    # Resolve a bare "@name": sibling file > builtin (incl. load, ENV) > stdlib > !.
    # `site` is the `{origin:, file:}` of the referencing code; `reference` is its
    # own source text (`"@name"`) — the single `operation` every failure reports.
    def resolve_name(name, dir, site, reference)
      sibling_file = File.expand_path(name + ".fsn", dir)
      if File.exist?(sibling_file)
        return jail_error(site, reference, NULL) unless within_jail?(sibling_file)

        return load_file(sibling_file).force(operation: reference, input: NULL, site: site)
      end

      resolve_builtin_or_stdlib(name, dir, site, reference)
    end

    # Resolve "@@": the builtin/stdlib that the referencing file shadows. It is its
    # own name resolved with the sibling step skipped (the sibling is itself), so
    # the file can extend what it overrides. There is no file to take super of in
    # an inline (`-e`) or REPL entry.
    def resolve_super(env, dir, site)
      file = env.context(:file)
      if file == :__unbound__
        return ErrorVal.from_runtime(kind: "reference_error", **site, operation: "@@", input: NULL, message: "no enclosing file")
      end

      resolve_builtin_or_stdlib(File.basename(file, ".fsn"), dir, site, "@@")
    end

    # The non-sibling tail of @name resolution: builtin (incl. load, ENV) > stdlib > !.
    def resolve_builtin_or_stdlib(name, dir, site, reference)
      if name == "ENV"
        return @env_vars.dup
      end

      if name == "load"
        # @load is a builtin closure capturing the calling file's directory. It
        # loads a VERBATIM filename (no ".fsn" appended) so arbitrary names work.
        d = dir
        return NativeFunc.new("load", lambda do |v|
          # @load errors carry origin "builtin" and no `file`; #apply stamps the
          # call site (the user file that wrote `| @load`) onto them as `file`.
          site = { origin: "builtin", file: nil }

          unless v.is_a?(String)
            next ErrorVal.from_runtime(kind: "argument_error", **site, operation: "@load", input: v, expected: ["_ ? @String"])
          end

          target = File.expand_path(v, d)

          # Check the jail before touching the filesystem, so an out-of-jail
          # path can't be probed for existence.
          next jail_error(site, "@load", v) unless within_jail?(target)

          unless File.exist?(target)
            next ErrorVal.from_runtime(kind: "reference_error", **site, operation: "@load", input: v, message: "file not found")
          end

          load_file(target).force(operation: "@load", input: v, site: site)
        end)
      end

      if @builtins.key?(name)
        return @builtins[name]
      end

      stdlib_file = File.join(@stdlib_dir, name + ".fsn")
      if File.exist?(stdlib_file)
        # The reference reports the user's source text, not the internal stdlib path.
        return load_file(stdlib_file).force(operation: reference, input: NULL, site: site)
      end

      ErrorVal.from_runtime(kind: "reference_error", **site, operation: reference, input: NULL, message: "unresolved reference")
    end

    # Resolve a pure path "@dir/a" or "@../a": file only, never builtin/stdlib.
    # `reference` is the source text (`"@../a"`), the single `operation` reported.
    def resolve_path(relpath, dir, site, reference)
      target = File.expand_path(relpath + ".fsn", dir)
      return jail_error(site, reference, NULL) unless within_jail?(target)

      load_file(target).force(operation: reference, input: NULL, site: site)
    end

    # The run's jail (the `:jail` context, an absolute path or nil) confines
    # file-backed @-resolution to its subtree. The stdlib is always reachable (it
    # lives outside any project), and a nil/unset jail means unconfined. Containment
    # is lexical (expand_path normalises `..`) and follows existing symlinks: it
    # confines references, it is not a security sandbox and needs none — Fusion
    # cannot write files, so no symlink can be planted to escape.
    def within_jail?(abspath)
      jail = @env.context(:jail)
      return true if jail.nil? || jail == :__unbound__
      return true if inside?(abspath, @stdlib_dir)

      inside?(abspath, jail)
    end

    def inside?(abspath, root)
      root = root.chomp(File::SEPARATOR)
      abspath == root || abspath.start_with?(root + File::SEPARATOR)
    end

    def jail_error(site, operation, input)
      ErrorVal.from_runtime(kind: "reference_error", **site, operation: operation, input: input, message: "outside the jail")
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
          ErrorVal.from_runtime(kind: "binding_error", **code_site(env), operation: "reading identifier #{node.name}", input: node.name, message: "unbound identifier")
        else
          value
        end
      when Expression::FileRef
        dir = env.context(:dir)
        dir = Dir.pwd if dir == :__unbound__
        case node.variety
        when :self
          # Bare `@` is the value of the current top-level unit: a file, or an inline (`-e`)/REPL entry.
          self_thunk = env.context(:self)

          if self_thunk == :__unbound__
            raise Unreachable, "bare @ evaluated outside a top-level unit"
          end

          self_thunk.force(operation: "@", input: NULL, site: code_site(env))
        when :super
          resolve_super(env, dir, code_site(env))
        when :name
          resolve_name(node.path, dir, code_site(env), "@#{node.path}")
        else # :path
          resolve_path(node.path, dir, code_site(env), "@#{node.path}")
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

      node.items.each do |item|
        value = eval_expr(item.value, env)

        if value.is_a?(ErrorVal)
          # Propagate errors
          return value
        end

        case item
        when ArrayItem
          out.append(value)
        when ArraySpread
          if value.is_a?(Array)
            out.concat(value)
          else
            return ErrorVal.from_runtime(kind: "argument_error", **code_site(env), operation: "[...] array spread", input: value, expected: ["_ ? @Array"])
          end
        else
          raise Unreachable, "Unknown array item #{item.class}"
        end
      end

      out
    end

    def eval_object(node, env)
      out = {}

      node.pairs.each do |pair|
        value = eval_expr(pair.value, env)

        if value.is_a?(ErrorVal)
          # Propagate errors
          return value
        end

        case pair
        when KeyValuePair
          out[pair.key] = value
        when ObjectSpread
          if value.is_a?(Hash)
            out.merge!(value)
          else
            return ErrorVal.from_runtime(kind: "argument_error", **code_site(env), operation: "{...} object spread", input: value, expected: ["_ ? @Object"])
          end
        else
          raise Unreachable, "Unknown object pair #{pair.class}"
        end
      end

      out
    end

    def eval_pipe(node, env)
      value = eval_expr(node.left, env)
      function = eval_expr(node.right, env)
      apply(function, value, call_site(env))
    end

    def eval_member(node, env)
      obj = eval_expr(node.obj, env)

      if obj.is_a?(ErrorVal)
        # Propagate errors
        return obj
      end

      site = code_site(env)
      unless obj.is_a?(Hash)
        return ErrorVal.from_runtime(kind: "argument_error", **site, operation: ".#{node.key}", input: obj, expected: ["_ ? @Object"])
      end

      unless obj.key?(node.key)
        return ErrorVal.from_runtime(kind: "access_error", **site, operation: ".#{node.key}", input: obj, message: "missing key")
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

      site = code_site(env)
      if obj.is_a?(Array) && idx.is_a?(Integer)
        i = idx >= 0 ? idx : obj.length + idx
        if i >= 0 && i < obj.length
          obj[i]
        else
          ErrorVal.from_runtime(kind: "access_error", **site, operation: "[]", input: [obj, idx], message: "index out of range")
        end
      elsif obj.is_a?(Hash) && idx.is_a?(String)
        if obj.key?(idx)
          obj[idx]
        else
          ErrorVal.from_runtime(kind: "access_error", **site, operation: "[]", input: [obj, idx], message: "missing key")
        end
      else
        ErrorVal.from_runtime(kind: "argument_error", **site, operation: "[]", input: [obj, idx], expected: ["[_ ? @Array, _ ? @Integer]", "[_ ? @Object, _ ? @String]"])
      end
    end

    # ---- Application & matching ------------------------------------------
    # `call_site` is the innermost user-code file the application runs for (see
    # #call_site): a built-in/stdlib error reports it as its `file`, and a stdlib
    # function passes it on to the operations it calls. It defaults to the runtime
    # ("<fusion>") for an apply with no user-code caller (e.g. the CLI applying the
    # whole program directly to a value).
    def apply(f, v, call_site = "<fusion>")
      result = dispatch_apply(f, v, call_site)
      # The interpreter owns the call-site `file` of a standardized builtin/stdlib
      # error (the call site is its knowledge, not the stdlib's): stamp it here, at
      # the apply that produced the error. An error keeps the file from its
      # innermost apply, so outer applies leave it untouched (see #with_call_site).
      result.is_a?(ErrorVal) ? result.with_call_site(call_site) : result
    end

    def dispatch_apply(f, v, call_site)
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
          # TODO: move math errors into the builtins. This should become a safety net for unpredicted errors.
          kind = (err.is_a?(FloatDomainError) || err.is_a?(ZeroDivisionError)) ? "math_error" : "internal_error"
          ErrorVal.from_runtime(kind: kind, origin: "builtin", operation: "@#{f.name}", input: v, message: err.message)
        end
      elsif f.is_a?(Func)
        # Stdlib code has no user file of its own: errors inside it (and in the
        # built-ins it calls) report the user `call_site` that reached it. User and
        # inline functions are their own call site (derived lexically from their env).
        body_call_site = (code_site(f.env)[:origin] == "stdlib") ? call_site : nil

        f.clauses.each do |clause|
          # Bindings are inserted directly into a fresh child env as the pattern
          # matches; a duplicate binder (e.g. `[a, a]`) trips Env#bind, which we
          # convert to a binding_error here. A failed/abandoned clause just drops
          # its env, so partial bindings never leak.
          clause_env = f.env.child
          clause_env.set_context(:call_site, body_call_site) if body_call_site
          m = begin
            match(clause.pattern, v, clause_env)
          rescue Env::DuplicateBinding => e
            return ErrorVal.from_runtime(kind: "binding_error", **code_site(clause_env), operation: "binding identifier #{e.name}", input: e.name, message: "identifier already bound")
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
        ErrorVal.from_runtime(kind: "argument_error", origin: "code", file: call_site, operation: "|", input: [v, f], expected: ["[_, _ ? @Function]"])
      end
    end

    # Run a guard predicate against the matched value. The predicate is a `|`
    # pipeline of functions; the value enters at the leftmost stage and the result
    # flows through each stage, so `a ? b | c` evaluates `a | b | c`. A non-pipe
    # predicate is just the single-stage case. #apply propagates any ErrorVal in
    # either the function or the threaded value position.
    def apply_predicate(pred_expr, value, env)
      if pred_expr.is_a?(Expression::Pipe)
        upstream = apply_predicate(pred_expr.left, value, env)
        apply(eval_expr(pred_expr.right, env), upstream, call_site(env))
      else
        apply(eval_expr(pred_expr, env), value, call_site(env))
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

          # The predicate is a pipeline fed the matched value: `a ? b | c` tests
          # `a | b | c`. The value reaching this PGuard is already correct, since
          # `!pat ? pred` parses as PErr(PGuard(pat, pred)) — by now it is the
          # payload. #apply_predicate threads it through each `|` stage.
          predicate_result = apply_predicate(pattern.pred_expr, value, lexical_env)
          if predicate_result.is_a?(ErrorVal)
            # An unresolved @-reference, or an error raised while applying the
            # predicate, becomes the clause's result.
            return predicate_result
          else
            # Ruby-style truthiness: the clause matches unless the predicate
            # yields `false` or `null`.
            truthy?(predicate_result)
          end
        end
      else
        raise Unreachable, "Unknown pattern #{pattern.class}"
      end
    end

    def match_array(pattern, value, env)
      return false unless value.is_a?(Array)

      items = pattern.items
      rest_index = items.index { |e| e.is_a?(PatternRest) }

      if rest_index.nil?
        return false unless value.length == items.length

        items.each_with_index do |item, i|
          r = match(item.pattern, value[i], env)
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        true
      else
        before = items[0...rest_index]
        after  = items[(rest_index + 1)..]
        return false if value.length < before.length + after.length
        before.each_with_index do |item, i|
          r = match(item.pattern, value[i], env)
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        after.each_with_index do |item, k|
          vi = value.length - after.length + k
          r = match(item.pattern, value[vi], env)
          return r if r.is_a?(ErrorVal)
          return false unless r
        end
        rest_name = items[rest_index].name
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
      pattern.pairs.each do |pair|
        case pair
        when PatternRest
          rest_name = pair.name # may be nil (ignore) or a string
        when PatternPair
          return false unless value.key?(pair.key)
          r = match(pair.pattern, value[pair.key], env)
          return r if r.is_a?(ErrorVal)
          return false unless r
          matched_keys << pair.key
        else
          raise Unreachable, "Unknown object pattern pair #{pair.class}"
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
    # Ruby-style truthiness: `false` and `null` are falsey, everything else
    # (numbers, strings, arrays, objects, functions — including `0` and `""`) is
    # truthy. Used by `?` guards and the `@and` / `@or` / `@not` built-ins.
    def truthy?(value)
      value != false && value != NULL
    end

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
