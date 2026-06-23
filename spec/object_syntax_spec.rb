# frozen_string_literal: true

# Syntactic structure rules for objects (literals and patterns): a fixed key may
# not repeat, and an object pattern's `...rest` must be the last member. Both are
# caught at parse time as a syntax_error.
RSpec.describe "object syntax" do
  describe "a fixed key may not repeat" do
    [
      ['{"a": 1, "a": 2}',        "duplicate key in an object literal"],
      ['({"a": x, "a": y} => x)', "duplicate key in an object pattern"],
      ['{"a": 1, "b": 2, "a": 3}', "duplicate key among other keys"],
    ].each do |src, why|
      it "rejects #{why}" do
        expect_pipe
          .code(src)
          .out("❌", a_string_including('"kind":"syntax_error"', '"location":"code"'))
      end
    end

    it "allows a key that a spread also carries (spreads are dynamic)" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"a": 1, ...{"a": 2}})')
        .out("✅", '{"a":2}')
    end
  end

  describe "an object pattern's ...rest must be last" do
    [
      ['({"a": x, ...r, "b": y} => x)', "a pair after the rest"],
      ['({...r, "a": x} => x)',         "the rest before a pair"],
    ].each do |src, why|
      it "rejects #{why}" do
        expect_pipe
          .code(src)
          .out("❌", a_string_including('"kind":"syntax_error"', '"location":"code"'))
      end
    end

    it "accepts a rest in the last position" do
      expect_pipe
        .in("✅", '{"a": 1, "b": 2}')
        .code('({"a": x, ...r} => r)')
        .out("✅", '{"b":2}')
    end
  end
end
