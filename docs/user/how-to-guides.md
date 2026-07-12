# How-to guides

*These are recipes for specific real-world tasks and assume you already know the
basics. Scan for the problem you have and copy the solution.*

---

## Diagnose a program that returns an error unexpectedly

When you run a program and see an error payload on stderr, the payload itself
tells you what went wrong. Interpreter errors carry a standardized object whose
fields (`kind`, `origin`, `file`, `operation`, `status`, `input`, `expected`,
`message`) are documented in
[reference §6.5](./reference.md#65-the-standardized-error-payload).

For a missing file or a parse error in an `@`-referenced file, the `file` and
`input` fields name the path that failed.

---

## Emulate control structures from other programming languages

1. Branch on a condition (emulate `if`)

Compute a boolean, then pipe it into a two-clause function:

```fusion
(n =>
  (n < 0) | (
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
      [n, 3] | @OP.modulo,
      [n, 5] | @OP.modulo,
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
  [x, ...rest] => [x, rest | @] | @OP.sum
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
([a, b] => [a, b] | @OP.sum)
```

Call it as `[3, 4] | @thatFunction`

To curry a function call (that means to supply arguments one at a time) write a function that
takes a single argument (`x` in the example below) and returns a simpler function that only
needs the remaining arguments (`y` in the example below). Each `=>` consumes one argument
and hands back a function waiting for the next:

```fusion
(x => (y => [x, y] | @OP.sum))
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
  [_, ...rest, _] ? ([first, ..., last] => [first, last] | @OP.equal) => rest | @,
  _   => "not a palindrome"
)
```

The outer pattern `[_, ...rest, _]` is what you destructure for retrieving the middle
of the array which you need to continue your recursion. The inline predicate
`([first, ..., last] => [first, last] | @OP.equal)` independently destructures the same
array again to compare its two ends.

---

## Short-circuit a chain of checks

`&&` and `||` are **eager**. `a && b` desugars to `[a, b] | @OP.and` — an array
piped into a function — so both operands are computed before the operator sees
them. The same goes for a hand-written conditions array `[a, b, c] | @OP.and`:
an array literal evaluates all of its elements, and if one of them is an error,
the error propagates out of the literal immediately. No piped form can keep its
input from being computed.

The one place where Fusion is lazy is a **clause body**: it evaluates only when
its clause's pattern matches. To run check B only if check A passed, put B in a
body that A's success selects. For boolean conditions:

```fusion
a | (true => b, _ => false)   # short-circuiting a && b
a | (true => true, _ => b)    # short-circuiting a || b
```

For example, `x | @Array | (true => x | @size > 0, _ => false)` safely tests
"a non-empty array": fed `5`, it yields `false` without ever piping the number
into `@size`.

In a guard, the same sequencing falls out of the stages pattern → predicate →
body, each of which runs only after the previous one succeeded. `@zip`
validates "a pair of equal-length arrays" like this:

```fusion
[xs, ys] ? ([a ? @Array, b ? @Array] => a | @size == b | @size)
```

The size comparison lives in the predicate's body, so it is computed only after
the pattern has established that both elements are arrays — `@size` can never
see a non-array. Sequencing matters because a predicate that *errors* does not
fall through to the next clause — the error propagates.

For a longer chain of checks you have two options. You can keep sequencing by
nesting another predicate between pattern and body — the checks stay lazy, and
a broken predicate still fails loudly. Or you can accept that every condition
is computed and route any error into "no match" by piping a conditions array
through `@OP.and | @safe`, one condition per line. `@matrix/sum` checks "an
array, non-empty, all matrices, all of equal dimensions" like this:

```fusion
matrices ? (ms => [
    ms | @Array,
    ms | @size > 0,
    {"c": ms, "f": @Matrix} | @all,
    ms |: @dimensions | @OP.equal,
  ] | @OP.and | @safe)
```

Fed `[5]`, the last condition errors (`@dimensions` of the number `5`), the
error collapses the conditions array — an array literal propagates an error
element, and `@OP.and` passes an error through untouched — and `@safe` turns
it into `false`: the clause simply doesn't match, and the input falls through
to the function's own error clause. Two things to keep in mind:

- `@safe` is just the two-clause function `(! => false, v => v)`, and it needs
  both clauses: the error clause alone would turn every *successful* condition
  into `null` — a value that matches no clause yields `null` — and the guard
  would go falsey for valid inputs too.
- Catching trades loudness for flatness. Errors-as-false means a genuinely
  broken condition (a typo'd reference, a wrong shape) reads as "the guard is
  false for every input" instead of crashing. Prefer sequenced clauses where
  the checks order themselves structurally anyway.

Eager conditions are fine when they are safe on the already-matched input.
After `[x ? @Matrix, row ? @Integer, col ? @Integer]` has matched, bounds
checks like `row >= 0 && row < x | @size` cannot error, and the flat `&&`
chain reads best — the structural pattern is what bought that safety.

(`@all` and `@any` do short-circuit, but at the level of applying their
predicate to already-computed items: the first falsey/truthy item stops the
testing. That protects against a predicate erroring on a later item, not
against computing the items themselves.)

---

## Shadow a built-in or stdlib function locally

Because a sibling file wins over a built-in or the standard library, you can override
either — but only for files in the same directory, so you can't break things
globally. Put a `map.fsn` next to your program and every `@map` *in that directory*
uses yours; files elsewhere still get the standard one.

---

## Reskin the operators (`@OP`) for a directory

The arithmetic, comparison, and boolean operators live in one built-in object,
`@OP` (`@OP.sum`, `@OP.compare`, `@OP.and`, …), and — like any `@`-name — it is
resolved per directory. To change what the operators mean for the files in one
directory (complex numbers, matrices, …), drop an `OP.fsn` there that overrides the
members you want, reaching the originals with `@@`:

```fusion
# OP.fsn — this directory's arithmetic
{ ...@@, "sum": (p => "my sum"), "product": (p => "my product") }
```

Only files in *that* directory are affected; everything else keeps the defaults. To
check whether a directory changed the operators, look for an `OP.fsn` — there is no
other way to change them.

The standard library ships one ready-made reskin: an `OP.fsn` containing just
`@matrix/OP` gives the directory matrix arithmetic — `a + b` elementwise, `a * b`
the matrix product, `a / b` multiplication by the inverse, `%`/`//` always an
error — built on the helpers `@matrix/multiply`, `@matrix/determinant`,
`@matrix/scale`, and `@matrix/rotate`.

### Making a named derived helper follow your override

Most stdlib helpers are deliberately **immune** to your override, so a reskin can't
break them by accident: `@truthy`/`@falsey` decide truthiness by pattern matching,
and `@compact` drops nulls by pattern matching too. The comparison readers
`@OP.lt`/`@OP.gt`/`@OP.lte`/`@OP.gte` interpret an `@OP.compare` *result*, and both
steps of `a < b` (= `[a, b] | @OP.compare | @OP.lt`) resolve through `@OP` — so
overriding `compare` alone already reskins the comparisons, and an `OP.fsn` that
spreads `...@@` keeps the original readers.

One helper still calls `@OP` internally — `@range` uses `@OP.sum` and `@OP.compare` —
and, like `@`-names everywhere, it resolves `@OP` in *its own* directory (the stdlib),
so it keeps the default even where you overrode `@OP`. To make it follow your override,
copy the stdlib file to the directory containing your other overrides. It then
resolves `@OP` locally:

```sh
# CAUTION: `fusion --stdlib-path` not implemented yet, determine manually

# copy — portable, a frozen snapshot
cp "$(fusion --stdlib-path)/range.fsn" .
```

Your copy of `range.fsn` now resolves `@OP` in its own directory first and will find
your overrides before the original builtin implementations.

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
(0 => 1, n ? @Integer => [n, [n, -1] | @OP.sum | @] | @OP.product)
```

If the file evaluates to an **object** and a recursive *helper* lives inside it as a
member, reach that member with `@.helper` — the current file's value (`@`) followed
by a `.member` access — rather than `@filename.helper`:

```fusion
{
  "sumTo": (
    0 => 0,
    n ? @Integer => [n, [n, -1] | @OP.sum | @.sumTo] | @OP.sum
  )
}
```

Both forms move and rename along with the file, so nothing dangles when you
reorganise your directory.
