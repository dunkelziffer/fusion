#!/usr/bin/env ruby
# frozen_string_literal: true

# Test suite for the Fusion interpreter.
# Loads fusion.rb as a library (its CLI block is guarded by $PROGRAM_NAME == __FILE__,
# so requiring it does not run the CLI).
#
# Run:  ruby test.rb

require_relative "fusion"

HERE   = File.dirname(File.expand_path(__FILE__))
STDLIB = File.join(HERE, "stdlib")
EX     = File.join(HERE, "examples")

# Run an example file from examples/ against a JSON input string.
def run_file(relpath, input_json)
  interp = Fusion::Interpreter.new(stdlib_dir: STDLIB)
  fn = interp.load_file(File.join(EX, relpath)).force
  val = Fusion::JsonInput.parse(input_json)
  res = interp.apply(fn, val)
  Fusion::Serializer.to_json(res)
end

# Run inline source against a JSON input string. __dir__ is set to EX so that
# any @refs in the snippet resolve like an examples/ file would.
def run_src(src, input_json)
  interp = Fusion::Interpreter.new(stdlib_dir: STDLIB)
  ast = Fusion::Parser.parse_file(src)
  env = interp.root_env.child
  env.define("__dir__", EX)
  fn = interp.eval_expr(ast, env)
  res = interp.apply(fn, Fusion::JsonInput.parse(input_json))
  Fusion::Serializer.to_json(res)
end

$results = []

def check(desc, got, expected)
  ok = (got == expected)
  $results << ok
  mark = ok ? "ok  " : "FAIL"
  puts "[#{mark}] #{desc}"
  unless ok
    puts "        got:      #{got}"
    puts "        expected: #{expected}"
  end
end

# For checks where the payload contains an environment-dependent value (like an
# absolute file path), assert that `got` contains every required substring.
def check_contains(desc, got, *needles)
  ok = needles.all? { |n| got.include?(n) }
  $results << ok
  mark = ok ? "ok  " : "FAIL"
  puts "[#{mark}] #{desc}"
  unless ok
    puts "        got:      #{got}"
    puts "        needles:  #{needles.inspect}"
  end
end

# --- File-based examples ---
check("double 21 -> 42", run_file("double.fsn", "21"), "42")
check("swap [1,2] -> [2,1]", run_file("swap.fsn", "[1,2]"), "[2,1]")
check("fact 5 -> 120 (self-recursion via @fact)", run_file("fact.fsn", "5"), "120")
check("fact 0 -> 1", run_file("fact.fsn", "0"), "1")
check("fact \"x\" -> ! (strict, non-integer)", run_file("fact.fsn", '"x"'), '!null')
check("sum [1,2,3,4] -> 10 (self-recursion via @sum)", run_file("sum.fsn", "[1,2,3,4]"), "10")
check("sum [] -> 0", run_file("sum.fsn", "[]"), "0")
check("main [1,2,3] -> [2,4,6] (uses @double + @map)", run_file("main.fsn", "[1,2,3]"), "[2,4,6]")
check("fizzbuzz 15 -> FizzBuzz", run_file("fizzbuzz.fsn", "15"), '"FizzBuzz"')
check("fizzbuzz 9 -> Fizz", run_file("fizzbuzz.fsn", "9"), '"Fizz"')
check("fizzbuzz 10 -> Buzz", run_file("fizzbuzz.fsn", "10"), '"Buzz"')
check("fizzbuzz 7 -> 7", run_file("fizzbuzz.fsn", "7"), "7")
check("safeDivide [10,2] -> 5", run_file("safeDivide.fsn", "[10,2]"), "5")
check("safeDivide [10,0] -> !", run_file("safeDivide.fsn", "[10,0]"), '!null')

# --- Inline source tests for core semantics ---
check("lenient no-match -> null", run_src("(1 => 2)", "99"), "null")
check("strict no-match -> !", run_src("(1 => 2, _ => !)", "99"), '!null')
check("wildcard matches ordinary value -> 1", run_src("(_ => 1)", "null"), "1")
check("object destructure + rest",
      run_src('({"a": x, ...rest} => [x, rest])', '{"a":1,"b":2,"c":3}'),
      '[1,{"b":2,"c":3}]')
check("array init+last via rest",
      run_src("([...init, last] => [init, last])", "[1,2,3,4]"),
      "[[1,2,3],4]")
check("guard ? @Integer matches",
      run_src('(n ? @Integer => "int", _ => "other")', "5"), '"int"')
check("guard ? @Integer rejects string",
      run_src('(n ? @Integer => "int", _ => "other")', '"hi"'), '"other"')
check("relational guard on parent container (a<b)",
      run_src('([a,b] ? ([x,y] => [x,y] | @lessThan) => "asc", _ => "not")', "[1,2]"), '"asc"')
check("relational guard rejects (a>=b)",
      run_src('([a,b] ? ([x,y] => [x,y] | @lessThan) => "asc", _ => "not")', "[2,1]"), '"not"')
check("member access present", run_src("(o => o.name)", '{"name":"bob"}'), '"bob"')
check("member access missing -> !", run_src("(o => o.nope)", '{"name":"bob"}'), '!{"kind":"missing_key","key":"nope"}')
check("index access", run_src("(a => a[1])", "[10,20,30]"), "20")
check("negative index", run_src("(a => a[-1])", "[10,20,30]"), "30")
check("index out of range -> !", run_src("(a => a[9])", "[10,20,30]"), '!{"kind":"index_out_of_range","index":9,"length":3}')
check("divide by zero -> !", run_src("(p => p | @divide)", "[1,0]"), '!"divide: division by zero"')
check("type error in add -> !", run_src("(p => p | @add)", '["a","b"]'), '!"add: expected a pair of numbers"')
check("deep equality structural", run_src("(p => p | @equals)", "[[1,[2]],[1,[2]]]"), "true")
check("null is ordinary data (matches binder)", run_src("(x => [x, x])", "null"), "[null,null]")
check("spread in array literal", run_src("(x => [0, ...x, 9])", "[1,2]"), "[0,1,2,9]")
check("object literal spread", run_src('(x => {"a":1, ...x})', '{"b":2}'), '{"a":1,"b":2}')
check("nested function / closure capture",
      run_src("(n => (m => [n, m] | @add))", "10").start_with?('"<function'), true)
check("currying: 10 | (n => (m => n+m)) then apply 5",
      run_src("(pair => pair[0] | (n => (m => [n,m] | @add)) | (g => pair[1] | g))", "[10,5]"), "15")

# explicit ! handling: a clause that matches ! catches it
check("explicit ! clause catches error", run_src("(! => 0, x => x)", "null"), "null")
check("explicit ! clause: feed an error via failed op then pipe into recover",
      run_src("(x => ([x,0] | @divide) | (! => 999, y => y))", "5"), "999")

# --- New @-resolution features ---
NF = File.join(EX, "newfeat")

def run_nf(relpath, input_json, env_vars = nil)
  interp = Fusion::Interpreter.new(stdlib_dir: STDLIB, env_vars: env_vars)
  fn = interp.load_file(File.join(NF, relpath)).force
  Fusion::Serializer.to_json(interp.apply(fn, Fusion::JsonInput.parse(input_json)))
end

check("sibling add.fsn shadows builtin @add", run_nf("usesAdd.fsn", "null"), '"shadowed-add"')
check("no sibling -> @add is builtin", run_nf("sub/usesBuiltinAdd.fsn", "null"), "5")
check("bare @ self-recursion countdown", run_nf("countdown.fsn", "3"), "[3,2,1,0]")
check("@ENV.CI -> string", run_nf("readenv.fsn", "null", {"CI" => "1"}), '"1"')
check("@ENV.CI missing -> !", run_nf("readenv.fsn", "null", {}), '!{"kind":"missing_key","key":"CI"}')
check("@load 'data.config.fsn' verbatim", run_nf("loader.fsn", '"data.config.fsn"'), '{"setting":"on"}')
check_contains("@load missing file -> !", run_nf("loader.fsn", '"nope.fsn"'),
               '"kind":"file_not_found"', 'nope.fsn')
check("@../helper from subdir", run_nf("sub/usesParent.fsn", "7"), "[7,7]")

# ENV / load are shadowable by siblings, like any builtin.
check("sibling ENV.fsn shadows @ENV",
      run_nf("shadowenv/usesEnv.fsn", "null", {"CI" => "1"}), '"shadowed-env"')
check("no sibling -> @ENV is real env",
      run_nf("readenv.fsn", "null", {"CI" => "1"}), '"1"')
check("sibling load.fsn shadows @load",
      run_nf("shadowload/usesLoad.fsn", "null"), '"shadowed-load"')

# Downward paths "dir/a" ARE eligible for stdlib/builtin fallback; only "../" is not.
check("@math/square falls through to stdlib subdir",
      run_nf("usesStdSub.fsn", "6"), "36")
check("sibling subdir shadows stdlib subdir method",
      run_nf("usesLocalSub.fsn", "6"), '"local-square"')
check_contains("@../subtract is file-only (no builtin fallback) -> !",
               run_nf("sub/usesDotDotBuiltin.fsn", "null"),
               '"kind":"file_not_found"', 'subtract.fsn')

passed = $results.count(true)
total  = $results.length
puts
puts "#{passed}/#{total} passed"
exit(passed == total ? 0 : 1)
