# frozen_string_literal: true

# === Interpreter internals ===
#
# A native (Ruby-implemented) function. Apply treats it like a Func.

module Fusion
  class Interpreter
    class NativeFunc
      attr_reader :name, :fn

      def initialize(name, fn)
        @name = name
        @fn = fn
      end

      def inspect
        "<builtin #{name}>"
      end
    end
  end
end
