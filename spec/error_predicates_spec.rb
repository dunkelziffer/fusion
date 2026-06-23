# frozen_string_literal: true

# How errors interact with ?-predicates: a predicate that errors bubbles, and a
# !pat ? predicate sees the payload rather than the error wrapper.
RSpec.describe "errors and ?-predicates" do
  describe "predicate error bubbling" do
    it "makes the function return an error raised inside a predicate" do
      expect_pipe
        .in("✅", "5")
        .code('(x ? (n => [n,0] | @divide) => "matched", _ => "fallback")')
        .out("❌", '{"kind":"math_error","location":"builtin","operation":"divide","status":0,"input":[5,0],"message":"division by zero"}')
    end

    it "does not advance to the next clause on a predicate error" do
      expect_pipe
        .in("✅", "5")
        .code('(x ? (n => [n,0] | @divide) => "matched", x => "next clause")')
        .out("❌", '{"kind":"math_error","location":"builtin","operation":"divide","status":0,"input":[5,0],"message":"division by zero"}')
    end

    it "advances when a predicate returns false without erroring" do
      expect_pipe
        .in("✅", "5")
        .code('(x ? (_ => false) => "no", x => "yes")')
        .out("✅", '"yes"')
    end
  end

  describe "!pat ? predicate feeds the payload to the predicate" do
    it "sees the payload, not the error wrapper" do
      expect_pipe
        .in("✅", "7")
        .code('(x => !x | (!a ? @Integer => ["int", a], _ => "other"))')
        .out("✅", '["int",7]')
    end

    it "propagates the error when the predicate is false and nothing catches it" do
      expect_pipe
        .in("✅", '"hello"')
        .code('(x => !x | (!a ? @Integer => ["int", a], _ => "other"))')
        .out("❌", '"hello"')
    end

    it "lets a second error pattern catch the propagating error" do
      expect_pipe
        .in("✅", '"hello"')
        .code('(x => !x | (!a ? @Integer => ["int", a], !b => ["non-int", b]))')
        .out("✅", '["non-int","hello"]')
    end

    it "sees the payload with !_ ? predicate (no binder)" do
      expect_pipe
        .in("✅", "7")
        .code('(x => !x | (!_ ? @Integer => "int-error", _ => "other"))')
        .out("✅", '"int-error"')
    end

    it "propagates when the !_ payload fails the predicate" do
      expect_pipe
        .in("✅", '"hi"')
        .code('(x => !x | (!_ ? @Integer => "int-error", _ => "other"))')
        .out("❌", '"hi"')
    end

    it "accepts a redundant literal payload pattern plus predicate" do
      expect_pipe
        .in("✅", "42")
        .code('(x => !x | (!42 ? @Integer => "match", _ => "no"))')
        .out("✅", '"match"')
    end
  end
end
