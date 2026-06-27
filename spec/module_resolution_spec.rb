# frozen_string_literal: true

# @-resolution: how @name resolves against sibling files, the stdlib, builtins,
# self-recursion, @ENV and @load. Fixtures live in spec/fixtures/ref/.
RSpec.describe "@-resolution" do
  describe "sibling files shadow builtins" do
    it "lets a sibling add.fsn shadow the builtin @add" do
      expect_pipe
        .in("✅", "null")
        .file_path("ref/usesAdd.fsn")
        .out("✅", '"shadowed-add"')
    end

    it "falls back to the builtin @add when there is no sibling" do
      expect_pipe
        .in("✅", "null")
        .file_path("ref/sub/usesBuiltinAdd.fsn")
        .out("✅", "5")
    end
  end

  it "supports bare-@ self-recursion" do
    expect_pipe
      .in("✅", "3")
      .file_path("ref/countdown.fsn")
      .out("✅", "[3,2,1,0]")
  end

  # `@@` is the builtin/stdlib the file shadows — its own name resolved with the
  # sibling step skipped — so an override can extend what it replaces. The fixtures
  # tag their result with "viaSuper" to prove the sibling ran, and the real
  # builtin/stdlib value proves `@@` reached past the file itself (no self-cycle).
  describe "@@ super-reference" do
    it "reaches the builtin a sibling add.fsn shadows" do
      expect_pipe
        .in("✅", "null")
        .file_path("ref/super/usesSuperAdd.fsn")
        .out("✅", '[5,"viaSuper"]')
    end

    it "reaches the stdlib function a sibling range.fsn shadows" do
      expect_pipe
        .in("✅", "3")
        .file_path("ref/super/usesSuperRange.fsn")
        .out("✅", '[[0,1,2],"viaSuper"]')
    end

    it "errors when there is no enclosing file (an inline program)" do
      expect_pipe
        .code("@@")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@@","status":0,"input":null,"message":"no enclosing file"}')
    end
  end

  describe "@ENV" do
    it "reads an environment variable" do
      expect_pipe
        .in("✅", "null")
        .env(CI: "1")
        .file_path("ref/readenv.fsn")
        .out("✅", '"1"')
    end

    it "errors on a missing variable" do
      expect_pipe
        .in("✅", "null")
        .file_path("ref/readenv.fsn")
        .out("❌", '{"kind":"access_error","origin":"code","file":"spec/fixtures/ref/readenv.fsn","operation":".CI","status":0,"input":{},"message":"missing key"}')
    end

    it "is shadowable by a sibling ENV.fsn" do
      expect_pipe
        .in("✅", "null")
        .env(CI: "1")
        .file_path("ref/shadowenv/usesEnv.fsn")
        .out("✅", '"shadowed-env"')
    end

    it "resolves to the real environment when not shadowed" do
      expect_pipe
        .in("✅", "null")
        .env(CI: "1")
        .file_path("ref/readenv.fsn")
        .out("✅", '"1"')
    end
  end

  describe "@load" do
    it "loads a file verbatim by name" do
      expect_pipe
        .in("✅", '"data.config.fsn"')
        .file_path("ref/loader.fsn")
        .out("✅", '{"setting":"on"}')
    end

    it "errors when the file is missing" do
      expect_pipe
        .in("✅", '"nope.fsn"')
        .file_path("ref/loader.fsn")
        .out("❌", '{"kind":"reference_error","origin":"builtin","file":"spec/fixtures/ref/loader.fsn","operation":"@load","status":0,"input":"nope.fsn","message":"file not found"}')
    end

    # @load is a function taking a filename, not a 0-argument @-reference: a
    # non-string argument is an argument_error that echoes the value as `input`.
    it "errors when given a non-string argument" do
      expect_pipe
        .in("✅", "5")
        .code("(n => n | @load)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@load","status":0,"input":5,"expected":["_ ? @String"]}')
    end

    it "is shadowable by a sibling load.fsn" do
      expect_pipe
        .in("✅", "null")
        .file_path("ref/shadowload/usesLoad.fsn")
        .out("✅", '"shadowed-load"')
    end
  end

  describe "relative paths" do
    it "resolves @../helper from a subdir (jail widened to include the parent)" do
      expect_pipe
        .in("✅", "7")
        .jail("ref")
        .file_path("ref/sub/usesParent.fsn")
        .out("✅", "[7,7]")
    end

    it "lets a downward path @math/square fall through to a stdlib subdir" do
      expect_pipe
        .in("✅", "6")
        .file_path("ref/usesStdSub.fsn")
        .out("✅", "36")
    end

    it "lets a sibling subdir shadow a stdlib subdir method" do
      expect_pipe
        .in("✅", "6")
        .file_path("ref/usesLocalSub.fsn")
        .out("✅", '"local-square"')
    end

    it "treats @../subtract as file-only (no builtin fallback)" do
      expect_pipe
        .in("✅", "null")
        .jail("ref")
        .file_path("ref/sub/usesDotDotBuiltin.fsn")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"spec/fixtures/ref/sub/usesDotDotBuiltin.fsn","operation":"@../subtract","status":0,"input":null,"message":"file not found"}')
    end
  end

  # The jail confines file-backed @-resolution to a directory subtree. It governs
  # the program only — stdin is plain JSON and never holds an @-reference. The
  # default jail (here and in the CLI) is the program's own directory.
  describe "the jail" do
    it "blocks an @../ reference that escapes the default jail (the program's dir)" do
      expect_pipe
        .in("✅", "7")
        .file_path("ref/sub/usesParent.fsn")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"spec/fixtures/ref/sub/usesParent.fsn","operation":"@../helper","status":0,"input":null,"message":"outside the jail"}')
    end

    # @mapValues is a stdlib file that calls its stdlib sibling @map. Both must
    # load even under a tight, unrelated jail — the stdlib is exempt, and a
    # stdlib file's siblings are inside the stdlib, so no user jail can break them.
    it "keeps the stdlib and its internal sibling references reachable despite a tight jail" do
      expect_pipe
        .jail("ref/localmath")
        .code('(_ => {"f": (v => [v, 10] | @add), "object": {"a": 1, "b": 2}} | @mapValues)')
        .out("✅", '{"a":11,"b":12}')
    end

    it "blocks an @load target that escapes the jail, without probing its existence" do
      expect_pipe
        .code('"../nope" | @load')
        .out("❌", '{"kind":"reference_error","origin":"builtin","file":"<inline>","operation":"@load","status":0,"input":"../nope","message":"outside the jail"}')
    end

    it "disables confinement with a jail of *" do
      expect_pipe
        .in("✅", "7")
        .jail("*")
        .file_path("ref/sub/usesParent.fsn")
        .out("✅", "[7,7]")
    end

    # A sibling that exists but sits outside the jail is the jail error, never a
    # silent fall-through to the builtin/stdlib of the same name. Here @add has a
    # sibling ref/add.fsn, but the jail (ref/localmath) excludes it.
    it "errors on an out-of-jail sibling instead of falling back to the builtin" do
      expect_pipe
        .in("✅", "null")
        .jail("ref/localmath")
        .file_path("ref/usesAdd.fsn")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"spec/fixtures/ref/usesAdd.fsn","operation":"@add","status":0,"input":null,"message":"outside the jail"}')
    end
  end
end
