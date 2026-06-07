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
    it "resolves @../helper from a subdir" do
      expect_pipe
        .in("✅", "7")
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
        .file_path("ref/sub/usesDotDotBuiltin.fsn")
        .out("❌", a_string_including('"kind":"reference_error"', '"message":"file not found"', "subtract.fsn"))
    end
  end
end
