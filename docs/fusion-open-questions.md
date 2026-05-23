# Fusion — open design decisions & questions log

Running record of decisions made, defaults chosen, and questions deferred.
Companion to `fusion-grammar.md` (rev 3).

---

## A. Decisions already made (locked for now)

- **Three ingredients** beyond atoms: arrays, objects, functions. JSON syntax.
- **Functions**: one input, one output; ordered clauses `(p => o, ...)`; first match
  wins; bare identifiers are holes (bind in patterns, read in expressions).
- **Application**: `value | function`, left-associative.
- **Refinement via `?`**: `pattern ? predicate`; predicate is any function; clause
  matches iff structural match AND `matched_subtree | predicate == true`.
- **Types = predicates**: `Integer`, `String`, ... are just built-in predicate fns.
- **No operator sugar** (deferred): use built-ins like `[a,b] | add`.
- **Error value `!`**, distinct from `null`:
  - `null` = legitimate absence; `!` = something went wrong.
  - Strictness is a clause: end with `_ => !` (strict) or omit (lenient → `null`).
  - Total predicates end with `_ => false`.
  - Strict ⇔ error-propagating (emergent, no special pipe rule).
  - `!` matches ONLY the literal `!` pattern (not `_`, not a binder).
  - Built-in **operations** return `!` on bad input; **predicates** return `false`.
- **No sibling scope in patterns**: bindings produced simultaneously; a `?` predicate
  sees only its own matched subtree. Relational guards go on a parent container.

---

## B. Program structure (REVISED — one value per file)

- **A file contains exactly one value** (function, array, object, or atom) and
  nothing else. No statement list, no top-level bindings, no `letrec`.
- A file is **executable** iff its value is a function. Runtime computes
  `STDIN | thatFunction` and serializes the result; `!` → nonzero exit code.
- The old "trailing expression + mutually-recursive bindings" model is DROPPED.
  The `letrec` concession is no longer needed (there is only one value).

### File references = module system = stdlib delivery
- **`@a` evaluates to the value in `a.fsn`**, relative to the *referencing
  file's* directory. `@../a` parent, `@dir/a` subdir. New primary expr in grammar.
- **Lazy** resolution (on use, not at load) → self-recursion (`@fact` in
  `fact.fsn`) and mutual recursion (`@even`↔`@odd`) work; unused refs never load.
- **Memoized** per path → diamond deps load once.
- **Self-reference IS recursion**: a file refers to itself by its own `@name`.

### Open sub-questions (new, important)
- **Anonymous local recursion is now awkward.** One value per file + no inner
  bindings ⇒ a recursive helper must either be its own file, or use a fixpoint
  combinator `@fix` (possible but unergonomic), or wait for an eventual `let`-form.
  REAL TENSION — leave open.
- **Stdlib resolution**: pure-relative only (honest but long paths) vs one magic
  root like `@std/map` (small legible magic)? Leaning: one `@std/...` root +
  pure-relative for everything else.
- **Data cycles** (`a`=`[1,@b]`, `b`=`[2,@a]`): allow as infinite/lazy data, or
  detect non-productive cycle → `!`? Leaning: detect → `!`. (Function cycles fine.)
- **Sandboxing**: `@../../../etc/x` escapes the project. Runtime should confine
  resolution to a project root / allow-list. (Runtime concern, not language.)
- Non-JSON stdin → `!` (TBD). NDJSON/streaming deferred.
- Must an executable's function be total over its input, or is `null`/`!` on
  unmatched stdin acceptable? (Leaning: acceptable; that's what strictness controls.)

---

## C. Standard library (proposed this round)

**Tier 0 — true primitives (cannot be written in Fusion):**
- Arithmetic on pairs: `add subtract multiply divide mod negate floor`
- Comparison: `equals` (deep), `lessThan`  (others derive from these)
- Boolean: `and or not`
- Predicates: `Integer Float Number String Boolean Array Object Null`
- Atom/structure bridges: `length`, `concat` (strings), `chars` (str→array),
  `join` (array+sep→str), `toString`, `parseNumber`
- **`keys`** (object → array of key strings) — REQUIRED primitive: pattern matching
  can pull *known* keys but cannot enumerate *unknown* ones.

**Tier 1 — written in Fusion, one function per file, in the stdlib directory:**
- Lists: `map filter reduce/fold reverse range head tail last init take drop zip
  flatten member find all any count`
- Comparison derivatives: `lessEq greaterThan greaterEq notEquals`
- Objects: `values entries get set merge` (built on `keys`)
- Control: `if` as a function helper.
- Each is a standalone `.fsn` file referenced via `@...`; recursion via self-ref.

### Open sub-questions
- Confirm `keys` (and maybe `values`/`entries`) must be Tier 0.
- Does `equals` on functions ever return anything but `!`/`false`? (function equality
  is undecidable — probably `!` or always-`false`).
- Numeric tower: one number type or int/float split? Affects `divide`, `floor`,
  `equals`. (Currently grammar has both int and float literals.)

## D. Module system (RESOLVED — it's `@`-references)

- **No separate module system and no `import` primitive.** `@path` references ARE
  the module system: a file is a value, so referencing a file imports a value.
- Namespacing comes free from the directory tree. Selective import / re-export are
  just object access on a file that evaluates to an object
  (e.g. `@lib.map` if `lib.fsn` is `{"map": (...), "filter": (...)}`).
- **Standard library = a directory of `.fsn` files** shipped with the runtime.
  Each function (`map`, `filter`, ...) is its own one-value file. See B for the

### Object-bundle access `@file.key` (analysis)
- **No new syntax needed.** `@enumerable.map` already parses as `(@enumerable).map`
  via existing rules: `fileref` (primary) + postfix `.key`. Precedence is correct:
  `.` binds tighter than `|`, so `xs | @enumerable.map` = `xs | (@enumerable.map)`.
- **Two equivalent-ish library shapes** now coexist, both reached with `@`:
  - directory of one-value files → `@map`, `@filter` (fine-grained loading)
  - one file holding an object → `@enumerable.map` (loads whole file for one field;
    one-time cost under memoization, but coarser granularity)
- **Bundling sacrifices relocatability (the real cost).** A function living as a
  field inside `enumerable.fsn` has no filename of its own, so to recurse or to
  call a sibling it must write `@enumerable.map` / `@enumerable.filter` — i.e. it
  **hard-codes its own file's external name**. Rename the file → all internal
  references break. One-function-per-file does NOT have this problem (self-ref is
  `@thatfile`, but each function genuinely owns its file). This is the
  "anonymous local recursion is awkward" tension (B) resurfacing: bundling
  reintroduces a function's need to name itself, with only the external name available.
- **Sibling references** within a bundle likewise go through the external name.
- **No multi-name local import.** Each use is a fresh `@enumerable.map`; with no
  `let`-form there is nowhere to bind `map`/`filter` as locals, so `@enumerable.`
  repeats at each call site. Another nudge toward an eventual local-binding form.

### NEW pressing decision: missing-key access → `!` or `null`?
- `@enumerable.map` when `map` is absent (or a typo `@enumerable.fitler`): yield `!`
  or `null`? Bundle access makes missing-key access COMMON, so this matters now.
- Leaning **`!`**: a typo'd method silently becoming `null` and propagating is exactly
  the bug class `!` exists to catch. Counter-view: if objects are open maps, missing
  key = legitimately absent = `null`. PICK ONE. (Same question applies to `x[i]`
  out-of-range and `x.k` on a non-object.)
  unresolved stdlib-root question.

---

## E. Crazy idea: destructuring functions (explored, NOT in grammar)

Two distinct readings:

1. **Reflect clauses as data (homoiconicity).** Treat a function as a list of
   `(pattern, output)` clause-pairs and pattern-match on that. Enables macros /
   function transformers (tracing, optimizing, reordering clauses) using the same
   matching machinery — no separate macro language.
   - **Blocker**: a *pattern* contains unbound binders, so it is not an ordinary
     value. Making patterns first-class would add a 4th ingredient and break the
     "only three" elegance.
   - **Cleanest path**: explicit, opt-in reflection via primitives
     `reflect : function → data` and `reify : data → function`, where patterns are
     represented as reflective AST objects (e.g. `{"bind":"a"}`, `{"array":[...]}`).
     Normal code keeps functions opaque; metaprogramming is a deliberate door.

2. **Match against / run functions backwards (relational).** Given an output, find an
   input — unification + search (Prolog / miniKanren).
   - Clean only for invertible functions (`swap`); hopeless for many-to-one (`_ => 0`).
   - Would change Fusion from *functional* to *relational*; needs backtracking search.
   - Tantalizing payoff: parsers, constraint solving, inverse functions "for free."

- **Function equality** (a third reading — match if input *is* a given function) is
  largely a non-starter: undecidable beyond trivial identity.

**Decision: keep all of this out of the grammar for now.** If pursued later, prefer
reading (1) via explicit `reflect`/`reify`. Reading (2) is a separate, much larger
language and should be its own project/mode.

---

## F. Earlier carried-over questions

- `_` is "match anything *except* `!`" — confirm the asymmetry is acceptable (it is
  what makes error propagation clean; cost is `_` no longer means literally anything).
- Should `!` carry a payload to distinguish error kinds (divide-by-zero vs type error
  vs no-match)? Currently no; `!` is a single opaque value.
- Should `null` ever be "sticky" like `!`? (Probably not — that's `!`'s job.)
- Left-to-right binding within a clause: explicitly REJECTED (see C in grammar).
- Reintroduce infix operator sugar once core is settled.
- Write a reference interpreter to force remaining decisions into the open.

---

## G. Decisions forced by the proof-of-concept interpreter (Ruby; verified via Python oracle)

- **Error propagation decoupled from strictness (CORRECTION).** The rev-3 claim
  "strict ⇔ error-propagating" was WRONG and the implementation proved it: a strict
  function `(_ => !)` given `!` does NOT fire, because `_` rejects `!`, so it fell
  through to `null`. Fix adopted: **`apply` propagates `!` for ANY function unless a
  clause explicitly matches `!`.** Propagation is now a property of application
  itself, uniform for strict and lenient functions. Strictness now means only what
  it literally says (error on no-match).
- **`_` and binders reject `!`** — confirmed and relied upon. Only literal `!` matches.
- **Missing key / OOR index / member-on-non-object → `!`** (chosen over `null`).
- **Built-in operations → `!` on bad input; predicates → `false`** — implemented.
- **Lazy + memoized `@refs`** — confirmed working for self- and mutual recursion.
- **Data cycle behavior refined:** not a blanket top-level `!`. The cycle yields `!`
  at the exact non-productive self-reference and keeps surrounding productive
  structure: `cyclicA = [1,@cyclicB]`, `cyclicB = [2,@cyclicA]` ⇒ `[1,[2,!]]`.
  (More useful than discarding everything; update spec wording accordingly.)
- **`@std/x` → bundled stdlib dir; all other `@path` relative to referencing file.**
  This is the resolution of the earlier "stdlib root vs pure-relative" question:
  ONE magic prefix (`std/`) + pure-relative for everything else.
- **Non-JSON stdin → `!`; empty stdin → `null`.**
- **Implementation caveat:** Ruby was not executable in the authoring sandbox (no
  network); `fusion.rb` was verified by behavioral equivalence to a runnable Python
  port (`oracle.py`, 38/38 tests), not by direct execution. Run locally to confirm.
