import sys, os
sys.path.insert(0, ".")
from oracle import Interp, to_json, from_json

HERE=os.path.abspath("."); EX=os.path.join(HERE,"examples"); STD=os.path.join(HERE,"stdlib")
NF=os.path.join(EX,"newfeat")

results=[]
def chk(desc, got, exp):
    ok=(got==exp); results.append(ok)
    print(f"[{'ok  ' if ok else 'FAIL'}] {desc}")
    if not ok: print(f"        got: {got}\n        exp: {exp}")

def run(relpath, inp, env_vars=None):
    i=Interp(stdlib_dir=STD, env_vars=env_vars)
    fn=i.load_file(os.path.join(NF, relpath)).force()
    return to_json(i.apply(fn, from_json(inp)))

# 1. Sibling shadows builtin (per-file): newfeat/usesAdd.fsn sees local add.fsn
chk("sibling add.fsn shadows builtin @add", run("usesAdd.fsn","null"), '"shadowed-add"')
# 2. In a different dir (sub/) with no add.fsn, @add is the builtin
chk("no sibling -> @add is builtin", run("sub/usesBuiltinAdd.fsn","null"), "5")
# 3. bare @ self-reference recursion
chk("bare @ self-recursion countdown", run("countdown.fsn","3"), "[3,2,1,0]")
# 4. @ENV.CI reads env var as string
chk("@ENV.CI -> string", run("readenv.fsn","null", env_vars={"CI":"1"}), '"1"')
chk("@ENV.CI missing -> !", run("readenv.fsn","null", env_vars={}), '"!"')
# 5. @load with arbitrary filename containing a dot
chk("@load 'data.config.fsn' verbatim", run("loader.fsn",'"data.config.fsn"'), '{"setting":"on"}')
chk("@load missing file -> !", run("loader.fsn",'"nope.fsn"'), '"!"')
# 6. @../helper resolves up a dir (path ref, never builtin)
chk("@../helper from subdir", run("sub/usesParent.fsn","7"), "[7,7]")

# --- ENV / load shadowing (added after clarification) ---
# usesEnv.fsn sits next to ENV.fsn, so @ENV must resolve to the sibling file's value.
chk("sibling ENV.fsn shadows @ENV", run("shadowenv/usesEnv.fsn","null", env_vars={"CI":"1"}), '"shadowed-env"')
# A dir WITHOUT ENV.fsn still gets the real environment object.
chk("no sibling -> @ENV is real env", run("readenv.fsn","null", env_vars={"CI":"1"}), '"1"')
# usesLoad.fsn sits next to load.fsn, so @load must resolve to the sibling.
chk("sibling load.fsn shadows @load", run("shadowload/usesLoad.fsn","null"), '"shadowed-load"')


# --- Downward paths "dir/a" ARE eligible for stdlib/builtin (only "../" is not) ---
chk("@math/square falls through to stdlib subdir", run("usesStdSub.fsn","6"), "36")
chk("sibling subdir shadows stdlib subdir method", run("usesLocalSub.fsn","6"), '"local-square"')
chk("@../subtract is file-only (no builtin fallback) -> !", run("sub/usesDotDotBuiltin.fsn","null"), '"!"')

passed=sum(results); total=len(results)
print(f"\n{passed}/{total} new-feature tests passed")
sys.exit(0 if passed==total else 1)
