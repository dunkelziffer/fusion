# Fusion — language design decisions

This document records the design of the Fusion language ("functional JSON"): every
decision made, who made it, the alternatives considered, and the trade-offs. For the
roadmap of unfinished work and possible experiments, refer to [roadmap.md](./roadmap.md).

**Legend for attribution:**

- 🧑 **Designer** — decided by the language designer during the active design
  conversation (the human author of the language).
- 🤖 **Implementer** — decided or forced by Claude while building the proof-of-concept
  interpreter, often because the running code exposed a question the spec had left
  implicit or gotten wrong.

**Status of this document:** describes the prototype interpreter `fusion.rb`.

---

## 1. Three ingredients beyond atoms — 🧑

**Decision.** Besides atomic types (null, booleans, integers, floats, strings), the
language has exactly three composite ingredients: arrays/lists, objects/maps, and
functions. Syntax for the first two is borrowed wholesale from JSON.

**Alternatives.** Add records/structs as distinct from maps; add tuples distinct from
arrays; add a richer primitive set (dates, symbols, sets).

**Pros.** Minimal concept count; instant familiarity for anyone who knows JSON; a
clean "JSON + functions" elevator pitch. **Cons.** No nominal types or tagged unions;
everything is structural, which can make large programs harder to keep disciplined.

---

## 2. JSON syntax for data — 🧑

**Decision.** Arrays are `[...]`, objects are `{...}` with quoted string keys, atoms
are JSON literals. A program file is therefore almost-JSON with functions added.

**Alternatives.** S-expressions (Lisp), a bespoke literal syntax, YAML-like
indentation.

**Pros.** Zero learning curve for data; trivially serializable I/O; the language reads
as data because it largely *is* data. **Cons.** Object keys must be quoted strings,
which is verbose for record-like use; JSON's lack of bare identifiers is exploited
(see §4) but JSON's other constraints (no comments natively, string-only keys) carry
over.

---

## 3. Functions: one input, one output, ordered pattern-matching clauses — 🧑

**Decision.** Every function takes exactly one argument and returns one value. A
function literal is `(pattern => result, pattern => result, ...)`. Clauses are tried
top to bottom; the first match wins.

**Alternatives.** Multi-argument functions; unordered/guarded clause sets; a separate
`match`/`case` construct distinct from function definition.

**Pros.** Application has a single uniform shape (see §5); matching and dispatch are
one mechanism; multi-argument needs are met by passing arrays/objects, which are
themselves first-class data. **Cons.** Verbose arithmetic and multi-argument calls;
currying must be written explicitly as nested functions.

---

## 4. Bare identifiers are "holes" — 🧑

**Decision.** A bare (unquoted) identifier binds in a pattern and reads in an
expression. Patterns and results are mirror images using the same names.

**Alternatives.** A sigil for binders (e.g. `$x`); explicit binding keywords; separate
syntaxes for destructuring vs. construction.

**Pros.** Exploits JSON's one unused syntactic slot; produces a striking
pattern/result symmetry; destructuring reads as correspondence, not procedure.
**Cons.** A name in pattern position silently shadows a built-in of the same name
(e.g. a pattern `add` binds, it does not match the function `add`); no visual marker
distinguishes a binder from a literal at a glance.

---

## 5. Application by pipe: `value | function` — 🧑

**Decision.** Function application is written `value | function`, left-associative.

**Alternatives.** Conventional `f(x)`; reverse-pipe `f <| x`; method-style `x.f()`.

**Pros.** Pipelines read left-to-right like a sentence; composes naturally with the
one-argument rule; no call-syntax or arity. **Cons.** Unfamiliar to those expecting
`f(x)`; deeply nested non-linear data flow can require parentheses that reduce the
pipeline's readability.

---

## 6. Refinement via `?`; types are predicates — 🧑

**Decision.** Any pattern may be followed by `? predicate`. The clause matches iff the
pattern matches structurally **and** the matched value piped into the predicate yields
`true`. The predicate is any function. The built-in "types" (`Integer`, `String`, …)
are simply predicate functions.

**Alternatives.** A dedicated type-annotation syntax; typed pattern keywords
(`n: int`); a separate static type system; `if`-style guards with arbitrary boolean
expressions.

**Pros.** Unifies three things (structural matching, type checks, value guards) into
one mechanism; the "type system" is user-extensible with ordinary functions; nothing
new to learn beyond `?`. **Cons.** All checking is dynamic; no static guarantees; a
predicate is run at match time, with a cost; expressing relational guards requires the
"parent container" idiom (see §7).

---

## 7. No sibling scope in patterns; relational guards go on a parent — 🧑

**Decision.** All bindings in a clause are produced simultaneously. A `?` predicate
sees only the value matched by the pattern it is attached to, never a sibling binding.
To compare several captured values, attach the predicate to the enclosing container.

**Alternatives.** Left-to-right binding so later predicates can see earlier bindings
(explicitly rejected); allowing predicates to reference the whole clause's bindings.

**Pros.** Matching is a pure structural walk with no scope-threading; predicates can be
checked in any order or in parallel; the rule is trivially simple to state. **Cons.**
Relational conditions (`a < b` across two bindings) need the slightly awkward
"attach `?` to `[a, b]` and re-destructure inside the predicate" idiom.

---

## 8. The error value `!`, distinct from `null` — 🧑 (concept) / 🤖 (propagation semantics)

**Decision (🧑).** Introduce a first-class error value `!`, separate from `null`.
`null` = legitimate absence; `!` = failure. A function is made *strict* by ending with
`_ => !` (error on no match) and is otherwise *lenient* (returns `null` on no match).
Total predicates end with `_ => false`. Built-in operations return `!` on bad input;
built-in predicates return `false`.

**Decision (🤖).** `!` matches **only** the literal `!` pattern (not `_`, not a
binder), and **applying any function to `!` returns `!` unless that function has an
explicit `! =>` clause.** Error propagation is thus a property of application itself,
independent of strictness.

**Why the implementer had to decide the second half.** The original spec claimed
"strict ⇔ error-propagating," reasoning that the `_ => !` clause would re-emit an
incoming error. The interpreter falsified this: since `_` was (correctly) made to
reject `!`, a strict function's `_ => !` clause could not fire on an `!` input, so the
function fell through to `null` instead of propagating. The two rules contradicted
each other. The fix — propagation in `apply` itself — made the model simpler and
uniform, and decoupled "strict" (error on no match) from "propagating" (automatic).

**Alternatives.** Overload `null` for both meanings (rejected: conflates absence and
failure); make the *pipe operator* short-circuit on `!` with a dedicated `catch`
built-in as the only handler (rejected: needs new mechanism; the emergent
"explicit `! =>` clause catches" rule reuses existing matching); give `!` a payload to
distinguish error kinds (deferred — see [roadmap](./roadmap.md)).

**Pros.** `Result`/exception-style short-circuiting with no new syntax; absence and
failure are cleanly separated; strictness is opt-in per function. **Cons.** `_` no
longer means "literally anything" (it excludes `!`), a subtle asymmetry; `!` is opaque,
so all failures look alike; an uncaught `!` can travel far from its origin, which can
make debugging harder (mitigated by `FUSION_DEBUG`).

---

## 9. Non-exhaustive match returns `null` by default — 🧑

**Decision.** If no clause matches and the function is not strict, the result is
`null`. Strictness (`_ => !`) is opt-in.

**Alternatives.** Make non-exhaustive matching an error by default (strict-by-default),
with leniency opt-in.

**Pros.** Forgiving during exploration and prototyping; base cases read naturally.
**Cons.** A typo'd or incomplete function silently yields `null`, which can hide bugs
several layers deep; the safer strict behavior must be remembered and added.

---

## 10. No operator sugar (deferred) — 🧑

**Decision.** No infix `+ - * / == < && …`. Arithmetic, comparison, and boolean
operations are built-in functions applied to a pair, e.g. `[a, b] | add`. Sugar is
explicitly deferred, not rejected.

**Alternatives.** Provide infix operators as sugar desugaring to the built-ins
immediately.

**Pros.** Keeps the core grammar tiny and uniform while semantics are being settled;
everything is visibly "just application." **Cons.** Arithmetic-heavy code is verbose
and harder to read (`[n, [n, 1] | subtract | @fact] | multiply` vs. `n * fact(n-1)`).

---

## 11. A file contains exactly one value — 🧑

**Decision.** A `.fsn` file contains exactly one expression, which is its value. A
file is *executable* if that value is a function; the runtime computes
`STDIN | thatFunction`. No top-level statement list, no top-level bindings.

**Alternatives (all earlier drafts, then dropped).** A program as a list of
`name = value` bindings executed top-to-bottom; bindings plus a trailing "main"
expression with mutually-recursive (`letrec`) scope.

**Pros.** The outermost layer is the same kind of thing as every inner layer (a
value); eliminates a whole second sub-language and its scoping rules; makes the module
system fall out for free (see §12). **Cons.** No place for local definitions; a
recursive *helper* has nowhere to live but its own file (the recurring "anonymous
local recursion" tension); arithmetic/glue code can become many tiny files.

---

## 12. File references `@path` as the module system — 🧑

**Decision.** `@a` evaluates to the value in `a.fsn`. `@../a` goes up a directory,
`@dir/a` into a subdirectory, `@std/a` into the bundled standard library. This is the
entire module system; there is no `import` primitive. Resolution is relative to the
referencing file. Self-reference (`@fact` in `fact.fsn`) is how recursion is written.

**Alternatives.** An explicit `import`/`use` construct with a namespace table;
content-addressed or URL-based imports; a single global namespace.

**Pros.** A file is a value, so importing is just referencing a value — one mechanism
covers top-level structure, modules, and stdlib delivery; the directory tree is the
namespace; relocatable like Node relative `require`. **Cons.** Couples module identity
to filesystem layout; deep relative paths can be unwieldy; reaching outside the
project (`@../../../x`) is possible and needs runtime sandboxing (a runtime concern).

---

## 13. References are lazy and memoized — 🧑 (intent) / 🤖 (confirmed load-bearing)

**Decision.** A reference resolves when used, not when its file loads, and each path is
evaluated once per run and cached.

**Why it matters (confirmed in implementation).** Laziness is what makes self- and
mutual recursion possible: an eager resolver would loop forever resolving a file that
references itself. The interpreter confirmed self-recursion (`@fact`) and cross-file
mutual recursion (`@even`/`@odd`) both work precisely because resolution is deferred to
application time.

**Alternatives.** Eager resolution at load (incompatible with self-reference);
no caching (re-evaluates shared dependencies redundantly).

**Pros.** Enables recursion with no special construct; unused references never load;
shared/diamond dependencies load once. **Cons.** Evaluation order is less obvious; data
cycles are possible (handled — see §14).

---

## 14. Data-cycle handling — 🤖

**Decision.** A non-productive data cycle (files whose values reference each other as
data, not through a function boundary) yields `!` at the point of the cyclic
self-reference, while surrounding productive structure is preserved. Example:
`cyclicA = [1, @cyclicB]`, `cyclicB = [2, @cyclicA]` evaluates to `[1, [2, !]]`.

**Why the implementer decided this.** The spec said only "detect a cycle → `!`." The
running thunk-forcing logic naturally produced something more precise and more useful:
the error lands exactly where the cycle closes, and the rest of the value survives.

**Alternatives.** Blanket top-level `!` for the whole value (less informative); allow
cycles as lazy infinite data (would require a lazy/streaming value model).

**Pros.** Maximally informative failure; localizes the problem. **Cons.** A partially-
`!` data structure can be surprising if not expected.

---

## 15. Member/index access failures yield `!` — 🤖

**Decision.** `x.key` on a missing key or non-object, and `x[i]` out of range or on a
wrong type, yield `!` (not `null`).

**Why the implementer decided this.** The spec flagged this as an open question made
pressing by object-bundle access (`@lib.map`). Choosing `!` means a typo'd member
(`@lib.filter`) fails loudly rather than silently becoming `null` and propagating as a
mystery later.

**Alternatives.** Return `null` for missing keys (treat objects as open maps).

**Pros.** Catches typos and shape errors at the access site; consistent with "`!` =
something went wrong." **Cons.** Cannot use `x.maybeMissing` as a convenient "absent →
null" probe; callers wanting optionality must catch the `!`.

---

## 16. Runtime I/O contract — 🧑 (shape) / 🤖 (edge cases)

**Decision (🧑).** Read stdin as JSON → value `v`; compute `v | program`; print the
result as JSON; a final `!` produces a nonzero exit code.

**Decision (🤖).** Empty stdin is treated as `null`; non-JSON stdin yields `!`.

**Alternatives.** NDJSON/streaming input mapping the program over each line (deferred);
a richer error report on stderr instead of a bare nonzero exit.

**Pros.** Fusion programs are first-class Unix filters; `!` maps onto exit status for
free. **Cons.** No streaming; whole input must be buffered and parsed; a bare `!` with
nonzero exit gives little diagnostic detail (mitigated by `FUSION_DEBUG`).

---

## 17. Numeric int/float distinction — 🧑 (literals) / 🤖 (operation behavior)

**Decision.** Integers and floats are distinct kinds. `divide` returns an integer when
evenly divisible and a float otherwise; `floor` returns an integer; `equals` is exact.

**Alternatives.** A single number type (all floats, or arbitrary precision); a full
numeric tower.

**Pros.** Matches JSON's practical number usage; integer results stay integers.
**Cons.** Two kinds to reason about; `Integer` vs. `Float` predicates can surprise
(e.g. `2.0` is a `Float`, not an `Integer`); equality across kinds is not automatic.

---

## 18. Standard library as one-function-per-file `.fsn` — 🧑

**Decision.** The standard library is a directory of `.fsn` files, each typically one
function, written in Fusion and reached via `@std/...`. Only true primitives that
cannot be written in Fusion are built into the interpreter.

**Alternatives.** A single bundled stdlib object/file; built-ins for everything common.

**Pros.** Fine-grained loading (use one function, load one file); dogfoods the
language; proves expressiveness (if `map` can't be written in Fusion, that's a red
flag). **Cons.** Many small files; a function bundled into an object loses
relocatability because it must reference itself/siblings by the file's external name.

---

## 19. Built-in primitive set (Tier 0) — 🧑 (catalogue) / 🤖 (exact roster implemented)

**Decision.** The interpreter provides these primitives: arithmetic (`add`,
`subtract`, `multiply`, `divide`, `mod`, `negate`, `floor`); comparison (`equals`,
`lessThan`); boolean (`and`, `or`, `not`); bridges (`length`, `concat`, `chars`,
`join`, `toString`, `parseNumber`, `keys`, `values`); predicates (`Integer`, `Float`,
`Number`, `String`, `Boolean`, `Array`, `Object`, `Null`).

**Notable inclusion.** `keys` must be a primitive: pattern matching can pull *known*
object keys but cannot enumerate *unknown* ones, so iterating an object of unknown
shape is impossible without it.

**Alternatives.** Derive `lessThan`'s siblings as built-ins too (chose to leave
`lessEq`/`greaterThan`/etc. to the library); omit `values` (derivable from `keys`).

**Pros.** Small, principled core; clear "can't be written in Fusion" inclusion test.
**Cons.** Boundary cases (`floor`, `values`) are judgment calls; the Tier 1 library
that would sit on top is only partially populated in the prototype.

---

## 20. Object-bundle access `@file.key` needs no new syntax — 🧑

**Decision.** Accessing a function bundled in a file-object, `@lib.map`, requires no
new grammar: it is `(@lib)` (a primary) followed by `.map` (postfix member access),
and `.` binds tighter than `|` so `xs | @lib.map` parses correctly.

**Trade-off identified.** Bundling functions into one object file sacrifices
relocatability: a bundled function must refer to itself and its siblings through the
file's external name (`@lib.map`), so renaming the file breaks internal references.
One-function-per-file does not have this problem.

**Pros.** Two library-organization styles (directory of files, or one object file)
with no extra syntax. **Cons.** The two styles are not equivalent; bundling trades
relocatability and load granularity for cohesion.

---

## Appendix — Provenance

The decisions above were made across an iterative design conversation followed by a
proof-of-concept implementation. The 🧑/🤖 attribution marks whether a decision was a
deliberate design choice by the human designer (🧑) or a choice made or forced by
Claude while implementing and testing the interpreter (🤖), where running code often
exposed questions or contradictions the prose specification had left implicit. The
most consequential implementer-forced change was decoupling error propagation from
strictness (8.), which a contradiction in the running interpreter brought to light.
