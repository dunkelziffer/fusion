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

  # `TypedData::Union(a, b, ...)` — a field matching any one of the alternatives.
  def self.Union(*alternatives)
    Union.new(*alternatives)
  end

  # `TypedData::ArrayOf(item)` — a field holding an array of `item`s.
  def self.ArrayOf(item)
    ArrayOf.new(item)
  end

  # Matches any one of several alternatives. An alternative is anything that
  # responds to `===`: a class (`Integer`), a literal value (`true`, `:null`,
  # `nil`), a marker module, or a nested matcher.
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

  # Matches an array whose every element matches `item` (anything `===`-able).
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
end
