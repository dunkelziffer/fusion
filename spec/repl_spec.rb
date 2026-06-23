# frozen_string_literal: true

# In-process tests for the REPL's semantics: deciding when an entry is complete,
# evaluating expressions vs. statements, binding identifiers, and rendering.
#
# The Reline-driven input loop (#run) is the only boundary-specific part and is
# exercised by spec/cli_spec.rb; everything here calls the session methods
# directly, the way the rest of the language is specced in-process.

RSpec.describe Fusion::CLI::Repl do
  # `#run` builds the session env itself; `#handle` (what these tests drive) takes
  # the environment as an argument, so the constructor's root_env is unused here.
  subject(:repl) { described_class.new(root_env: Fusion::Interpreter::Env.new) }

  # A fresh session environment, built the way #run does, so a binding made by
  # one entry is visible to the next within an example.
  let(:environment) { Fusion::Interpreter::Env.new.set_context(:dir, Dir.pwd) }

  let(:division_by_zero) do
    '{"kind":"math_error","location":"builtin","operation":"divide","status":0,"input":[1,0],"message":"division by zero"}'
  end

  let(:self_cycle) do
    '{"kind":"reference_error","location":"code","operation":"forcing a reference","status":0,"input":null,"message":"non-productive data cycle"}'
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

  describe "#handle (expressions)" do
    it "evaluates and renders an expression without binding anything" do
      expect(repl.handle("[1, 2, 3] | @length", environment)).to eq("3")
    end

    it "renders an error expression with a `!` prefix" do
      expect(repl.handle("[1, 0] | @divide", environment)).to eq("!#{division_by_zero}")
    end

    it "renders a function leniently" do
      expect(repl.handle("(n => [n, 2] | @multiply)", environment)).to eq('"<function>"')
    end

    it "renders an @-using function leniently — the @ is deferred until it is applied" do
      expect(repl.handle("(0 => 1, n => [n, [n, 1] | @subtract | @] | @multiply)", environment)).to eq('"<function>"')
    end

    it "resolves a bare @ to the entry's own value (forcing it in data position is a self-data-cycle)" do
      expect(repl.handle("[1, @]", environment)).to eq("!#{self_cycle}")
    end
  end

  describe "#handle (statements)" do
    it "evaluates, renders, and binds the identifier for later entries" do
      expect(repl.handle("x = 5", environment)).to eq("5")
      expect(repl.handle("[x, 1] | @add", environment)).to eq("6")
    end

    it "allows rebinding a name" do
      expect(repl.handle("x = 1", environment)).to eq("1")
      expect(repl.handle("x = 2", environment)).to eq("2")
      expect(repl.handle("x", environment)).to eq("2")
    end

    it "supports recursion through the bound name" do
      repl.handle("fact = (0 => 1, n => [n, [n, 1] | @subtract | fact] | @multiply)", environment)
      expect(repl.handle("5 | fact", environment)).to eq("120")
    end

    it "supports recursion through a bare @ (the entry's own value)" do
      repl.handle("fact = (0 => 1, n => [n, [n, 1] | @subtract | @] | @multiply)", environment)
      expect(repl.handle("5 | fact", environment)).to eq("120")
    end

    it "allows binding errors to identifiers and renders errors with a `!` prefix" do
      expect(repl.handle("bad = [1, 0] | @divide", environment)).to eq("!#{division_by_zero}")
      expect(repl.handle("bad", environment)).to eq("!#{division_by_zero}")
    end
  end

  describe "#handle (per-entry safety net)" do
    it "turns a stack overflow into a runtime_error and keeps the session alive" do
      repl.handle("loop = (n => n | loop)", environment)
      expect(repl.handle("1 | loop", environment)).to eq(
        '!{"kind":"runtime_error","location":"interpreter",' \
        '"operation":"running the program","status":0,"input":null,"message":"stack level too deep"}'
      )
      expect(repl.handle('"still alive"', environment)).to eq('"still alive"')
    end
  end
end
