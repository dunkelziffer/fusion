# frozen_string_literal: true

# @-resolution: how @name resolves against sibling files, the stdlib, builtins,
# self-recursion, @ENV and @load. Fixtures live in spec/fixtures/ref/.
RSpec.describe "@-resolution" do
  describe "sibling files shadow builtins" do
    it "lets a sibling range.fsn shadow @range" do
      expect_pipe
        .in("✅", "null")
        .file_path("ref/usesRange.fsn")
        .out("✅", '"shadowed-range"')
    end

    it "falls back to the default @range when there is no sibling" do
      expect_pipe
        .in("✅", "null")
        .file_path("ref/sub/usesBuiltinRange.fsn")
        .out("✅", "[0,1,2]")
    end
  end

  # A local file that derives from `@OP.*` resolves the operator object in its own
  # directory, so an `OP.fsn` override reskins both the operator and that helper.
  describe "reskinning @OP per directory" do
    it "makes a local helper follow an OP.fsn override of @OP.sum" do
      # ref/reskin/OP.fsn overrides `sum`; both @OP.sum and the local @plus see it.
      expect_pipe
        .in("✅", "[1,2]")
        .file_path("ref/reskin/probe.fsn")
        .out("✅", '["reskinned","reskinned"]')
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

  # `@@name` is the stable form: it resolves `name` skipping the sibling `name.fsn`,
  # so a local shadow can't intercept it (used by error patterns and escape hatches).
  describe "@@name stable references" do
    it "skips a sibling shadow and reaches the stdlib" do
      # ref/stable/all.fsn shadows @all; @all hits it ("shadowed"), @@all doesn't.
      expect_pipe
        .in("✅", '["a","b"]')
        .file_path("ref/stable/probe.fsn")
        .out("✅", '["shadowed",true]')
    end

    it "resolves a stable builtin regardless of shadowing" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @@Integer)")
        .out("✅", "true")
    end

    it "rejects an upward @@../ path as a syntax error" do
      expect_pipe
        .code("(_ => @@../x)")
        .out("❌", a_string_including('"kind":"syntax_error"', '"origin":"code"', '"file":"<inline>"', '"operation":"parsing code"', '"message":'))
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
        .env(CI: "real-env")
        .file_path("ref/readenv.fsn")
        .out("✅", '"real-env"')
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

    # loadcycleA and loadcycleB @load each other at data time. The cycle is
    # reported under the @load that re-entered, echoing its filename argument
    # (the operation stays "@load" — the resolve/read stages don't leak).
    it "errors on a cycle reached through @load" do
      expect_pipe
        .in("✅", "null")
        .file_path("loadcycleA.fsn")
        .out("❌", '{"kind":"reference_error","origin":"builtin","file":"spec/fixtures/loadcycleB.fsn","operation":"@load","status":0,"input":"loadcycleA.fsn","message":"non-productive data cycle"}')
    end

    # A file's thunk is shared across references, but a read-failure error depends
    # on the *forcing* reference (its `input`). Loading the same directory twice via
    # different arguments ("ref/sub/../adir.fsn" then "ref/adir.fsn" — same path)
    # must report each call's own `input`, not return the first's cached error. The
    # first load is caught; the array then surfaces the second's error.
    it "a read-failure error reflects the forcing reference, not a cached earlier one" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => [("ref/sub/../adir.fsn" | @load) | (! => "_"), "ref/adir.fsn" | @load])')
        .out("❌", a_string_including('"kind":"reference_error"', '"origin":"builtin"', '"operation":"@load"', '"input":"ref/adir.fsn"', /"message":"[^"]*directory[^"]*"/))
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

    it "resolves a downward path to a sibling subdirectory" do
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

    # A path reference to a directory (here a dir literally named "adir.fsn") fails
    # the read; like @../subtract it stays one operation ("@../adir", input null),
    # the message being the lowercased, machine-dependent strerror.
    it "errors when @../adir points at a directory" do
      expect_pipe
        .in("✅", "null")
        .jail("ref")
        .file_path("ref/sub/usesDotDotDir.fsn")
        .out("❌", a_string_including('"kind":"reference_error"', '"origin":"code"', '"file":"spec/fixtures/ref/sub/usesDotDotDir.fsn"', '"operation":"@../adir"', '"status":0', '"input":null', /"message":"[^"]*directory[^"]*"/))
    end
  end

  # @-references nest: forcing a file's thunk runs its body, which may reference
  # another file and force *its* thunk. When the deepest reference hits a read
  # failure, the error is built at that innermost force — so it reports the
  # reference that directly named the missing file, not the enclosing one.
  # Here readChainOuter @readChainInner, and readChainInner @../readChainMissing
  # (which does not exist): the error names readChainInner / @../readChainMissing,
  # never readChainOuter / @readChainInner.
  describe "nested references" do
    it "reports the innermost reference that hit the read failure, not the enclosing one" do
      expect_pipe
        .in("✅", "null")
        .jail("ref")
        .file_path("ref/sub/readChainOuter.fsn")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"spec/fixtures/ref/sub/readChainInner.fsn","operation":"@../readChainMissing","status":0,"input":null,"message":"file not found"}')
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

    # @sanitize is a stdlib file that calls stdlib siblings (@map, @concat). All
    # must load even under a tight, unrelated jail — the stdlib is exempt, and a
    # stdlib file's siblings are inside the stdlib, so no user jail can break them.
    it "keeps the stdlib and its internal sibling references reachable despite a tight jail" do
      expect_pipe
        .jail("ref/localmath")
        .code('(_ => {"a": 1, "b": [1e400]} | @sanitize)')
        .out("✅", '{"a":1,"b":["<Infinity>"]}')
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
    # silent fall-through to the builtin/stdlib of the same name. Here @range has a
    # sibling ref/range.fsn, but the jail (ref/localmath) excludes it.
    it "errors on an out-of-jail sibling instead of falling back to the builtin" do
      expect_pipe
        .in("✅", "null")
        .jail("ref/localmath")
        .file_path("ref/usesRange.fsn")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"spec/fixtures/ref/usesRange.fsn","operation":"@range","status":0,"input":null,"message":"outside the jail"}')
    end
  end
end
