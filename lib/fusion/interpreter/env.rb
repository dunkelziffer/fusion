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
        @context = {}  # hidden interpreter context, keyed by symbol (dir / file / self)
        @parent = parent
      end

      # Unchecked insert of a user-visible binding. Used by the REPL to keep a
      # bound name across entries (pattern binders go through #bind instead).
      def define(name, value)
        @vars[name] = value
        self
      end

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

      # Insert a pattern binding, rejecting a duplicate binder. Only this env's
      # own scope is checked: a binder may shadow a name from a parent env, but
      # must be unique within one pattern/clause.
      def bind(name, value)
        raise DuplicateBinding, name if @vars.key?(name)

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

      def child
        Env.new(self)
      end
    end
  end
end
