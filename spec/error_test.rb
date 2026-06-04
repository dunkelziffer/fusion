#!/usr/bin/env ruby
# frozen_string_literal: true

# Tests for payloaded errors: !payload construction, !pat matching, propagation,
# and the ?-predicate-error bubbling rule.
#
# Run:  ruby spec/error_test.rb

require_relative "../lib/fusion"

HERE   = File.dirname(File.expand_path(__FILE__))
STDLIB = File.join(HERE, "../stdlib")
EX     = File.join(HERE, "fixtures")

def run(src, input_json)
  interp = Fusion::Interpreter.new(stdlib_dir: STDLIB)
  ast = Fusion::Parser.parse_file(src)
  env = interp.root_env.child
  env.define("__dir__", EX)
  fn = interp.eval_expr(ast, env)
  Fusion::CLI.serialize(interp.apply(fn, Fusion::CLI.parse(input_json)))
end

$results = []
def chk(desc, got, exp)
  ok = (got == exp)
  $results << ok
  puts "[#{ok ? 'ok  ' : 'FAIL'}] #{desc}"
  puts "        got: #{got}\n        exp: #{exp}" unless ok
end

# --- Construction: !expr produces a payloaded error ---
chk("!42 produces an error with payload 42",
    run('(_ => !42)', "null"), '!42')
chk('!"oops" produces error with string payload',
    run('(_ => !"oops")', "null"), '!"oops"')
chk("!null produces !null",
    run('(_ => !null)', "null"), '!null')
chk("bare ! is shorthand for !null",
    run('(_ => !)', "null"), '!null')
chk("![1,2,3] wraps an array as error payload",
    run('(_ => ![1,2,3])', "null"), '![1,2,3]')
chk('!{"code":"x"} wraps an object as error payload',
    run('(_ => !{"code":"x"})', "null"), '!{"code":"x"}')

# --- Payload uses a captured value ---
chk("!x in result uses the captured value as payload",
    run('(x => !x)', "42"), '!42')
chk("!x using a bound array",
    run('([a,b] => !{"left":a,"right":b})', "[1,2]"),
    '!{"left":1,"right":2}')

# --- Pattern matching on errors ---
chk("bare ! pattern matches any error",
    run('(! => "caught", x => "fine")', "null"),
    '"fine"')  # null is not an error
chk("bare ! pattern matches a real error too",
    run('(x => !x | (! => "caught", _ => "no"))', "42"),
    '"caught"')
chk("!_ pattern matches any error (different payload)",
    run('(x => !x | (!_ => "caught", _ => "no"))', '"oops"'),
    '"caught"')
chk("a function that produces an error, caught by bare !",
    run('(x => ([x,0] | @divide) | (! => "caught"))', "5"),
    '"caught"')
chk("!_ catches with no binding",
    run('(x => ([x,0] | @divide) | (!_ => "caught"))', "5"),
    '"caught"')
chk("!msg pattern binds the payload",
    run('(x => ([x,0] | @divide) | (!msg => msg))', "5"),
    '"divide: division by zero"')
chk("!42 only matches an error with payload 42",
    run('(x => !x | (!42 => "got 42", !other => "got something else"))', "42"),
    '"got 42"')
chk("!42 does NOT match a different payload",
    run('(x => !x | (!42 => "got 42", !other => "got something else"))', "99"),
    '"got something else"')
chk('!{"code":c} destructures an object payload',
    run('(_ => !{"code":"X","msg":"hi"} | (!{"code":c} => c))', "null"),
    '"X"')

# --- Propagation through pipelines preserves the payload ---
chk("an error propagates through any unrelated function (payload preserved)",
    run('(x => ([x,0] | @divide) | (n => [n, 1] | @add))', "5"),
    '!"divide: division by zero"')
chk("strict no-match gives !null (not the propagated input error)",
    run('(_ => null | (1 => "one", _ => !))', "null"),
    '!null')

# --- ?-predicate error bubbling ---
chk("predicate that errors makes the function return that error",
    run('(x ? (n => [n,0] | @divide) => "matched", _ => "fallback")', "5"),
    '!"divide: division by zero"')
chk("predicate-error does NOT advance to next clause",
    run('(x ? (n => [n,0] | @divide) => "matched", x => "next clause")', "5"),
    '!"divide: division by zero"')
chk("predicate returning false (no error) DOES advance",
    run('(x ? (_ => false) => "no", x => "yes")', "5"),
    '"yes"')

# --- Nested ! propagates inner error rather than wrapping it ---
chk("!(divide_by_zero) propagates the inner error, doesn't wrap as !!",
    run('(x => !([x,0] | @divide))', "5"),
    '!"divide: division by zero"')

# --- Errors are NOT first-class values: they always propagate ---
# Array literal containing an error short-circuits at the first error.
chk("array literal short-circuits on error element",
    run('(_ => [!42, !99])', "null"),
    '!42')
chk("object literal short-circuits on error value",
    run('(_ => {"a": !42, "b": 1})', "null"),
    '!42')
# @equals propagates an error input (you'd have to catch first to compare two errors).
chk("@equals propagates: a literal building [!42, !42] short-circuits to !42",
    run('(_ => [!42, !42] | @equals)', "null"),
    '!42')
# Type predicates propagate too -- to ask about a payload you must catch first.
chk("@Integer propagates on an error input",
    run('(_ => !42 | @Integer)', "null"),
    '!42')
chk("to inspect an error's payload you catch it first",
    run('(_ => !42 | (!a => a) | @Integer)', "null"),
    'true')

# --- !pat ? predicate feeds the PAYLOAD to the predicate, not the whole error ---
chk("!a ? @Integer: predicate sees payload, not error wrapper",
    run('(x => !x | (!a ? @Integer => ["int", a], _ => "other"))', "7"),
    '["int",7]')
chk("!a ? @Integer: predicate false -> error propagates (NOT swallowed to null)",
    # When the first clause's predicate is false and no later clause catches
    # the error, the original error propagates as the function's result. An
    # unmatched error is NEVER silently turned into null.
    run('(x => !x | (!a ? @Integer => ["int", a], _ => "other"))', '"hello"'),
    '!"hello"')
chk("!a ? @Integer: predicate false -> caught by a SECOND error pattern",
    run('(x => !x | (!a ? @Integer => ["int", a], !b => ["non-int", b]))', '"hello"'),
    '["non-int","hello"]')
chk("!_ ? @Integer (no binder): predicate sees payload",
    # To get a predicate without binding the payload, use `!_ ? pred`.
    # Bare `!` alone has no payload pattern, so it cannot carry a predicate
    # (syntactically: `! ? pred` is a parse error — see the syntax tests below).
    run('(x => !x | (!_ ? @Integer => "int-error", _ => "other"))', "7"),
    '"int-error"')
chk("!_ ? @Integer: payload non-int -> error propagates",
    # Confirms predicate sees the payload (not the error wrapper): "hi" is not
    # an integer, predicate is false, no other clause catches, so the original
    # error propagates.
    run('(x => !x | (!_ ? @Integer => "int-error", _ => "other"))', '"hi"'),
    '!"hi"')
chk("!42 ? @Integer: literal payload pattern + predicate redundancy",
    run('(x => !x | (!42 ? @Integer => "match", _ => "no"))', "42"),
    '"match"')

# --- Partial match: error of a different shape must keep propagating ---
chk("partial match: matched payload returns normal value",
    run('(_ => !42 | (!42 => "got 42", x => x))', "null"),
    '"got 42"')
chk("partial match: unmatched payload propagates the original error",
    # The first clause is !42; we feed !99. PWild rejects errors, so no clause
    # matches. Per the rule, the original error keeps propagating.
    run('(_ => !99 | (!42 => "got 42", x => x))', "null"),
    '!99')
chk("partial match across multiple error clauses",
    # First clause catches only !42; second catches only !99; we feed !"oops".
    # No clause matches => original error propagates.
    run('(_ => !"oops" | (!42 => "a", !99 => "b"))', "null"),
    '!"oops"')
chk("non-error input with no matching clause still returns null",
    # The "no match -> null" lenient default only applies to non-error inputs.
    run('(_ => 5 | (1 => "one", 2 => "two"))', "null"),
    'null')

# --- Nested !pat is a syntax error ---
def parse_should_fail(src, why)
  begin
    Fusion::Parser.parse_file(src)
  rescue Fusion::ParseError
    $results << true
    puts "[ok  ] syntax error rejected: #{why}"
    return
  end
  $results << false
  puts "[FAIL] expected syntax error, parsed cleanly: #{why}"
end

parse_should_fail('([!a, b] => a)',     "[!a, b] (error inside array pattern)")
parse_should_fail('({"e": !x} => x)',   '{"e": !x} (error inside object pattern)')
parse_should_fail('([..., !x] => x)',   "[..., !x] (error after rest in array)")
parse_should_fail('(!!42 => "x")',      "!!42 (nested error pattern)")
parse_should_fail('(!{"k": !v} => v)',  '!{"k": !v} (error nested in payload)')
parse_should_fail('(![!a] => a)',       "![!a] (error nested in payload array)")
parse_should_fail('(! ? @Integer => "x")',
                  "! ? pred (bare bang has no payload pattern for the predicate to refer to)")

# --- Sanity: legitimate error patterns still parse ---
chk("legitimate: !pat at top-level still works",
    run('(!a => a)', "null"),    # input is null, not an error -> no match -> null
    'null')
chk("legitimate: !pat with object payload destructure",
    run('(_ => !{"kind": "x", "msg": "hi"} | (!{"kind": k} => k))', "null"),
    '"x"')
chk("legitimate: !pat with array payload destructure",
    run('(_ => ![1,2,3] | (![a, b, c] => [c, b, a]))', "null"),
    '[3,2,1]')

passed = $results.count(true)
total  = $results.length
puts
puts "#{passed}/#{total} error-feature tests passed"
exit(passed == total ? 0 : 1)
