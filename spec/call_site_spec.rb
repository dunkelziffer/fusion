# frozen_string_literal: true

# The error `file` is the innermost user-code file on the call chain when the
# operation failed (docs/lang/design.md §2.13): builtin/stdlib frames are skipped
# through to the nearest code you wrote. These cases pin it across three axes —
#   - location:  "<fusion>" (above all user code) vs "<inline>" vs a user file
#   - source:    a builtin, a stdlib function, or a syntactic op (`.name`, `[]`, `|`)
#   - depth:     a directly-piped operation vs one reached through `@map`
RSpec.describe "the error `file` (innermost user-code call site)" do
  # The program is a bare operation; the CLI applies it to the input directly, so
  # the failure has no user-code frame around it. Only *direct* failures arise
  # here — a nested one would need a function argument, which JSON input can't carry.
  describe "above all user code (\"<fusion>\")" do
    it "a builtin applied directly to the input" do
      expect_pipe
        .in("✅", "[1,0]")
        .code("@math.divide")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<fusion>","operation":"@math.divide","status":0,"input":[1,0],"message":"division by zero"}')
    end

    it "a stdlib function applied directly to the input" do
      expect_pipe
        .in("✅", "5")
        .code("@map")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<fusion>","operation":"@map","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "piping the input into a non-function program" do
      expect_pipe
        .in("✅", "null")
        .code("42")
        .out("❌", '{"kind":"argument_error","origin":"code","file":"<fusion>","operation":"|","status":0,"input":[null,42],"expected":["[_, _ ? @Function]"]}')
    end
  end

  describe "in inline code (\"<inline>\")" do
    it "a builtin piped directly" do
      expect_pipe
        .in("✅", '["a","b"]')
        .code("(p => p | @OP.sum)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":["a","b"],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end

    it "a stdlib function piped directly" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @map)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "a member access (.name)" do
      expect_pipe
        .in("✅", "5")
        .code("(n => n.foo)")
        .out("❌", '{"kind":"argument_error","origin":"code","file":"<inline>","operation":".foo","status":0,"input":5,"expected":["_ ? @Object"]}')
    end

    it "an index ([])" do
      expect_pipe
        .in("✅", "[10,20]")
        .code("(a => a[5])")
        .out("❌", '{"kind":"access_error","origin":"code","file":"<inline>","operation":"[]","status":0,"input":[[10,20],5],"message":"index out of range"}')
    end

    it "a builtin reached through @map" do
      expect_pipe
        .in("✅", '[["a","b"]]')
        .code('(xs => {"f": @OP.sum, "xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":["a","b"],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end

    it "a stdlib function reached through @map" do
      expect_pipe
        .in("✅", '["x"]')
        .code('(xs => {"f": @math/square, "xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@math/square","status":0,"input":"x","expected":["_ ? @Integer"]}')
    end
  end

  # The four `callsite/*.fsn` fixtures are each a one-line function; the `file` is
  # their `Dir.pwd`-relative path, the same whatever the failure depth.
  describe "in a user file" do
    it "a builtin piped directly" do
      expect_pipe
        .in("✅", '["a","b"]')
        .file_path("callsite/builtin.fsn")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"spec/fixtures/callsite/builtin.fsn","operation":"@OP.sum","status":0,"input":["a","b"],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end

    it "a stdlib function piped directly" do
      expect_pipe
        .in("✅", "5")
        .file_path("callsite/stdlib.fsn")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"spec/fixtures/callsite/stdlib.fsn","operation":"@map","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "a member access (.name)" do
      expect_pipe
        .in("✅", '{"a":1}')
        .file_path("callsite/member.fsn")
        .out("❌", '{"kind":"access_error","origin":"code","file":"spec/fixtures/callsite/member.fsn","operation":".missing","status":0,"input":{"a":1},"message":"missing key"}')
    end

    it "a builtin reached through @map (still the file that called @map)" do
      expect_pipe
        .in("✅", '[["a","b"]]')
        .file_path("callsite/nested.fsn")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"spec/fixtures/callsite/nested.fsn","operation":"@OP.sum","status":0,"input":["a","b"],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end
  end
end
