# frozen_string_literal: true

# === Interpreter internals ===
#
# A native (Ruby-implemented) function. Apply treats it like a Func.

module Fusion
  class Interpreter
    class NativeFunc
      attr_reader :name, :fn

      # `needs_call_site`: when true, `#dispatch_apply` passes the caller's call
      # site as a second argument to `fn` — needed by a builtin that itself
      # applies another function and must thread the site through (e.g. `@OP.map`
      # delegating to the stdlib `@map`).
      def initialize(name, fn, needs_call_site: false)
        @name = name
        @fn = fn
        @needs_call_site = needs_call_site
      end

      def needs_call_site?
        @needs_call_site
      end

      def inspect
        "<builtin #{name}>"
      end
    end
  end
end
