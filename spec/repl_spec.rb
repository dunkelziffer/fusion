# frozen_string_literal: true

# In-process tests for the REPL's semantics: deciding when an entry is complete,
# evaluating expressions vs. statements, binding identifiers, and rendering.
#
# The Reline-driven input loop (#run) is the only boundary-specific part and is
# exercised by spec/cli_spec.rb; everything here calls the session methods
# directly, the way the rest of the language is specced in-process.
RSpec.describe Fusion::CLI::Repl do
  subject(:repl) { described_class.new }

  let(:division_by_zero) do
    '!{"kind":"math_error","location":"builtin divide","operation":"divide","input":[1,0],"message":"division by zero"}'
  end

  describe "#complete? — the editing termination check" do
    it "treats a blank buffer as complete (it is submitted, then skipped)" do
      expect(repl.complete?("")).to be(true)
      expect(repl.complete?("   \n  ")).to be(true)
    end

    it "is complete for a whole statement or expression" do
      expect(repl.complete?("x = 5")).to be(true)
      expect(repl.complete?("[1, 2, 3] | @length")).to be(true)
      expect(repl.complete?("[\n  1,\n  2\n]")).to be(true)
    end

    it "is not complete for an unfinished entry (keep editing)" do
      expect(repl.complete?("[1,")).to be(false)
      expect(repl.complete?("x =")).to be(false)
      expect(repl.complete?("(n =>")).to be(false)
      expect(repl.complete?("5 |")).to be(false)
    end

    it "is not complete for an otherwise invalid entry (let the user correct it)" do
      expect(repl.complete?("x = = 5")).to be(false)
      expect(repl.complete?("@ |")).to be(false)
    end
  end

  describe "#evaluate_entry — expressions" do
    it "evaluates and renders an expression without binding anything" do
      expect(repl.evaluate_entry("[1, 2, 3] | @length")).to eq("3")
    end

    it "renders an error expression as its payload" do
      expect(repl.evaluate_entry("[1, 0] | @divide")).to eq(division_by_zero)
    end

    it "renders a function leniently" do
      expect(repl.evaluate_entry("(n => [n, 2] | @multiply)")).to eq('"<function>"')
    end
  end

  describe "#evaluate_entry — statements" do
    it "evaluates, renders, and binds the identifier for later entries" do
      expect(repl.evaluate_entry("x = 5")).to eq("5")
      expect(repl.evaluate_entry("[x, 1] | @add")).to eq("6")
    end

    it "allows rebinding a name" do
      expect(repl.evaluate_entry("x = 1")).to eq("1")
      expect(repl.evaluate_entry("x = 2")).to eq("2")
      expect(repl.evaluate_entry("x")).to eq("2")
    end

    it "supports recursion through the bound name" do
      repl.evaluate_entry("fact = (0 => 1, n => [n, [n, 1] | @subtract | fact] | @multiply)")
      expect(repl.evaluate_entry("5 | fact")).to eq("120")
    end

    it "renders an error but does not bind it (a binder never captures an error)" do
      expect(repl.evaluate_entry("bad = [1, 0] | @divide")).to eq(division_by_zero)
      expect(repl.evaluate_entry("bad")).to eq(
        '!{"kind":"binding_error","location":"code <inline>",' \
        '"operation":"reading identifier bad","input":"bad","message":"unbound identifier"}'
      )
    end
  end

  describe "#evaluate_entry — the per-entry safety net" do
    it "turns a stack overflow into a stack_error and keeps the session alive" do
      repl.evaluate_entry("loop = (n => n | loop)")
      expect(repl.evaluate_entry("1 | loop")).to eq(
        '!{"kind":"stack_error","location":"interpreter",' \
        '"operation":"running the entry","input":null,"message":"recursion too deep"}'
      )
      expect(repl.evaluate_entry('"still alive"')).to eq('"still alive"')
    end
  end
end
