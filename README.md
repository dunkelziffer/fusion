# Fusion — proof-of-concept interpreter

A reference implementation of the Fusion language (spec rev 4): JSON + pattern-
matching functions, one input / one output, `value | function` application, a file
is one value, `@refs` for modules/stdlib.

## Files

- `fusion.rb` — the interpreter (Ruby, single file). **This is the deliverable.**
- `test.rb` — Ruby test suite (38 cases) driving `fusion.rb` directly. Run with
  `ruby test.rb` from this directory.
- `oracle.py` — a faithful Python port of the same algorithm, used during authoring
  to verify the logic where Ruby could not be executed (see *Verification*).
- `test.py` — the same 38 cases against the Python oracle (`python3 test.py`); kept
  in lockstep with `test.rb`.
- `examples/` — sample `.fsn` programs.
- `stdlib/` — standard-library files written in Fusion (`@std/...`).

## Running

```sh
echo '5' | ruby fusion.rb examples/fact.fsn          # => 120
echo '[1,2,3]' | ruby fusion.rb examples/main.fsn    # => [2,4,6]
ruby fusion.rb examples/fact.fsn 5                    # input as an argument
ruby fusion.rb -e '(n => [n,2] | multiply)' 21          # inline program  => 42
```

Input is read from stdin (or the 2nd CLI arg) as JSON, parsed into a Fusion value,
piped through the file's function, and the result is printed as JSON. A final
result of `!` sets exit code 1.

## Decisions baked into this implementation

These were open questions in the spec; the implementation commits to:

- **Error propagation is automatic and uniform.** Any function applied to `!`
  returns `!`, *unless* it has a clause that explicitly matches `!` (`! => ...`).
  This is decoupled from strictness (a refinement found while implementing: tying
  propagation to a trailing `_ => !` failed, because `_` rejects `!`).
- **`_` and binders reject `!`.** Only a literal `!` pattern matches the error value.
- **Missing object key / out-of-range index / member access on a non-object → `!`.**
- **Built-in operations return `!` on bad input; predicates return `false`.**
- **`@refs` are lazy + memoized.** Self-recursion (`@fact` in `fact.fsn`) and
  cross-file mutual recursion (`@even`/`@odd`) work. A non-productive **data cycle**
  yields `!` at the exact point of cyclic self-reference, preserving surrounding
  productive structure (e.g. `cyclicA` => `[1,[2,!]]`).
- **`@std/x`** resolves to the bundled `stdlib/` dir; every other `@path` is relative
  to the referencing file.
- **Non-JSON stdin → `!`.** Empty stdin → `null`.
- **Numbers** keep Ruby int/float distinction; `divide` yields an int when evenly
  divisible, else a float.

## Verification

The Python oracle passes all 38 tests, covering: file-based recursion (`fact`,
`sum`), cross-file use (`main` → `@double` + `@std/map`), `fizzbuzz`, destructuring
(array/object rest, init+last), `?`-guards incl. relational guards on a parent
container, member/index access and their `!` cases, arithmetic `!` cases, deep
equality, spreads, closures/currying, and the full `!` propagation/catch matrix.

`fusion.rb` is a line-for-line translation of the verified oracle algorithm. It was
**not executed** here because the sandbox had no Ruby and no network to install it.
Run `ruby fusion.rb ...` locally to exercise it; behavior should match the oracle.

## Known not-yet-implemented

- No operator sugar (use `[a,b] | add` etc.) — deferred by design.
- No local `let`-binding form — recursive helpers need their own file (the spec's
  open "anonymous local recursion" tension).
- Tier-1 stdlib is only partially populated (`map`, `range`); `filter`, `reduce`,
  etc. are specified but not all written yet.
