# frozen_string_literal: true

# === Utility ===
#
# Ruby's `Data` with `===` type per attribute.
# Mini-clone of gem `literal`.

module TypedData
  def self.define(**schema)
    Data.define(*schema.keys) do
      define_method(:initialize) do |**kwargs|
        kwargs.each_key do |key|
          unless schema[key] === kwargs[key]
            raise TypeError, "#{key}: expected #{schema[key]}, got #{kwargs[key].inspect} (#{kwargs[key].class})"
          end
        end
        super(**kwargs)
      end
    end
  end

  # A field that matches any one of several alternatives. An alternative is
  # anything that responds to `===`: a class (`Integer`), a literal value
  # (`true`, `:null`, `nil`), a marker module, or a nested matcher.
  class Union
    def initialize(*alternatives)
      @alternatives = alternatives
    end

    def ===(value)
      @alternatives.any? { |alternative| alternative === value }
    end

    def inspect
      @alternatives.map(&:inspect).join(" | ")
    end
    alias_method :to_s, :inspect
  end

  # A field holding an array whose every element matches `item` (anything that
  # responds to `===`). Use the `_Array(item)` shorthand to build one.
  class ArrayOf
    def initialize(item)
      @item = item
    end

    def ===(value)
      value.is_a?(Array) && value.all? { |element| @item === element }
    end

    def inspect
      "Array(#{@item.inspect})"
    end
    alias_method :to_s, :inspect
  end

  def self._Array(item)
    ArrayOf.new(item)
  end
end
