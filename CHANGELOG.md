# Changelog

This project adheres to [Break Versioning](https://www.taoensso.com/break-versioning).

## [Unreleased]

### Breaking

- The stdlib comparison readers `@lt`, `@lte`, `@gt`, `@gte` are gone; they live
  in `@OP` now, as `@OP.lt`, `@OP.lte`, `@OP.gt`, `@OP.gte`. Migrate
  `… | @OP.compare | @lt` to `… | @OP.compare | @OP.lt`; an `@OP` reskin covers
  the ordering and its readers together.
- `@toObject` is a stdlib function instead of a builtin. Same behavior, but its
  errors report `"origin": "stdlib"` and a reworded `expected`.
- The `expected` strings of several error payloads are reworded: they name the
  new `@Collection` predicate and mirror the validating guard verbatim. Affected:
  `@size`, `@all`, `@any`, `@compact`, `@concat`, `@filter`, `@map`, `@range`,
  `@toObject`. Consumers that match payload text must update.

### Non-breaking

- New comparison operators `<`, `<=`, `>`, `>=`: sugar for
  `[a, b] | @OP.compare | @OP.lt` (and so on), so a local `@OP` reskins them.
  They are binary and non-chaining, like `??`, and a `null` from a partial
  order's compare passes through instead of being forced to a boolean.
- New builtin predicate `@Collection`: true for arrays and objects.
- New stdlib functions:
  - `@entries`: an object's `[key, value]` pairs — the inverse of `@toObject`.
  - `@zip`: a pair of equal-length arrays into an array of `[left, right]` pairs.
  - `@safe`: the error catcher `(! => false, v => v)` — the one stdlib function
    with an error clause. Append `| @safe` to a chain of guard conditions to
    read an erroring check as "no match" instead of propagating it.
- New stdlib matrix module: `@matrix/OP` reskins the operators for matrices
  (`+`/`-` elementwise, `*` the matrix product, `/` the inverse, `%` and `//`
  always raise), built on `@matrix/multiply`, `@matrix/determinant`,
  `@matrix/invert`, `@matrix/minor`, `@matrix/transpose`, `@matrix/identity`,
  `@matrix/column`, `@matrix/row`, `@matrix/add`, `@matrix/subtract`,
  `@matrix/sum`, `@matrix/product`, `@matrix/negate`, `@matrix/scale`,
  `@matrix/rotate`, the `@matrix/Matrix` predicate, and `@matrix/dimensions`
  (`{"rows": _, "columns": _}`).
- New stdlib vector module, the foundation of the matrix module: `@vector/dot`,
  `@vector/cross`, `@vector/add`, `@vector/subtract`, `@vector/scale`,
  `@vector/norm`, and the `@vector/Vector` predicate (a non-empty array of
  numbers; a matrix is a non-empty array of equally sized vectors).
- `@concat` is n-ary: it concatenates any array of strings, not just a pair.
- New examples: `gcd.fsn`, and `examples/matrix/` — a directory whose `OP.fsn`
  points at `@matrix/OP`, with `average` and `solve` as one-line linear-algebra
  programs. `double.fsn` and `factorial.fsn` are reworked to showcase
  destructuring and the positive-guard style.
- New how-to guide "Short-circuit a chain of checks": `&&`/`||` and condition
  arrays evaluate eagerly, clause bodies are the lazy place, and a flat
  conditions array piped through `@OP.and | @safe` turns erroring checks into
  "no match".
- Documentation refreshed to the current state: the reference covers the
  comparison operators and `@safe`'s place in the error model, the how-to
  guides cover the matrix reskin, and the documented `@load` error kinds match
  reality.
- Development: RuboCop, SimpleCov, and mutation testing (mutant) run in CI.

## [0.0.1] - 2026-07-04

Release the first non-alpha version of Fusion.
