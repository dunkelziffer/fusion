# How-to guides

*These are recipes for specific real-world tasks and assume you already know the
basics. Scan for the problem you have and copy the solution.*

---

## Diagnose a program that returns an error unexpectedly

When you run a program and see an error payload on stderr, the payload itself
tells you what went wrong. Interpreter errors carry a standardized object whose
fields (`kind`, `location`, `operation`, `input`, `message`) are documented in
[reference §6.5](./reference.md#65-the-standardized-error-payload).

For a missing file or a parse error in an `@`-referenced file, the `location` and
`input` fields name the exact path that failed. A common cause is that the
`stdlib/` folder is not where the interpreter expects it, so `@`-references can't
be resolved.

---

## Emulate control structures from other programming languages

1. Branch on a condition (emulate `if`)

Compute a boolean, then pipe it into a two-clause function:

```fusion
(n =>
  [n, 0] | @lessThan | (
    true  => "negative",
    false => "non-negative"
  )
)
```

You don't need to restrict yourself to 2 branches and the intermediate values `true` and `false`.
Here's an elegant way of writing FizzBuzz:

```fusion
(
  n =>
    [
      [n, 3] | @mod,
      [n, 5] | @mod,
    ]
      |
    (
      [0, 0] => "FizzBuzz",
      [0, _] => "Fizz",
      [_, 0] => "Buzz",
      _      => n,
    )
)
```

2. Loop over a list (emulate `for`)

Use recursion on lists with the base case `[]` and the recursive case `[x, ...rest]`.
You could write `sum` like this:

```fusion
(
  [] => 0,
  [x, ...rest] => [x, rest | @] | @add
)
```

If you don't have a list yet, but want to repeat something `n` times, use the
standard library function `range` to construct a list. `5 | @range` will evaluate
to `[0,1,2,3,4]`.

If you need further inputs in addition to your list, e.g. a function, use an object:
`{"function": f, "list": [1, 2, 3]}`.

3. Apply a function partially (only provide a subset of required inputs and emulate `currying`)

A Fusion function takes exactly one input. Functions that require multiple inputs bundle
them into an array (or object) and destructure that in the pattern:

```fusion
([a, b] => [a, b] | @add)
```

Call it as `[3, 4] | @thatFunction`

To curry a function call (that means to supply arguments one at a time) write a function that
takes a single argument (`x` in the example below) and returns a simpler function that only
needs the remaining arguments (`y` in the example below). Each `=>` consumes one argument
and hands back a function waiting for the next:

```fusion
(x => (y => [x, y] | @add))
```

Call it as `4 | (3 | @thatFunction)`. `3 | f` yields a one-argument function that adds 3,
and piping a second value into that finishes the sum.

With this, you can partially apply functions. Apply the first argument now and then use
the resulting function later.

---

## Match on a condition involving several captured values

A `?` predicate sees **only** the value its own pattern matched — it cannot see
sibling bindings. To compare two captured values, attach the predicate to the
**parent container** so it receives the whole thing.

For example, to recognise a three-element palindrome you have to compare the first
and last elements. A predicate guarding `first` on its own could never see `last`,
so guard the whole array instead:

```fusion
(
  []  => "palindrome",
  [_] => "palindrome",
  [_, ...rest, _] ? ([first, ..., last] => [first, last] | @equals) => rest | @,
  _   => "not a palindrome"
)
```

The outer pattern `[_, ...rest, _]` is what you destructure for retrieving the middle
of the array which you need to continue your recursion. The inline predicate
`([first, ..., last] => [first, last] | @equals)` independently destructures the same
array again to compare its two ends.

---

## Shadow a built-in or stdlib function locally

Because a sibling file wins over a built-in or the standard library, you can override
either — but only for files in the same directory, so you can't break things
globally. Put an `add.fsn` next to your program and every `@add` *in that directory*
uses yours; files elsewhere still get the built-in.

---

## Read environment variables

`@ENV` evaluates to an object of all environment variables (every value is a string;
nothing is auto-parsed). Read one with member access:

```fusion
# with CI=1 in the environment, yields the string "1"
(_ => @ENV.CI)
```

A missing variable (`@ENV.NOPE`) yields `!`. Note `@ENV` is itself shadowable: a
sibling `ENV.fsn` replaces it for that directory.

---

## Load a file by a runtime filename

`@map` and friends require the name at parse time and imply the `.fsn` extension.
When you need to load a file whose name is computed at runtime, or whose name isn't a
plain identifier (e.g. contains a `.`), use the `@load` built-in. It takes a filename
**verbatim** — no extension is added — resolved relative to the current file:

```fusion
# Load a file with exactly the given name. Don't append ".fsn".
("data.config.json" | @load)
```

```fusion
# Load a file chosen at runtime.
(name => name | @load)
```

A missing file yields an error.

---

## Keep a recursive file independent of its name and location

A recursive function should never call itself by its own filename. Writing `@fact`
inside `fact.fsn` works until someone renames or moves the file — then the reference
dangles. Refer to the current file with a bare `@` ("this file", whatever it happens
to be called) instead:

```fusion
# factorial
(0 => 1, n ? @Integer => [n, [n, 1] | @subtract | @] | @multiply)
```

If the file evaluates to an **object** and a recursive *helper* lives inside it as a
member, reach that member with `@.helper` — the current file's value (`@`) followed
by a `.member` access — rather than `@filename.helper`:

```fusion
{
  "sumTo": (
    0 => 0,
    n ? @Integer => [n, [n, 1] | @subtract | @.sumTo] | @add
  )
}
```

Both forms move and rename along with the file, so nothing dangles when you
reorganise your directory.
