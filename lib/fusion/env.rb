module Fusion
  # =========================================================================
  # RUNTIME VALUES
  # =========================================================================

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

end
