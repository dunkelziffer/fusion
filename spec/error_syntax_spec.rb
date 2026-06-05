# frozen_string_literal: true

# Syntactic rules for error patterns: errors may not be nested inside other
# patterns, while legitimate top-level !pat forms still parse and run.
RSpec.describe "error pattern syntax" do
  describe "nested error patterns are rejected" do
    [
      ["([!a, b] => a)",       "error inside an array pattern"],
      ['({"e": !x} => x)',     "error inside an object pattern"],
      ["([..., !x] => x)",     "error after a rest in an array"],
      ['(!!42 => "x")',        "nested error pattern (!!)"],
      ['(!{"k": !v} => v)',    "error nested in an object payload"],
      ["(![!a] => a)",         "error nested in an array payload"],
      ['(! ? @Integer => "x")', "bare ! carrying a predicate (no payload to refer to)"],
    ].each do |src, why|
      it "rejects #{why}" do
        expect_pipe
          .code(src)
          .out("❌", a_string_including('"kind":"parse_error"', '"location":"code <inline>"'))
      end
    end
  end

  describe "legitimate error patterns still work" do
    it "parses and runs a top-level !pat (no match on non-error input)" do
      expect_pipe
        .in("✅", "null")
        .code("(!a => a)")
        .out("✅", "null")
    end

    it "destructures an object payload" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => !{"kind": "x", "msg": "hi"} | (!{"kind": k} => k))')
        .out("✅", '"x"')
    end

    it "destructures an array payload" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => ![1,2,3] | (![a, b, c] => [c, b, a]))")
        .out("✅", "[3,2,1]")
    end
  end
end
