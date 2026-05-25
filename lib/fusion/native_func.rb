module Fusion
  # A native (Ruby-implemented) function. Apply treats it like a Func.
  class NativeFunc
    attr_reader :name, :fn
    def initialize(name, fn)
      @name = name
      @fn = fn
    end
    def inspect = "<builtin #{name}>"
  end
end
