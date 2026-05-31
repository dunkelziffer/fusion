#!/usr/bin/env python3
import sys, os, json
sys.path.insert(0, os.path.dirname(__file__))
from oracle import Interp, Parser, Env, to_json, from_json, ERROR, NULL

HERE = os.path.dirname(os.path.abspath(__file__))
STDLIB = os.path.join(HERE, "stdlib")
EX = os.path.join(HERE, "examples")

def run_file(relpath, input_json):
    interp = Interp(stdlib_dir=STDLIB)
    fn = interp.load_file(os.path.join(EX, relpath)).force()
    val = from_json(input_json)
    res = interp.apply(fn, val)
    return to_json(res)

def run_src(src, input_json):
    interp = Interp(stdlib_dir=STDLIB)
    ast = Parser.parse_file(src)
    env = interp.root.child(); env.define("__dir__", EX)
    fn = interp.eval(ast, env)
    res = interp.apply(fn, from_json(input_json))
    return to_json(res)

tests = []
def check(desc, got, expected):
    ok = got == expected
    tests.append(ok)
    mark = "ok  " if ok else "FAIL"
    print(f"[{mark}] {desc}")
    if not ok:
        print(f"        got:      {got}")
        print(f"        expected: {expected}")

# --- File-based examples ---
check("double 21 -> 42", run_file("double.fsn", "21"), "42")
check("swap [1,2] -> [2,1]", run_file("swap.fsn", "[1,2]"), "[2,1]")
check("fact 5 -> 120 (self-recursion via @fact)", run_file("fact.fsn", "5"), "120")
check("fact 0 -> 1", run_file("fact.fsn", "0"), "1")
check("fact \"x\" -> ! (strict, non-integer)", run_file("fact.fsn", '"x"'), '"!"')
check("sum [1,2,3,4] -> 10 (self-recursion via @sum)", run_file("sum.fsn", "[1,2,3,4]"), "10")
check("sum [] -> 0", run_file("sum.fsn", "[]"), "0")
check("main [1,2,3] -> [2,4,6] (uses @double + @map)", run_file("main.fsn", "[1,2,3]"), "[2,4,6]")
check("fizzbuzz 15 -> FizzBuzz", run_file("fizzbuzz.fsn", "15"), '"FizzBuzz"')
check("fizzbuzz 9 -> Fizz", run_file("fizzbuzz.fsn", "9"), '"Fizz"')
check("fizzbuzz 10 -> Buzz", run_file("fizzbuzz.fsn", "10"), '"Buzz"')
check("fizzbuzz 7 -> 7", run_file("fizzbuzz.fsn", "7"), "7")
check("safeDivide [10,2] -> 5", run_file("safeDivide.fsn", "[10,2]"), "5")
check("safeDivide [10,0] -> !", run_file("safeDivide.fsn", "[10,0]"), '"!"')

# --- Inline source tests for core semantics ---
check("lenient no-match -> null", run_src("(1 => 2)", "99"), "null")
check("strict no-match -> !", run_src("(1 => 2, _ => !)", "99"), '"!"')
check("wildcard matches ordinary value -> 1", run_src("(_ => 1)", "null"), "1")
check("object destructure + rest",
      run_src('({"a": x, ...rest} => [x, rest])', '{"a":1,"b":2,"c":3}'),
      '[1,{"b":2,"c":3}]')
check("array init+last via rest",
      run_src("([...init, last] => [init, last])", "[1,2,3,4]"),
      "[[1,2,3],4]")
check("guard ? @Integer matches",
      run_src("(n ? @Integer => \"int\", _ => \"other\")", "5"), '"int"')
check("guard ? @Integer rejects string",
      run_src("(n ? @Integer => \"int\", _ => \"other\")", '"hi"'), '"other"')
check("relational guard on parent container (a<b)",
      run_src("([a,b] ? ([x,y] => [x,y] | @lessThan) => \"asc\", _ => \"not\")", "[1,2]"), '"asc"')
check("relational guard rejects (a>=b)",
      run_src("([a,b] ? ([x,y] => [x,y] | @lessThan) => \"asc\", _ => \"not\")", "[2,1]"), '"not"')
check("member access present", run_src('(o => o.name)', '{"name":"bob"}'), '"bob"')
check("member access missing -> !", run_src('(o => o.nope)', '{"name":"bob"}'), '"!"')
check("index access", run_src("(a => a[1])", "[10,20,30]"), "20")
check("negative index", run_src("(a => a[-1])", "[10,20,30]"), "30")
check("index out of range -> !", run_src("(a => a[9])", "[10,20,30]"), '"!"')
check("divide by zero -> !", run_src("(p => p | @divide)", "[1,0]"), '"!"')
check("type error in add -> !", run_src("(p => p | @add)", '["a","b"]'), '"!"')
check("deep equality structural", run_src("(p => p | @equals)", "[[1,[2]],[1,[2]]]"), "true")
check("null is ordinary data (matches binder)", run_src("(x => [x, x])", "null"), "[null,null]")
check("spread in array literal", run_src("(x => [0, ...x, 9])", "[1,2]"), "[0,1,2,9]")
check("object literal spread", run_src('(x => {"a":1, ...x})', '{"b":2}'), '{"a":1,"b":2}')
check("nested function / closure capture",
      run_src("(n => (m => [n, m] | @add))", "10").startswith('"<function'), True)
check("currying: 10 | (n => (m => n+m)) then apply 5",
      run_src("(pair => pair[0] | (n => (m => [n,m] | @add)) | (g => pair[1] | g))", "[10,5]"), "15")

# explicit ! handling: a clause that matches ! catches it
check("explicit ! clause catches error", run_src("(! => 0, x => x)", "null"), "null")
check("explicit ! clause: feed an error via failed op then pipe into recover",
      run_src("(x => ([x,0] | @divide) | (! => 999, y => y))", "5"), "999")

passed = sum(tests); total = len(tests)
print(f"\n{passed}/{total} passed")
sys.exit(0 if passed == total else 1)
