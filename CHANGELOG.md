# Changelog

This project adheres to [Break Versioning](https://www.taoensso.com/break-versioning).

## [Unreleased]

### Breaking

- The stdlib functions `@lt`, `@lte`, `@gt`, `@gte` have been turned into builtins
  and moved into the `@OP` object. Migration:
  - `@lt` -> `@OP.lt`
  - `@lte` -> `@OP.lte`
  - `@gt` -> `@OP.gt`
  - `@gte` -> `@OP.gte`
  Their errors now report `"origin": "builtin"`.
- The builtin `@toObject` has been moved to the stdlib. Its regular behavior stayed
  the same, but its errors now report `"origin": "stdlib"`.
- The `expected` strings of many error payloads have been improved. Consumers that
  matched the exact `expected` text need to update.
- The stdlib function `@concat` has been extended to be n-ary. Consumers that relied
  on an error if the number of given strings wasn't equal to 2 need to update.

### Non-breaking

- New syntax sugar has been introduced:
  - `a < b` is `[a, b] | @OP.compare | @OP.lt`
  - `a <= b` is `[a, b] | @OP.compare | @OP.lte`
  - `a > b` is `[a, b] | @OP.compare | @OP.gt`
  - `a >= b` is `[a, b] | @OP.compare | @OP.gte`
- New builtin predicates:
  - `@Collection`: true for arrays and objects.
- New stdlib functions:
  - `@entries`: an object's `[key, value]` pairs, the inverse of `@toObject`.
  - `@zip`: turns a pair of equal-length arrays into an array of `[left, right]` pairs.
  - `@safe`: the error catcher `(! => false, v => v)`
- New stdlib modules:
  - `matrix/` (including the matrix operator set `@matrix/OP`)
  - `vector/`

## [0.0.1] - 2026-07-04

Release the first non-alpha version of Fusion.
