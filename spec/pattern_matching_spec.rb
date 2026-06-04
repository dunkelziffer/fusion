# frozen_string_literal: true

# Core matching semantics: clause selection, wildcards, destructuring and guards.
RSpec.describe "pattern matching" do
  describe "clause selection" do
    it "returns null when nothing matches (lenient)" do
      expect_pipe
        .in("✅", "99")
        .code("(1 => 2)")
        .out("✅", "null")
    end

    it "errors when nothing matches and a clause demands it (strict)" do
      expect_pipe
        .in("✅", "99")
        .code("(1 => 2, _ => !)")
        .out("❌", "null")
    end

    it "matches an ordinary value with a wildcard" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1)")
        .out("✅", "1")
    end
  end

  describe "destructuring" do
    it "destructures an object with a rest binding" do
      expect_pipe
        .in("✅", '{"a":1,"b":2,"c":3}')
        .code('({"a": x, ...rest} => [x, rest])')
        .out("✅", '[1,{"b":2,"c":3}]')
    end

    it "splits an array into init and last via rest" do
      expect_pipe
        .in("✅", "[1,2,3,4]")
        .code("([...init, last] => [init, last])")
        .out("✅", "[[1,2,3],4]")
    end
  end

  describe "guards (?)" do
    it "matches when the type guard holds" do
      expect_pipe
        .in("✅", "5")
        .code('(n ? @Integer => "int", _ => "other")')
        .out("✅", '"int"')
    end

    it "rejects when the type guard fails" do
      expect_pipe
        .in("✅", '"hi"')
        .code('(n ? @Integer => "int", _ => "other")')
        .out("✅", '"other"')
    end

    it "applies a relational guard to the parent container (a<b)" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('([a,b] ? ([x,y] => [x,y] | @lessThan) => "asc", _ => "not")')
        .out("✅", '"asc"')
    end

    it "rejects when the relational guard fails (a>=b)" do
      expect_pipe
        .in("✅", "[2,1]")
        .code('([a,b] ? ([x,y] => [x,y] | @lessThan) => "asc", _ => "not")')
        .out("✅", '"not"')
    end
  end
end
