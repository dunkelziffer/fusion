# frozen_string_literal: true

# In-process tests for the REPL's semantics: deciding when an entry is complete,
# evaluating expressions vs. statements, binding identifiers, and rendering.
#
# The Reline-driven input loop (#run) is the only boundary-specific part and is
# exercised by spec/cli_spec.rb; everything here calls the session methods
# directly, the way the rest of the language is specced in-process.

require "fusion/wire_pair"
require "fusion/cli/serializer"

RSpec.describe Fusion::CLI::Repl do
  subject(:repl) { described_class.new }

  let(:division_by_zero) do
    '{"kind":"math_error","location":"builtin divide","operation":"divide","input":[1,0],"message":"division by zero"}'
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

  describe "#evaluate_entry + #serialize (expressions)" do
    def serialize(value)
      Fusion::CLI::Serializer.serialize(value, lenient: true)
    end

    it "evaluates and renders an expression without binding anything" do
      expect(serialize(repl.evaluate_entry("[1, 2, 3] | @length"))).to eq(Fusion::WirePair.new(status: 0, data: "3"))
    end

    it "renders an error expression as its payload" do
      expect(serialize(repl.evaluate_entry("[1, 0] | @divide"))).to eq(Fusion::WirePair.new(status: 1, data: division_by_zero))
    end

    it "renders a function leniently" do
      expect(serialize(repl.evaluate_entry("(n => [n, 2] | @multiply)"))).to eq(Fusion::WirePair.new(status: 0, data: '"<function>"'))
    end
  end

  describe "#evaluate_entry + #serialize (statements)" do
    def serialize(value)
      Fusion::CLI::Serializer.serialize(value, lenient: true)
    end

    it "evaluates, renders, and binds the identifier for later entries" do
      expect(serialize(repl.evaluate_entry("x = 5"))).to eq(Fusion::WirePair.new(status: 0, data: "5"))
      expect(serialize(repl.evaluate_entry("[x, 1] | @add"))).to eq(Fusion::WirePair.new(status: 0, data: "6"))
    end

    it "allows rebinding a name" do
      expect(serialize(repl.evaluate_entry("x = 1"))).to eq(Fusion::WirePair.new(status: 0, data: "1"))
      expect(serialize(repl.evaluate_entry("x = 2"))).to eq(Fusion::WirePair.new(status: 0, data: "2"))
      expect(serialize(repl.evaluate_entry("x"))).to eq(Fusion::WirePair.new(status: 0, data: "2"))
    end

    it "supports recursion through the bound name" do
      repl.evaluate_entry("fact = (0 => 1, n => [n, [n, 1] | @subtract | fact] | @multiply)")
      expect(serialize(repl.evaluate_entry("5 | fact"))).to eq(Fusion::WirePair.new(status: 0, data: "120"))
    end

    it "renders an error but does not bind it (a binder never captures an error)" do
      expect(serialize(repl.evaluate_entry("bad = [1, 0] | @divide"))).to eq(Fusion::WirePair.new(status: 1, data: division_by_zero))
      expect(serialize(repl.evaluate_entry("bad"))).to eq(
        Fusion::WirePair.new(
          status: 1,
          data: '{"kind":"binding_error","location":"code <inline>",' \
        '"operation":"reading identifier bad","input":"bad","message":"unbound identifier"}'
        )
      )
    end
  end

  describe "#evaluate_entry + #serialize (per-entry safety net)" do
    def serialize(value)
      Fusion::CLI::Serializer.serialize(value, lenient: true)
    end

    it "turns a stack overflow into a stack_error and keeps the session alive" do
      repl.evaluate_entry("loop = (n => n | loop)")
      expect(serialize(repl.evaluate_entry("1 | loop"))).to eq(
        Fusion::WirePair.new(
          status: 1,
          data: '{"kind":"stack_error","location":"interpreter",' \
        '"operation":"running the entry","input":null,"message":"recursion too deep"}'
        )
      )
      expect(serialize(repl.evaluate_entry('"still alive"'))).to eq(Fusion::WirePair.new(status: 0, data: '"still alive"'))
    end
  end
end
