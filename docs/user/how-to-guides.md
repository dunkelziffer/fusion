# How-to guides

*These are **how-to guides** in the [Diátaxis](https://diataxis.fr/) sense: each one
addresses a specific real-world task and assumes you already know the basics (if you
don't, start with the [Tutorial](./tutorial.md)). They are recipes, not lessons —
scan for the problem you have and copy the solution.*

---

## Run a program

Pipe JSON into the interpreter:

```sh
echo '[1,2,3]' | ruby lib/fusion.rb path/to/program.fsn
```

Pass the input as an argument instead of stdin:

```sh
ruby lib/fusion.rb path/to/program.fsn '[1,2,3]'
```

Run a one-off snippet without a file:

```sh
ruby lib/fusion.rb -e '(n => [n, 2] | multiply)' '21'
```

A program that produces the error value `!` exits with a nonzero status, so you can
use Fusion programs in shell pipelines and `&&` chains.

---

## Diagnose a program that returns `!` unexpectedly

A bare `!` usually means a file failed to load (missing file, or a parse error)
somewhere in the reference chain. Turn on diagnostics:

```sh
FUSION_DEBUG=1 ruby lib/fusion.rb program.fsn '...'
```

With `FUSION_DEBUG` set, the interpreter prints to stderr the exact path it failed to
find or the parse error it hit.

---

## Branch on a condition (emulate `if`)

Compute a boolean, then pipe it into a two-clause function:

```fusion
(n =>
  [n, 0] | lessThan | (
    true  => "negative",
    false => "non-negative"
  )
)
```

For a three-way branch, match a small tuple of booleans (priority is top-to-bottom):

```fusion
(n =>
  [ [n, 0] | lessThan,
    [n, 0] | equals ] | (
    [true, _]  => "negative",
    [_, true]  => "zero",
    _          => "positive"
  )
)
```

---

## Loop over a list (emulate `for`)

Recurse by peeling the head off with `[x, ...rest]` and bottoming out on `[]`. Sum:

```fusion
(
  [] => 0,
  [x, ...rest] => [x, rest | @sum] | add
)
```

Count elements (length):

```fusion
(
  [] => 0,
  [_, ...rest] => [1, rest | @count] | add
)
```

---

## Count from 0 to n (emulate a counting loop)

Build a range by recursion, then process it. This is `range.fsn` from the stdlib:

```fusion
(
  0 => [],
  n ? Integer => [...([n, 1] | subtract | @std/range), [n, 1] | subtract]
)
```

`echo '5' | ruby lib/fusion.rb stdlib/range.fsn` gives `[0,1,2,3,4]`. Pipe that into a
recursive list function to do work for each number.

---

## Match only values of a certain type

Attach a predicate with `?`. The built-in type predicates are `Integer`, `Float`,
`Number`, `String`, `Boolean`, `Array`, `Object`, `Null`.

```fusion
(
  s ? String  => [s, " (text)"]   | concat,
  n ? Integer => n | toString,
  _           => "unsupported"
)
```

---

## Match on a condition involving several captured values

A `?` predicate sees **only** the value its own pattern matched — it cannot see
sibling bindings. To compare two captured values, attach the predicate to the
**parent container** so it receives the whole thing:

```fusion
(
  [a, b] ? ([x, y] => [x, y] | lessThan) => "ascending",
  _                                       => "not ascending"
)
```

The outer pattern `[a, b]` is what you destructure for the result; the inline
predicate `([x, y] => [x, y] | lessThan)` independently re-destructures the same pair
to do the comparison.

---

## Write your own type / validation predicate

A predicate is just a function returning a boolean. Make it *total* (never `!`) by
ending with a `_ => false` catch-all, so it's safe to throw any value at it:

```fusion
// isPositive.fsn
(n ? Number => [n, 0] | greaterThan, _ => false)
```

Use it like any built-in predicate: `(n ? @isPositive => "ok", _ => "bad")`.

---

## Make a function strict (error instead of `null` on no match)

Add a final `_ => !` clause. Without it, an unmatched input silently becomes `null`;
with it, an unmatched input becomes the error value `!`:

```fusion
(
  0 => 1,
  n ? Integer => [n, [n, 1] | subtract | @fact] | multiply,
  _ => !                          // reject non-integers loudly
)
```

---

## Handle (catch) an error value

By default `!` propagates: any function given `!` returns `!`, *unless* it has a
clause that explicitly matches `!`. To recover, write that clause:

```fusion
(! => 0, x => x)        // turn any error into 0, pass everything else through
```

To guard a risky operation and substitute a default:

```fusion
(x => ([x, 0] | divide) | (! => -1, y => y))     // divide-by-zero becomes -1
```

---

## Do arithmetic and string work

There is no operator sugar; pipe a pair (or value) into a built-in.

```fusion
[a, b] | add            // a + b
[a, b] | subtract       // a - b
[a, b] | multiply       // a * b
[a, b] | divide         // a / b   (! if b is 0)
[a, b] | mod            // a % b
n | negate              // -n
[s1, s2] | concat       // string concatenation
s | chars               // "abc" -> ["a","b","c"]
[parts, sep] | join     // ["a","b"], "-"  ->  "a-b"
n | toString            // number -> string
s | parseNumber         // "42" -> 42   (! if not numeric)
```

---

## Read and rebuild objects

Pull known keys by destructuring; keep the rest with `...`:

```fusion
({"id": id, ...rest} => rest)            // drop the id field
```

Add or override a field with object spread in the result:

```fusion
(o => {"seen": true, ...o})              // ensure a "seen" field
```

Enumerate *unknown* keys (pattern matching can't do this) with the `keys` built-in:

```fusion
(o => o | keys)                          // {"a":1,"b":2} -> ["a","b"]
```

---

## Reuse code across files

Reference another file's value with `@`. Resolution is relative to the *referencing*
file's directory:

- `@helper` → `helper.fsn` in the same directory
- `@../shared/util` → `util.fsn` one directory up, in `shared/`
- `@std/map` → the bundled standard library

If a file evaluates to an object of functions, reach a member with a dot:

```fusion
(xs => {"f": @double, "xs": xs} | @lib.map)   // lib.fsn is {"map": (...), ...}
```

---

## Recurse without giving the function its own file

This is currently awkward — Fusion has no local binding form. Two options:

1. **Give the helper its own file** and reference it with `@`. This is the idiomatic
   choice today.
2. **Pass the function to itself** as part of the input, simulating a fixpoint. This
   works but is verbose and is not recommended for everyday code.

See the [Explanation](./explanation.md) and [Design doc](../lang/design-decisions.md) for why this
gap exists and what may fix it.
