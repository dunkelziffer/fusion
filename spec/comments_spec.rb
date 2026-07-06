# frozen_string_literal: true

# Comment syntax: whole-line "#" only, no inline comments; raw newlines in
# strings are forbidden.
RSpec.describe "comments", mutant_expression: "Fusion::CLI*" do
  describe "accepted forms" do
    it "ignores a full-line # comment" do
      expect_pipe
        .in("✅", "null")
        .code("# this is a comment\n(_ => 1)")
        .out("✅", "1")
    end

    it "ignores an indented # comment" do
      expect_pipe
        .in("✅", "null")
        .code("\t   # indented comment\n(_ => 1)")
        .out("✅", "1")
    end

    it "treats a shebang line as a comment" do
      expect_pipe
        .in("✅", "null")
        .code("#!/usr/bin/env fusion\n(_ => 1)")
        .out("✅", "1")
    end

    it "ignores a comment between tokens" do
      expect_pipe
        .in("✅", "null")
        .code("(_ =>\n# pick one\n1)")
        .out("✅", "1")
    end

    it "treats # inside a string as a literal character" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => "#notacomment")')
        .out("✅", '"#notacomment"')
    end
  end

  describe "rejected forms" do
    it "rejects a trailing inline comment" do
      expect_pipe
        .code("(_ => 1) # nope")
        .out("❌", a_string_including('"kind":"syntax_error"', '"origin":"code"', '"file":"<inline>"', '"operation":"parsing code"', '"status":0', '"input":"(_ => 1) # nope"', '"message":'))
    end

    it "rejects a mid-line # comment" do
      expect_pipe
        .code("(_ => 1 # nope\n)")
        .out("❌", a_string_including('"kind":"syntax_error"', '"origin":"code"', '"file":"<inline>"', '"operation":"parsing code"', '"status":0', '"input":"(_ => 1 # nope\n)"', '"message":'))
    end

    it "rejects a raw newline inside a string" do
      expect_pipe
        .code("(_ => \"line1\nline2\")")
        .out("❌", a_string_including('"kind":"syntax_error"', '"origin":"code"', '"file":"<inline>"', '"operation":"parsing code"', '"status":0', '"input":"(_ => \"line1\nline2\")"', '"message":'))
    end
  end
end
