# frozen_string_literal: true

# === Utility ===
#
# Ruby's `Data` with `===` type per attribute. A type is anything `===`-able:
# a class (`Integer`), a regexp (`Identifier`), a marker module, or — for
# anything composite (unions, typed arrays, enums, "optional") — a `proc`.
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
end
