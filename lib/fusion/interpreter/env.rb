# frozen_string_literal: true

# === Interpreter internals ===
#
# Environment: maps names -> values, with a parent chain. Built-ins live at root.

module Fusion
  class Interpreter
    class Env
      # Raised by #bind when a name is already bound in this env's own scope —
      # i.e. a duplicate pattern binder like `[a, a]`. Interpreter#apply catches
      # it and reports a binding_error (see docs/user/reference.md §6.5).
      class DuplicateBinding < StandardError
        attr_reader :name

        def initialize(name)
          @name = name
          super("identifier already bound: #{name}")
        end
      end

      attr_reader :parent

      def initialize(parent = nil)
        @vars = {}     # pattern bindings, keyed by identifier
        @context = {}  # hidden interpreter context, keyed by symbol
        @parent = parent
      end

      def child
        Env.new(self)
      end

      # The topmost ancestor — the binding-free root a run is built on. The
      # interpreter loads files relative to it, so they stay isolated.
      def root
        @parent ? @parent.root : self
      end

      # Pattern bindings:
      # - Shadowing a binding from a parent Env is always allowed.
      # - A duplicate identifier in the same Env is usually an error, but allowed on the REPL.
      def bind(name, value, checked: true)
        if checked && @vars.key?(name)
          raise DuplicateBinding, name
        end

        @vars[name] = value
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

      # Hidden interpreter context:
      # - `:dir`:  the directory @-references resolve against (a path String).
      # - `:file`: the current file's absolute path, used for error origins (a
      #            String; absent for inline/REPL code, which reports as location
      #            "code" with no "file").
      # - `:self`: the current top-level unit's own Thunk, used for recursion via a bare `@`.
      # - `:jail`: the run's jail root confining @-resolution (an absolute path
      #            String, or nil for unconfined). Set once on the root and, unlike
      #            the others, never overridden by a descendant.
      def set_context(key, value)
        @context[key] = value
        self
      end

      def context(key)
        if @context.key?(key)
          @context[key]
        elsif @parent
          @parent.context(key)
        else
          :__unbound__
        end
      end
    end
  end
end
