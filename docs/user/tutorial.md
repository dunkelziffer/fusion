# Tutorial: Your first hour with Fusion

*This is a guided lesson: follow it start to finish, type the code yourself, and run
every example. By the end you will have written a recursive program and understood how
Fusion's pieces fit together.*

> **What you need:** Ruby installed, and the interpreter package (`fusion.rb` plus
> the `examples/` and `stdlib/` folders). All commands below are run from inside the
> interpreter directory.

---

## Step 1 — Run something

Fusion programs read JSON on standard input and write JSON on standard output. Let's
create our first program. Create a file `lesson.fsn` containing exactly:

```fusion
(n => [n, 2] | @multiply)
```

Now run it:

```sh
echo '21' | ruby fusion.rb lesson.fsn
```

You should see `42`. Take a moment to notice three things you just used without
being told:

- The whole file is **one value** — here, a function. There is no `main`, no list of
  statements. The file *is* the program.
- The input `21` was piped *into* the function. That is what `|` means: **`value |
  function`** applies the function to the value.
- `[n, 2] | @multiply` built a two-element array and piped it into the built-in
  `@multiply`. Fusion has no `*` operator (yet); arithmetic is done by piping a pair
  into a named function. **Built-ins are reached with an `@` prefix**, just like files
  — `@multiply`, `@add`, and so on. (You'll see why `@` is used for both in Step 8.)

Note: on the right side of `=>` you can use regular parentheses `()` to group
expressions and influence execution order.

You are now able to compute arithmetic expressions.

---

## Step 2 — A function is a list of patterns

A Fusion function is a comma-separated list of `pattern => result` clauses, wrapped
in parentheses. When you apply it, the clauses are tried top to bottom and the
**first one that matches** wins. Replace your file with:

```fusion
(
  0 => "zero",
  1 => "one",
  2 => "two"
)
```

Run `echo '1' | ruby fusion.rb lesson.fsn` and you get `"one"`. The pattern `1`
is a *literal* — it matches only the value `1`.

Now try an input no clause matches: `echo '5' | ruby fusion.rb lesson.fsn`. You get
`null`. **A function with no matching clause returns `null`.** Remember this; it is a
deliberate, important rule.

---

## Step 3 — Capturing values with holes

Literals are not very useful on their own. The power comes from *binding*. A bare
word in a pattern is a **hole**: it matches anything and captures it under that name.
The same bare word in the result **reads** that captured value back out. Try:

```fusion
([a, b] => [b, a])
```

```sh
echo '[1, 2]' | ruby fusion.rb lesson.fsn
```

You get `[2, 1]`. The pattern `[a, b]` matches a two-element array and binds its
elements to `a` and `b`; the result `[b, a]` constructs a new array and fills in
`a` and `b` in swapped order.

This single idea — *bare words bind in patterns, read in results* — is the heart of the
whole language. Patterns and results are mirror images of each other.

Try passing in a three-element array (`echo '[1, 2, 3]'`). You get `null`, because
`[a, b]` only matches arrays of length exactly two.

---

## Step 4 — Matching the *shape* of data

Patterns can dig into nested structure. Objects work just like arrays. Replace your
file with a function that pulls a name out of a person object:

```fusion
({"name": n, "age": _} => n)
```

```sh
echo '{"name": "Ada", "age": 36}' | ruby fusion.rb lesson.fsn
```

You get `"Ada"`. Two new things here:

- `{"name": n, ...}` matches an object that has a `name` key and binds its value.
- `_` is the **wildcard**: it matches anything but binds nothing. We required an
  `age` key to exist but didn't care about its value.

This is *destructuring*: the pattern describes the shape you expect. Pattern matching
both *checks the shape* AND *extracts values* in one step.

---

## Step 5 — Making decisions (there is no `if`)

Fusion has no `if` statement. You don't need one, because choosing between cases is
exactly what pattern matching does. To branch on a condition, compute the condition
as a boolean and match on `true`/`false`. Let's write a function that computes a
number's absolute value:

```fusion
(n =>
  [n, 0] | @lessThan | (
    true  => [0, n] | @subtract,
    false => n
  )
)
```

Run it on `-5` and on `5`:

```sh
echo '-5' | ruby fusion.rb lesson.fsn    # => 5
echo '5'  | ruby fusion.rb lesson.fsn    # => 5
```

Read the middle line carefully: `[n, 0] | @lessThan` produces `true` or `false`. That
boolean is then piped into a *second, inline function* whose two clauses are the two
branches. **An `if` is just a function with a `true` clause and a `false` clause.**

Note: you don't need to restrict yourself to the two values `true` and `false` as
an intermediate result. Don't use it purely as an `if / else`. Use it like a `case`
statement. You can have as many cases as you need.

---

## Step 6 — Repeating things (there is no loop, either)

There are no loops in Fusion. Repetition is done with recursion, and recursion is
done by pattern-matching on structure, usually on arrays.

To make recursion easier, `@` always means *the current file*. Create a new file
`sum.fsn`:

```fusion
(
  [] => 0,
  [x, ...rest] => [x, rest | @ ] | @add
)
```

```sh
echo '[1, 2, 3, 4]' | ruby fusion.rb sum.fsn    # => 10
```

Walk through what happened:
- As long as our input list is non-empty, the first pattern doesn't match.
- The pattern `[x, ...rest]` matches non-empty lists and binds the first element
  to `x` and *the remaining elements* to `rest` (that's what `...` does — it
  captures "the rest").
- The expression on the right side of `=>` then adds `x` to the "sum of `rest`".
- This "sum of `rest`" gets computed recursively by piping `rest` back into the
  same function via `@`.
- Eventually `rest` becomes `[]`, the first clause matches and the recursion bottoms
  out at `0`.
- Then, all the additions unwind.

This is how you emulate `for` loops via recursion in Fusion.

---

## Step 7 — Refining a match with a predicate

Sometimes pattern matching on the input's *structure* isn't enough. An integer and a
string are both atomic values. They have the same *structure*. You also can't express
conditions between bindings with structure alone.

To express such distinctions, you can attach a predicate to any pattern with `?`. The
clause will match only if the structure matches *and* the predicate returns `true`.
Let's compute the factorial:

```fusion
(
  0 => 1,
  n ? @Integer => [n, [n, 1] | @subtract | @] | @multiply
)
```

Save it as `fact.fsn` and run `echo '5' | ruby fusion.rb fact.fsn` → `120`.

`n ? @Integer` reads as "bind `n`, but only if `n` is an integer." And here is the
beautiful part: `@Integer` is not a keyword. It is just a built-in function that
returns `true` for integers. Fusion's "type system" is a dynamic runtime type system.
It is nothing more than ordinary functions you attach with `?`. You can write your own
and use them exactly the same way.

Create a function that sorts a pair of values:

```fusion
(
  [a, b] ? @lessThan => [a, b],
  [a, b] => [b, a]
)
```

The first case only matches, if the values are already in the correct order. It
simply returns the input unmodified. The second case matches without restrictions.
It swaps the two elements.

---

## Step 8 — Using the standard library (and the one `@` namespace)

You don't have to write `sum` and friends from scratch; common helpers live in the
standard library and are reached with a plain `@name` — the same `@map` you'd use for
a sibling file. The classic `map` is in the standard library. Create `doubler.fsn`:

```fusion
(xs => {"f": (n => [n, 2] | @multiply), "xs": xs} | @map)
```

```sh
echo '[1, 2, 3]' | ruby fusion.rb doubler.fsn    # => [2, 4, 6]
```

Because every Fusion function takes exactly one argument, `map` takes an *object*
bundling the function `f` and the list `xs`. You just passed a function as a value
nested within an object — functions are values like any other.

Now the payoff for using `@` everywhere. A bare `@name` is resolved in the following
order:
1. A **sibling file** `name.fsn` next to the current file.
2. A **built-in** called `name`.
3. A **standard-library** file `name.fsn`.

The first match wins. So `@multiply` finds the built-in and `@map` falls through to
the standard library. And if *you* put a `map.fsn` next to your program, *your* `map`
shadows the standard one — but only for files in that directory.

Built-ins and the standard library share the same `@` namespace as your own files
and you can locally override either, without ever affecting other directories.

---

## Step 9 — When things go wrong: errors with payloads

So far you have written programs that succeed. What happens when something goes
wrong? Try dividing by zero. Save as `boom.fsn`:

```fusion
(n => [n, 0] | @divide)
```

```sh
echo '5' | ruby fusion.rb boom.fsn
```

You will see no output on stdout, a message like `"divide: division by zero"` on
stderr, and the process will exit with status `1`. The result *was* an error, and
the interpreter knows the difference: it routes the error's **payload** to
stderr, leaves stdout empty, and signals failure. That makes Fusion programs
well-behaved Unix filters.

An error is always written as `!` followed by a **payload** — any regular JSON value.
The built-ins above produced `!"divide: division by zero"` (an error whose payload
is a string). You can construct your own:

| Example                             | Meaning                  |
| ----------------------------------- | ------------------------ |
| `!42`                               | Error with payload 42    |
| `!"could not parse"`                | Error carrying a message |
| `!{"kind": "bad_input", "got": 99}` | Structured error         |
| `!`                                 | Shorthand for `!null`    |

Errors **propagate** through pipelines automatically. If any step in
`a | f | g | h` produces an error, the rest is skipped and the error becomes the
final result — *unless* you write a clause that explicitly catches an error.
Catching is done with an error pattern:

```fusion
# Matches any error, returns "recovered"
(! => "recovered", x => x)
```

```fusion
# Binds the payload to "msg" for further processing
(!msg => msg, x => "ok")
```

Here's `safeDivide` that returns `null` instead of failing:

```fusion
(p => p | @divide | (! => null, n => n))
```

Run `echo '[10, 0]' | ruby fusion.rb safeDivide.fsn` and you get `null` rather than an
error. Notice how matching `!` is symmetric with constructing it: in expression
position, `!42` *builds* an error with payload 42; in pattern position, `!42`
*matches* an error with payload 42. The same syntax means "construct" on the right
of `=>` and "destructure" on the left, just like every other pattern in Fusion.

---

## What you have learned

In about an hour you have used every major feature of the language:

- A file is one value; a program is a function; `value | function` applies it.
- Functions are ordered `pattern => result` clauses; the first match wins; no match
  gives `null`; unmatched errors propagate.
- Bare words are holes: they bind in patterns and read in results.
- Destructuring matches and extracts nested array/object shape at once; `_` ignores,
  `...rest` captures the remainder.
- `if` is a function matching `true`/`false`; a loop is recursion via `@` (a bare
  `@` means "this file").
- `?` attaches a predicate to refine a match, and predicates double as types.
- Everything reachable lives in one `@` namespace: built-ins (`@add`, `@Integer`),
  the standard library (`@map`), sibling files (`@helper`), and the current file
  (`@`). A bare `@name` checks sibling → built-in → standard library, so you can
  locally shadow a built-in or stdlib function per directory.

You are ready to solve real problems with Fusion.
