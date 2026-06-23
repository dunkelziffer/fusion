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

  describe "object patterns are closed without a rest" do
    it "matches when the keys are exactly the named ones" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code('({"a": x} => x)')
        .out("✅", "1")
    end

    it "does not match when a superfluous key is present" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code('({"a": x} => x)')
        .out("✅", "null")
    end

    it "a bare ... reopens it to ignore extra keys" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code('({"a": x, ...} => x)')
        .out("✅", "1")
    end
  end

  describe "duplicate binders" do
    it "rejects a repeated binder in an array pattern" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("([a, a] => a)")
        .out("❌", '{"kind":"binding_error","location":"code","operation":"binding identifier a","status":0,"input":"a","message":"identifier already bound"}')
    end

    it "rejects a repeated binder across object members" do
      expect_pipe
        .in("✅", '{"x":1,"y":2}')
        .code('({"x": v, "y": v} => v)')
        .out("❌", '{"kind":"binding_error","location":"code","operation":"binding identifier v","status":0,"input":"v","message":"identifier already bound"}')
    end

    it "rejects a binder that collides with a rest binder" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("([a, ...a] => a)")
        .out("❌", '{"kind":"binding_error","location":"code","operation":"binding identifier a","status":0,"input":"a","message":"identifier already bound"}')
    end

    it "does not reject the duplicate when the clause's shape does not match (clause simply does not apply)" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("([a, a] => a)")
        .out("✅", "null")
    end

    it "still allows distinct binders" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("([a, b] => [b, a])")
        .out("✅", "[2,1]")
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

    it "does not let the predicate expression see the pattern's sibling binders" do
      # `a` in the predicate position resolves in the clause's lexical env, not
      # against the sibling binder `a`, so it is unbound.
      expect_pipe
        .in("✅", "[1,2]")
        .code("([a, b ? a] => \"matched\")")
        .out("❌", '{"kind":"binding_error","location":"code","operation":"reading identifier a","status":0,"input":"a","message":"unbound identifier"}')
    end

    it "matches on any truthy predicate result, not only true" do
      # The predicate returns 1 (truthy), so the guard holds.
      expect_pipe
        .in("✅", "0")
        .code('(n ? (_ => 1) => "yes", _ => "no")')
        .out("✅", '"yes"')
    end

    it "fails the guard when the predicate yields null or false" do
      expect_pipe
        .in("✅", "7")
        .code('(n ? (_ => null) => "yes", _ => "no")')
        .out("✅", '"no"')
    end

    it "chains functions in the predicate: a ? b | c tests a | b | c" do
      # 5 | @not = false, false | @not = true → truthy → matches.
      expect_pipe
        .in("✅", "5")
        .code('(x ? @not | @not => "even-negations", _ => "no")')
        .out("✅", '"even-negations"')
    end

    describe "an error bubbles only at the end of the predicate chain" do
      # The first stage `(_ => !"boom")` always raises; what matters is whether a
      # later stage catches it before the chain ends.
      it "matches when a later stage catches the error and returns truthy" do
        expect_pipe
          .in("✅", "5")
          .code('(n ? (_ => !"boom") | (!x => true) => "matched", _ => "no match")')
          .out("✅", '"matched"')
      end

      it "fails without bubbling when a later stage catches it and returns falsey" do
        expect_pipe
          .in("✅", "5")
          .code('(n ? (_ => !"boom") | (!x => false) => "matched", _ => "no match")')
          .out("✅", '"no match"')
      end

      it "bubbles when no later stage catches the error" do
        expect_pipe
          .in("✅", "5")
          .code('(n ? (_ => !"boom") | @Integer => "matched", _ => "no match")')
          .out("❌", '"boom"')
      end
    end
  end
end
