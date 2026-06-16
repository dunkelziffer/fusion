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
        .out("❌", '{"kind":"access_error","location":"code readenv.fsn","operation":".CI","input":[{},"CI"],"message":"missing key"}')
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
        .out("❌", a_string_including('"kind":"reference_error"', '"message":"file not found"', "nope.fsn"))
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
        .out("❌", a_string_including('"kind":"reference_error"', '"message":"file not found"', "subtract.fsn"))
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
        .out("❌", '{"kind":"reference_error","location":"code usesParent.fsn","operation":"resolving @../helper","input":"../helper","message":"outside the jail"}')
    end

    it "keeps the stdlib reachable from inside the default jail" do
      expect_pipe
        .in("✅", "5")
        .file_path("fact.fsn")
        .out("✅", "120")
    end

    it "blocks an @load target that escapes the jail, without probing its existence" do
      expect_pipe
        .code('"../nope" | @load')
        .out("❌", '{"kind":"reference_error","location":"builtin load","operation":"@load","input":"../nope","message":"outside the jail"}')
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
        .out("❌", '{"kind":"reference_error","location":"code usesAdd.fsn","operation":"resolving @add","input":"add","message":"outside the jail"}')
    end
  end
end
