# frozen_string_literal: true

# === Interpreter internals ===
#
# Lazy, memoized reference to a file's value (a "thunk" / promise).

module Fusion
  class Interpreter
    class FileThunk
      def initialize(loader, abspath)
        @loader = loader
        @abspath = abspath
        @state = :unforced # :unforced | :forcing | :done
        @value = nil
      end

      def force
        case @state
        when :done then @value
        when :forcing
          # We are already evaluating this file and were asked for it again
          # without any intervening function boundary => non-productive data cycle.
          ErrorVal.new({"kind" => "data_cycle", "path" => @abspath})
        else
          @state = :forcing
          @value = @loader.evaluate_file(@abspath)
          @state = :done
          @value
        end
      end
    end
  end
end
