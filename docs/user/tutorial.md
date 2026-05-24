# Tutorial: Your first hour with Fusion

*This is a **tutorial** in the [Diátaxis](https://diataxis.fr/) sense: a guided
lesson. Its goal is to build your skill and confidence by having you write and run
small programs, not to get a particular job done. Follow it start to finish, type
the code yourself, and run every example. By the end you will have written a
recursive program and understood how Fusion's pieces fit together.*

> **What you need:** Ruby installed, and the interpreter package (`fusion.rb` plus
> the `examples/` and `stdlib/` folders). All commands below are run from inside the
> interpreter directory.

---

## Step 1 — Run something

Fusion programs read JSON on standard input and write JSON on standard output. Let's
run the smallest possible program. Create a file `lesson.fsn` containing exactly:

```fusion
(n => [n, 2] | multiply)
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
- `[n, 2] | multiply` built a two-element array and piped it into the built-in
  `multiply`. Fusion has no `*` operator (yet); arithmetic is done by piping a pair
  into a named function.

Change the `2` to a `3` and run it again. You are now editing Fusion.

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

You get `[2, 1]`. The pattern `[a, b]` required a two-element array and bound its
elements to `a` and `b`; the result `[b, a]` put them back in swapped order. This
single idea — *bare words bind in patterns, read in results* — is the heart of the
whole language. Patterns and results are mirror images of each other.

Try feeding it a three-element array (`echo '[1,2,3]'`). You get `null`, because
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

- `{"name": n, ...}` matched an object that has a `name` key and bound its value.
- `_` is the **wildcard**: it matches anything but binds nothing. We required an
  `age` key to exist but didn't care about its value.

This is *destructuring*: the pattern describes the shape you expect, and matching
both checks the shape and extracts the parts in one step.

---

## Step 5 — Making decisions (there is no `if`)

Fusion has no `if` statement. You don't need one, because choosing between cases is
exactly what pattern matching does. To branch on a condition, compute the condition
as a boolean and match on `true`/`false`. Write an absolute-value function:

```fusion
(n =>
  [n, 0] | lessThan | (
    true  => [0, n] | subtract,
    false => n
  )
)
```

Run it on `-5` and on `5`:

```sh
echo '-5' | ruby fusion.rb lesson.fsn    # => 5
echo '5'  | ruby fusion.rb lesson.fsn    # => 5
```

Read the middle line carefully: `[n, 0] | lessThan` produces `true` or `false`, and
that boolean is piped into a *second, inline function* whose two clauses are the two
branches. **An `if` is just a function with a `true` clause and a `false` clause.**
Once you see this, you will see it everywhere.

---

## Step 6 — Repeating things (there is no loop, either)

There are no loops in Fusion. Repetition is done with recursion, and recursion is
done by pattern-matching on structure. The trick for a function to call *itself* is
the `@` reference: inside a file named `sum.fsn`, the reference `@sum` means "this
file." Create a new file `sum.fsn`:

```fusion
(
  [] => 0,
  [x, ...rest] => [x, rest | @sum] | add
)
```

```sh
echo '[1, 2, 3, 4]' | ruby fusion.rb sum.fsn    # => 10
```

Walk through what happened. The pattern `[x, ...rest]` matched a non-empty list,
binding the first element to `x` and *the remaining elements* to `rest` (that's what
`...` does — it captures "the rest"). The result added `x` to the sum of `rest`,
computed by piping `rest` back into the same function via `@sum`. Eventually `rest`
becomes `[]`, the first clause matches, the recursion bottoms out at `0`, and the
additions unwind. **That peeling-the-list-apart pattern is Fusion's `for` loop.**

---

## Step 7 — Refining a match with a predicate

Sometimes "this is an array of length two" isn't specific enough; you want "this is
an *integer*." Attach a predicate to any pattern with `?`. The clause matches only if
the structure matches *and* the predicate returns `true`. Make a factorial:

```fusion
(
  0 => 1,
  n ? Integer => [n, [n, 1] | subtract | @fact] | multiply
)
```

Save it as `fact.fsn` and run `echo '5' | ruby fusion.rb fact.fsn` → `120`.

`n ? Integer` reads as "bind `n`, but only if `n` is an integer." And here is the
beautiful part: `Integer` is not a keyword. It is just a built-in function that
returns `true` for integers. Fusion's "type system" is nothing more than ordinary
predicate functions you attach with `?`. You can write your own and use them exactly
the same way.

---

## Step 8 — Using the standard library

You don't have to write `sum` and friends from scratch; common helpers live in the
standard library and are reached with the `@std/` prefix. The classic `map` is there.
Create `doubler.fsn`:

```fusion
(xs => {"f": (n => [n, 2] | multiply), "xs": xs} | @std/map)
```

```sh
echo '[1, 2, 3]' | ruby fusion.rb doubler.fsn    # => [2, 4, 6]
```

Because every Fusion function takes exactly one argument, `map` takes an *object*
bundling the function `f` and the list `xs`. You just passed a function as a value
inside an object — functions are values like any other.

---

## What you have learned

In about an hour you have used every major feature of the language:

- A file is one value; a program is a function; `value | function` applies it.
- Functions are ordered `pattern => result` clauses; the first match wins; no match
  gives `null`.
- Bare words are holes: they bind in patterns and read in results.
- Destructuring matches and extracts nested array/object shape at once; `_` ignores,
  `...rest` captures the remainder.
- `if` is a function matching `true`/`false`; a loop is recursion via `@self`.
- `?` attaches a predicate to refine a match, and predicates double as types.
- The standard library is reached with `@std/...`.

You are ready to solve real problems. For that, turn to the
[**How-to guides**](./how-to-guides.md). To look up exact behavior, see the
[**Reference**](./reference.md). To understand *why* the language is shaped this way,
read the [**Explanation**](./explanation.md).
