# How-to guides

*These are **how-to guides** in the [Diátaxis](https://diataxis.fr/) sense: each one
addresses a specific real-world task and assumes you already know the basics (if you
don't, start with the [Tutorial](./tutorial.md)). They are recipes, not lessons —
scan for the problem you have and copy the solution.*

---

## Run a program

Pipe JSON into the interpreter:

```sh
echo '[1,2,3]' | ruby fusion.rb path/to/program.fsn
```

Pass the input as an argument instead of stdin:

```sh
ruby fusion.rb path/to/program.fsn '[1,2,3]'
```

Run a one-off snippet without a file:

```sh
ruby fusion.rb -e '(n => [n, 2] | @multiply)' '21'
```

A program that produces the error value `!` exits with a nonzero status, so you can
use Fusion programs in shell pipelines and `&&` chains.

---

## Diagnose a program that returns `!` unexpectedly

A bare `!` usually means a file failed to load (missing file, or a parse error)
somewhere in the reference chain. Turn on diagnostics:

```sh
FUSION_DEBUG=1 ruby fusion.rb program.fsn '...'
```

With `FUSION_DEBUG` set, the interpreter prints to stderr the exact path it failed to
find or the parse error it hit. The most common cause is that `examples/` and
`stdlib/` are not sitting next to `fusion.rb`, so `@`-references can't be resolved.

---

## Branch on a condition (emulate `if`)

Compute a boolean, then pipe it into a two-clause function:

```fusion
(n =>
  [n, 0] | @lessThan | (
    true  => "negative",
    false => "non-negative"
  )
)
```

For a three-way branch, match a small tuple of booleans (priority is top-to-bottom):

```fusion
(n =>
  [ [n, 0] | @lessThan,
    [n, 0] | @equals ] | (
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
  [x, ...rest] => [x, rest | @sum] | @add
)
```

Count elements (length):

```fusion
(
  [] => 0,
  [_, ...rest] => [1, rest | @count] | @add
)
```

---

## Count from 0 to n (emulate a counting loop)

Build a range by recursion, then process it. This is `range.fsn` from the stdlib:

```fusion
(
  0 => [],
  n ? @Integer => [...([n, 1] | @subtract | @range), [n, 1] | @subtract]
)
```

`echo '5' | ruby fusion.rb stdlib/range.fsn` gives `[0,1,2,3,4]`. Pipe that into a
recursive list function to do work for each number.

---

## Match only values of a certain type

Attach a predicate with `?`. The built-in type predicates are `Integer`, `Float`,
`Number`, `String`, `Boolean`, `Array`, `Object`, `Null`.

```fusion
(
  s ? @String  => [s, " (text)"]   | @concat,
  n ? @Integer => n | @toString,
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
  [a, b] ? ([x, y] => [x, y] | @lessThan) => "ascending",
  _                                       => "not ascending"
)
```

The outer pattern `[a, b]` is what you destructure for the result; the inline
predicate `([x, y] => [x, y] | @lessThan)` independently re-destructures the same pair
to do the comparison.

---

## Write your own type / validation predicate

A predicate is just a function returning a boolean. Make it *total* (never `!`) by
ending with a `_ => false` catch-all, so it's safe to throw any value at it:

```fusion
// isPositive.fsn
(n ? @Number => [n, 0] | @greaterThan, _ => false)
```

Use it like any built-in predicate: `(n ? @isPositive => "ok", _ => "bad")`.

---

## Make a function strict (error instead of `null` on no match)

Add a final `_ => !` clause. Without it, an unmatched input silently becomes `null`;
with it, an unmatched input becomes the error value `!`:

```fusion
(
  0 => 1,
  n ? @Integer => [n, [n, 1] | @subtract | @fact] | @multiply,
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
(x => ([x, 0] | @divide) | (! => -1, y => y))     // divide-by-zero becomes -1
```

---

## Do arithmetic and string work

There is no operator sugar; pipe a pair (or value) into a built-in.

```fusion
[a, b] | @add            // a + b
[a, b] | @subtract       // a - b
[a, b] | @multiply       // a * b
[a, b] | @divide         // a / b   (! if b is 0)
[a, b] | @mod            // a % b
n | @negate              // -n
[s1, s2] | @concat       // string concatenation
s | @chars               // "abc" -> ["a","b","c"]
[parts, sep] | @join     // ["a","b"], "-"  ->  "a-b"
n | @toString            // number -> string
s | @parseNumber         // "42" -> 42   (! if not numeric)
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
(o => o | @keys)                          // {"a":1,"b":2} -> ["a","b"]
```

---

## Reuse code across files

Reference another value with `@`. A bare `@name` (no slash, no `../`) is resolved in
order — **sibling file → built-in → standard-library file** — and the first match
wins:

- `@helper` → `helper.fsn` in the same directory (a sibling)
- `@add`, `@Integer` → a built-in (when no sibling `add.fsn`/`Integer.fsn` exists)
- `@map` → the standard library (when no sibling and no built-in `map`)

Paths are also allowed:

- `@dir/util` → `dir/util.fsn` in a **subdirectory**. Downward paths are still
  eligible for the built-in/standard-library fallback, so `@math/sqrt` can resolve to
  a stdlib `math/sqrt.fsn`.
- `@../shared/util` → `util.fsn` one directory up. **Upward paths (`../`) are
  file-only** — they never fall back to a built-in or the standard library.

A bare `@` (nothing after it) means **the current file** — this is how a function
refers to itself for recursion.

If a file evaluates to an object of functions, reach a member with a dot:

```fusion
(xs => {"f": @double, "xs": xs} | @lib.map)   // lib.fsn is {"map": (...), ...}
```

### Shadow a built-in or stdlib function locally

Because a sibling file wins over a built-in or the standard library, you can override
either — but only for files in the same directory, so you can't break things
globally. Put an `add.fsn` next to your program and every `@add` *in that directory*
uses yours; files elsewhere still get the built-in.

### Read environment variables

`@ENV` evaluates to an object of all environment variables (every value is a string;
nothing is auto-parsed). Read one with member access:

```fusion
(_ => @ENV.CI)        // with CI=1 in the environment, yields the string "1"
```

A missing variable (`@ENV.NOPE`) yields `!`. Note `@ENV` is itself shadowable: a
sibling `ENV.fsn` replaces it for that directory.

### Load a file by a runtime filename

`@map` and friends require the name at parse time and imply the `.fsn` extension.
When you need to load a file whose name is computed at runtime, or whose name isn't a
plain identifier (e.g. contains a `.`), use the `@load` built-in. It takes a filename
**verbatim** — no extension is added — resolved relative to the current file:

```fusion
("data.config.fsn" | @load)      // loads exactly that file, returns its value
(name => name | @load)           // load a file chosen at runtime
```

A missing file yields `!`. Like any built-in, `@load` is shadowable by a sibling
`load.fsn`.

---

## Recurse without giving the function its own file

A file's function refers to *itself* with a bare `@` (which means "this file"), so
single-file recursion is easy — that is how `sum` and `fact` above call themselves. A
recursive *helper* that is not the file's top-level value is still awkward, because
Fusion has no local binding form. Two options:

1. **Give the helper its own file** and reference it with `@name`. This is the
   idiomatic choice today.
2. **Pass the function to itself** as part of the input, simulating a fixpoint. This
   works but is verbose and is not recommended for everyday code.

See the [Explanation](./explanation.md) and [Design doc](./design.md) for why this
gap exists and what may fix it.
