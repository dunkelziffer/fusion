# Fusion — language design documentation

This document records the design of the Fusion language ("functional JSON"): every
decision made, who made it, the alternatives considered, and the trade-offs. It then
lays out the roadmap of unfinished work and possible experiments.

It supersedes and consolidates the earlier working notes (`fusion-grammar.md` and
`fusion-open-questions.md`), which remain as raw history.

**Legend for attribution:**

- 🧑 **Designer** — decided by the language designer during the active design
  conversation (the human author of the language).
- 🤖 **Implementer** — decided or forced by Claude while building the proof-of-concept
  interpreter, often because the running code exposed a question the spec had left
  implicit or gotten wrong.

**Status of this document:** describes the prototype interpreter `fusion.rb`
(grammar rev 4), covered by a test suite (core plus @-resolution feature tests).

---

## Part 1 — Design decisions

### 1.1 Three ingredients beyond atoms — 🧑

**Decision.** Besides atomic types (null, booleans, integers, floats, strings), the
language has exactly three composite ingredients: arrays/lists, objects/maps, and
functions. Syntax for the first two is borrowed wholesale from JSON.

**Alternatives.** Add records/structs as distinct from maps; add tuples distinct from
arrays; add a richer primitive set (dates, symbols, sets).

**Pros.** Minimal concept count; instant familiarity for anyone who knows JSON; a
clean "JSON + functions" elevator pitch. **Cons.** No nominal types or tagged unions;
everything is structural, which can make large programs harder to keep disciplined.

---

### 1.2 JSON syntax for data — 🧑

**Decision.** Arrays are `[...]`, objects are `{...}` with quoted string keys, atoms
are JSON literals. A program file is therefore almost-JSON with functions added.

**Alternatives.** S-expressions (Lisp), a bespoke literal syntax, YAML-like
indentation.

**Pros.** Zero learning curve for data; trivially serializable I/O; the language reads
as data because it largely *is* data. **Cons.** Object keys must be quoted strings,
which is verbose for record-like use; JSON's lack of bare identifiers is exploited
(see 1.4) but JSON's other constraints (no comments natively, string-only keys) carry
over.

---

### 1.3 Functions: one input, one output, ordered pattern-matching clauses — 🧑

**Decision.** Every function takes exactly one argument and returns one value. A
function literal is `(pattern => result, pattern => result, ...)`. Clauses are tried
top to bottom; the first match wins.

**Alternatives.** Multi-argument functions; unordered/guarded clause sets; a separate
`match`/`case` construct distinct from function definition.

**Pros.** Application has a single uniform shape (see 1.5); matching and dispatch are
one mechanism; multi-argument needs are met by passing arrays/objects, which are
themselves first-class data. **Cons.** Verbose arithmetic and multi-argument calls;
currying must be written explicitly as nested functions.

---

### 1.4 Bare identifiers are "holes" — 🧑

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

### 1.5 Application by pipe: `value | function` — 🧑

**Decision.** Function application is written `value | function`, left-associative.

**Alternatives.** Conventional `f(x)`; reverse-pipe `f <| x`; method-style `x.f()`.

**Pros.** Pipelines read left-to-right like a sentence; composes naturally with the
one-argument rule; no call-syntax or arity. **Cons.** Unfamiliar to those expecting
`f(x)`; deeply nested non-linear data flow can require parentheses that reduce the
pipeline's readability.

---

### 1.6 Refinement via `?`; types are predicates — 🧑

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
"parent container" idiom (see 1.7).

---

### 1.7 No sibling scope in patterns; relational guards go on a parent — 🧑

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

### 1.8 The error value `!`, distinct from `null` — 🧑 (concept) / 🤖 (propagation semantics)

**Decision (🧑).** Introduce a distinct error mode `!`, separate from `null`.
`null` = legitimate absence; `!` = failure. A function is made *strict* by ending with
`_ => !` (error on no match) and is otherwise *lenient* (returns `null` on no match).
Total predicates end with `_ => false`. Built-in operations return `!` on bad input;
built-in predicates return `false`. (At this stage, `!` is opaque — see 1.22 for
the payload extension.)

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
distinguish error kinds (deferred — see roadmap).

**Pros.** `Result`/exception-style short-circuiting with no new syntax; absence and
failure are cleanly separated; strictness is opt-in per function. **Cons.** `_` no
longer means "literally anything" (it excludes `!`), a subtle asymmetry; an uncaught
error can travel far from its origin, which can make debugging harder (mitigated by
`FUSION_DEBUG`). Originally, `!` was opaque — all failures looked alike — which was
the dominant ergonomic complaint and led to the later redesign in **1.22**, where
`!` was made to carry a payload.

---

### 1.9 Non-exhaustive match: `null` for normal inputs, propagate for errors — 🧑

**Decision.** If no clause matches and the input is not an error, the result is
`null`. Strictness (`_ => !`) is opt-in. **If the input is an error and no
clause matched, the original error propagates** (it is never silently turned
into `null`). This was a refinement: early implementation defaulted to `null`
in both cases, but that meant a function with error clauses that only matched
*some* error shapes would silently swallow the others — exactly the kind of
"loud failure quietly disappears" bug the error model is designed to prevent.

**Alternatives.** Make non-exhaustive matching an error by default
(strict-by-default), with leniency opt-in; or unify "no match" handling
(always `null` regardless of input kind).

**Pros.** Forgiving during exploration and prototyping; base cases read
naturally for non-error inputs; errors are *never* silently swallowed, so a
partially-matching error handler still preserves the original failure for
diagnosis. **Cons.** A typo'd or incomplete function silently yields `null`
on non-error inputs, which can hide bugs several layers deep; the safer
strict behavior must be remembered and added.

---

### 1.10 No operator sugar (deferred) — 🧑

**Decision.** No infix `+ - * / == < && …`. Arithmetic, comparison, and boolean
operations are built-in functions applied to a pair, e.g. `[a, b] | @add`. Sugar is
explicitly deferred, not rejected.

**Alternatives.** Provide infix operators as sugar desugaring to the built-ins
immediately.

**Pros.** Keeps the core grammar tiny and uniform while semantics are being settled;
everything is visibly "just application." **Cons.** Arithmetic-heavy code is verbose
and harder to read (`[n, [n, 1] | @subtract | @fact] | @multiply` vs. `n * fact(n-1)`).

---

### 1.11 A file contains exactly one value — 🧑

**Decision.** A `.fsn` file contains exactly one expression, which is its value. A
file is *executable* if that value is a function; the runtime computes
`STDIN | thatFunction`. No top-level statement list, no top-level bindings.

**Alternatives (all earlier drafts, then dropped).** A program as a list of
`name = value` bindings executed top-to-bottom; bindings plus a trailing "main"
expression with mutually-recursive (`letrec`) scope.

**Pros.** The outermost layer is the same kind of thing as every inner layer (a
value); eliminates a whole second sub-language and its scoping rules; makes the module
system fall out for free (see 1.12). **Cons.** No place for local definitions; a
recursive *helper* has nowhere to live but its own file (the recurring "anonymous
local recursion" tension); arithmetic/glue code can become many tiny files.

---

### 1.12 File references `@path` as the module system — 🧑

**Decision.** `@a` evaluates to the value in `a.fsn`; `@dir/a` into a subdirectory;
`@../a` up a directory. A bare `@` is the current file. This is the entire module
system; there is no `import` primitive, and resolution is relative to the referencing
file. Recursion is written with a bare `@` (self-reference). The full resolution rules
(including how built-ins and the standard library now share this namespace) were
revised later — see 1.21.

**Alternatives.** An explicit `import`/`use` construct with a namespace table;
content-addressed or URL-based imports; a single global namespace.

**Pros.** A file is a value, so importing is just referencing a value — one mechanism
covers top-level structure, modules, and stdlib delivery; the directory tree is the
namespace; relocatable like Node relative `require`. **Cons.** Couples module identity
to filesystem layout; deep relative paths can be unwieldy; reaching outside the
project (`@../../../x`) is possible and needs runtime sandboxing (a runtime concern).

---

### 1.13 References are lazy and memoized — 🧑 (intent) / 🤖 (confirmed load-bearing)

**Decision.** A reference resolves when used, not when its file loads, and each path is
evaluated once per run and cached.

**Why it matters (confirmed in implementation).** Laziness is what makes self- and
mutual recursion possible: an eager resolver would loop forever resolving a file that
references itself. The interpreter confirmed self-recursion (a bare `@` meaning "this
file") and cross-file mutual recursion (`@even`/`@odd`) both work precisely because
resolution is deferred to application time.

**Alternatives.** Eager resolution at load (incompatible with self-reference);
no caching (re-evaluates shared dependencies redundantly).

**Pros.** Enables recursion with no special construct; unused references never load;
shared/diamond dependencies load once. **Cons.** Evaluation order is less obvious; data
cycles are possible (handled — see 1.14).

---

### 1.14 Data-cycle handling — 🤖

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

### 1.15 Member/index access failures yield `!` — 🤖

**Decision.** `x.key` on a missing key or non-object, and `x[i]` out of range or on a
wrong type, yield `!` (not `null`).

**Why the implementer decided this.** The spec flagged this as an open question made
pressing by object-bundle access (`@lib.map`). Choosing `!` means a typo'd member
(`@lib.fitler`) fails loudly rather than silently becoming `null` and propagating as a
mystery later.

**Alternatives.** Return `null` for missing keys (treat objects as open maps).

**Pros.** Catches typos and shape errors at the access site; consistent with "`!` =
something went wrong." **Cons.** Cannot use `x.maybeMissing` as a convenient "absent →
null" probe; callers wanting optionality must catch the `!`.

---

### 1.16 Runtime I/O contract — 🧑 (shape) / 🤖 (edge cases)

**Decision (🧑).** Read stdin as JSON → value `v`; compute `v | program`; print the
result as JSON; a final `!` produces a nonzero exit code.

**Decision (🤖).** Empty stdin is treated as `null`; non-JSON stdin yields `!`.

**Alternatives.** NDJSON/streaming input mapping the program over each line (deferred);
a richer error report on stderr instead of a bare nonzero exit.

**Pros.** Fusion programs are first-class Unix filters; `!` maps onto exit status for
free. **Cons.** No streaming; whole input must be buffered and parsed; a bare `!` with
nonzero exit gives little diagnostic detail (mitigated by `FUSION_DEBUG`).

---

### 1.17 Numeric int/float distinction — 🧑 (literals) / 🤖 (operation behavior)

**Decision.** Integers and floats are distinct kinds. `divide` returns an integer when
evenly divisible and a float otherwise; `floor` returns an integer; `equals` is exact.

**Alternatives.** A single number type (all floats, or arbitrary precision); a full
numeric tower.

**Pros.** Matches JSON's practical number usage; integer results stay integers.
**Cons.** Two kinds to reason about; `Integer` vs. `Float` predicates can surprise
(e.g. `2.0` is a `Float`, not an `Integer`); equality across kinds is not automatic.

---

### 1.18 Standard library as one-function-per-file `.fsn` — 🧑

**Decision.** The standard library is a directory of `.fsn` files, each typically one
function, written in Fusion and reached via `@name`. Only true primitives that
cannot be written in Fusion are built into the interpreter.

**Alternatives.** A single bundled stdlib object/file; built-ins for everything common.

**Pros.** Fine-grained loading (use one function, load one file); dogfoods the
language; proves expressiveness (if `map` can't be written in Fusion, that's a red
flag). **Cons.** Many small files; a function bundled into an object loses
relocatability because it must reference itself/siblings by the file's external name.

---

### 1.19 Built-in primitive set (Tier 0) — 🧑 (catalogue) / 🤖 (exact roster implemented)

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

### 1.20 Object-bundle access `@file.key` needs no new syntax — 🧑

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

### 1.21 Unified `@` namespace with per-file shadowing — 🧑

**Decision (a later redesign of access).** All access goes through `@`:

- **Built-ins require `@`.** `@add`, `@Integer`, etc. A bare identifier is now *only*
  a pattern hole; it never denotes a built-in. This means built-ins can no longer be
  shadowed by a clause's bindings — they live in a different namespace entirely.
- **The standard library dropped its `std/` prefix.** `@map` reaches it directly.
- **A bare `@name` (no `/`, no `../`) resolves: sibling file → built-in → stdlib
  file → `!`.** First match wins. Consequently siblings can shadow a built-in or a
  stdlib function, but only for files in that directory (never globally).
- **Built-in/stdlib fallback is gated on `../`, not on `/`.** Downward paths
  (`@dir/a`, `@math/sqrt`) remain eligible for the built-in/stdlib fallback; only
  upward paths (`@../a`) are file-only and never fall back.
- **A bare `@`** (nothing after it) means the current file — recursion is written
  this way rather than by repeating the file's own name.
- **`@ENV`** is a built-in evaluating to an object of environment variables (all
  string values, no parsing); read with member access (`@ENV.CI`).
- **`@load`** is a built-in taking a filename **verbatim** (no `.fsn` appended),
  resolved relative to the referencing file, for runtime/non-identifier filenames.
  Both `@ENV` and `@load` resolve in the `@name` chain, so both are shadowable by a
  sibling file of that name.

**Why "self/ENV/load shadowable, and `../` is the only fallback gate."** During
implementation it was cleaner to give *every* bare `@name` one uniform precedence
(sibling → builtin → stdlib) than to carve out reserved names; `ENV` and `load` simply
live in the builtin tier. And the original "a `/` makes it a pure path" rule was too
strong — it wrongly excluded downward paths from the stdlib — so the gate was narrowed
to `../` only.

**Alternatives.** Keep built-ins as bare globals (rejected: they could be shadowed by
any same-named binding, and the `@`-everything story is more uniform); keep an
`@std/` prefix (rejected: extra ceremony, and a magic prefix); make `@ENV`/`@load`
reserved/unshadowable (rejected: less uniform); gate fallback on any `/` (rejected:
breaks stdlib subdirectories).

**Pros.** One uniform access sigil for files, built-ins, stdlib, self, env, and
dynamic load; built-ins can no longer be accidentally shadowed by bindings; safe,
*per-directory* shadowing of built-ins/stdlib; downward stdlib packages (`@math/...`)
work. **Cons.** Built-ins are now verbose (`@add` everywhere); shadowing is invisible
at the call site (whether `@map` is yours or the stdlib's depends on directory
contents); a bare word that *looks* like a function reference is silently just a hole
(reading an unbound one yields an error).

---

### 1.22 Payloaded errors — 🧑 (concept and motivation) / 🤖 (predicate/equality/literal subtleties)

**Decision (🧑).** Replace the opaque `!` of 1.8 with a compound error value: every
error is `!` followed by a **payload**, which may be any Fusion value (`!42`,
`!"divide by zero"`, `!{"kind":"missing_key","key":"id"}`, `!null`). Bare `!` is
shorthand for `!null`, preserving the look of existing code. In expression position,
`!expr` is a prefix operator that wraps a value as an error; in pattern position,
`!pat` matches an error and destructures its payload (bare `!` and `!_` match any
error). Propagation preserves the *same* error (payload intact), so by the time you
reach a catch site you still know what happened. The CLI prints the payload (as
JSON) to stderr on failure and exits `1`, leaving stdout empty.

**Decision (🤖).** Three subtleties emerged from implementation that needed to be
nailed down for the model to hold together coherently:

- **Errors propagate uniformly — they are not values.** At any moment of
  execution there is either a value or an error in motion, never both.
  Built-ins (including `@equals` and the type predicates), array and object
  literals, `?` predicates, and the function-value position of a pipe all
  propagate an encountered error. The only way to do anything with an error
  besides letting it propagate is to catch it in an `!pat` clause, which
  yields a normal value (the payload). An earlier prototype made errors
  "first-class values" (storable in collections, examined by predicates,
  comparable with `@equals`); the user rejected this — it created exactly the
  kind of carve-outs the rest of the language is designed to avoid, and was
  reverted before any external code grew.
- **No nested errors.** When `!expr` is evaluated and `expr` itself produces an
  error, that inner error propagates and the outer `!` is a no-op. This
  preserves the "never more than one error simultaneously" invariant — there
  is no `!!` value, ever.
- **Partial matching propagates the unmatched error.** A function with error
  clauses that match *some* error shapes (e.g. `!42 => ...`) but not the one
  it receives (e.g. `!"oops"`) must still propagate the unmatched error,
  not turn it into `null`. The simpler "lenient default" rule from 1.9 was
  refined to: on no clause matching, return `null` only if the input is not
  an error; otherwise propagate the error. This prevents the silent-swallow
  bug where a partial error handler would erase the original failure.
- **`!pat` is a top-level prefix in the clause grammar.** `!` is a prefix on
  the *clause pattern*, not on any sub-pattern: array elements, object
  members, and the payload of another `!` all recurse into the non-`!`
  pattern production. This grammar shape simultaneously enforces two things
  with no special-case parsing flag: (i) nested error patterns
  (`[!a, b]`, `{"err": !x}`, `!!42`, `!{"k": !v}`) are syntax errors,
  matching the runtime invariant that errors never sit inside other values;
  and (ii) `!pat ? pred` parses as `!(pat ? pred)`, so the `?` binds *inside*
  the `!`. The runtime payoff is that the predicate of `!a ? pred` naturally
  sees the payload (because by the time the guard runs, the value at hand is
  already the payload), removing what would otherwise be a special case in
  `PGuard`. An earlier implementation parsed `!pat ? pred` as
  `(!pat) ? pred` and special-cased `PGuard` to inspect its inner for `PErr`;
  the user pointed out the parse shape was wrong, and switching to the
  cleaner grammar dropped both that runtime special case and the per-context
  parser flag (`allow_err`) in one change.
- **Predicate-errors bubble up to the function level.** If a `?` predicate
  evaluates to an error (it crashed, or it was itself an error value), that
  error becomes the function's result immediately, without trying later
  clauses. The alternative — treating a predicate-error as "no match" and
  continuing — would silently hide bugs in the predicate.

**Alternatives.** Keep `!` opaque, with a separate logging channel for
diagnostics (rejected: the payload carries debugging context exactly where it's
needed); use a `Result`-style two-variant `Ok | Err` (rejected: needs new
machinery; payloaded errors with propagation give the same ergonomics with two
rules); make payloads always strings (rejected: built-in mechanics like missing
keys benefit from structured payloads); make errors first-class values that can
be stored, compared, and inspected directly (rejected by the user: creates
carve-outs in propagation that contradict the "never more than one error"
invariant).

**Pros.** Vastly improved debuggability — a propagated error tells you both
*that* something failed and *what*; the catch site can dispatch on the error
kind (`(!{"kind":"missing_key"} => ..., !msg => !msg)`); construction and
matching are syntactically symmetric (`!42` builds on the right of `=>`,
matches on the left); propagation remains uniform, with no carve-outs to
remember. **Cons.** The payload format is now part of the language's surface
— built-ins currently use string payloads (`"divide: division by zero"`)
while runtime mechanics use structured object payloads (`{"kind": ...}`), an
inconsistency worth resolving (see 2.2); a payload that itself contains
sensitive data becomes part of the program's stderr stream; the bare-`!`-means-
`!null` rule preserves source compatibility but means a careless `_ => !`
clause gives a maximally unhelpful error; inspecting an error's payload now
requires a small catch-and-rebind (`(!a => a)`) rather than direct comparison.

---

## Part 2 — Roadmap and open questions

### 2.1 Ergonomics: the most-wanted improvements

**Operator sugar (planned).** Reintroduce infix `+ - * / % == != < <= > >= && || !`
and string `++`, desugaring to the existing built-ins over pairs. Pure ergonomics,
no semantic change. This is the single biggest readability win available and was
always intended. Open question: exact precedence table and how it interleaves with
`|` and `=>`.

**A local binding form (the recurring tension).** "Anonymous local recursion is
awkward" has surfaced three times: recursion needs a name; bundled functions need to
name themselves; multi-name imports have nowhere to bind. A single `let`-style form
(binding names within an expression, mutually recursive) would resolve all three. It
would be the **first genuinely new construct** in the language, so it is being resisted
until the need is undeniable. Sub-questions: syntax that doesn't clash with JSON;
whether it implies giving up "one value per file" framing internally.

**`@`-namespace resolution polish.** Decide on project-root confinement (sandboxing)
for `@../` escapes; consider a configurable standard-library search path; consider
tooling to surface *which* target a given `@name` resolves to in a directory (since
shadowing is invisible at the call site). The core resolution rules (sibling →
built-in → stdlib, `../` as the only fallback gate, `@`/`@ENV`/`@load`) are settled —
see 1.21.

### 2.2 Error model

**Payload shape consistency** *(open)*. Payloaded errors landed (see 1.22), but the
payload *shape* is inconsistent: built-ins use bare strings (`"divide: division by
zero"`) while runtime mechanics use structured objects (`{"kind":"missing_key",
"key":"foo"}`). The string form is human-friendlier; the structured form is
machine-friendlier (catchable via `!{"kind": k}`). Three plausible resolutions:
(a) all errors get structured payloads with a `kind` and an optional `message`;
(b) all errors get human strings, and structured matching is left to user code;
(c) keep both, document the rule that built-in operations use strings and runtime
mechanics use objects. This is a small but irreversible decision (it shapes how
catch clauses are written) and should be decided before any external code grows
that depends on the current shapes.

**Better diagnostics.** `FUSION_DEBUG` exists for file/parse errors; extend
principled diagnostics to runtime error origins (where did this error first
arise?). With payloaded errors this could mean attaching a source position to the
payload (an extra `"at": "file.fsn:L:C"` field) when `FUSION_DEBUG` is set.

**Stack traces** *(deferred)*. Currently a propagated error tells you what
happened, but not the chain of function applications it passed through. A capped
trace (last N frames, accessible as an extra payload field, opt-in via env) would
help in deep pipelines.

### 2.3 Standard library completion

Populate Tier 1 (written in Fusion): `filter`, `reduce`/`fold`, `reverse`, `head`,
`tail`, `last`, `init`, `take`, `drop`, `zip`, `flatten`, `member`, `find`, `all`,
`any`, `count`; comparison derivatives `lessEq`, `greaterThan`, `greaterEq`,
`notEquals`; object helpers `entries`, `get`, `set`, `merge`; an `if` helper. This is
also the best stress test of whether the language is pleasant to *write* in, not just
to implement.

### 2.4 Runtime and tooling

- **Streaming I/O** (NDJSON): map a program over a stream of JSON values.
- **Sandboxed reference resolution** confined to a project root.
- **A real CLI** beyond the prototype (`-e`, file, stdin) with better error reporting.
- **A faster implementation** once semantics are frozen (the current `fusion.rb` is a
  proof of concept, not optimized).

### 2.5 Open semantic questions to settle

- Should `_` strictly exclude `!` (current) or match literally anything? The current
  asymmetry is what makes propagation clean; confirm it is acceptable long-term.
- Should `null` ever be "sticky" like `!`? (Almost certainly not — that is `!`'s job.)
- Numeric tower: keep int/float split, or move to a single number type / arbitrary
  precision? Affects `divide`, `floor`, `equals`, and the `Integer`/`Float` predicates.
- Function equality: `equals` on two functions — always `false`, or `!`? (Function
  equality is undecidable beyond trivial identity.)

### 2.6 Bigger experiments

**Destructuring functions (homoiconicity).** Treat a function as a list of
`(pattern, output)` clause-pairs and pattern-match on it, enabling macros and function
transformers with the same matching machinery. The clean path is explicit, opt-in
reflection (`reflect : function → data`, `reify : data → function`) representing
patterns as reflective AST objects, so normal code keeps functions opaque and "three
ingredients" intact. High payoff (metaprogramming), moderate disruption.

**Running functions backwards (relational mode).** Given an output, find an input —
unification and search, à la Prolog/miniKanren. Clean only for invertible functions;
hopeless for many-to-one. Would change Fusion from functional to relational and needs
backtracking search. The most exciting and most disruptive possible direction; best
pursued as a separate mode or sibling project rather than folded into the core.

**A static checker.** Because "types" are predicates, a optional static layer could
attempt to verify predicate-guarded clauses and exhaustiveness without changing the
dynamic semantics. Speculative.

---

## Appendix — Provenance

The decisions above were made across an iterative design conversation followed by a
proof-of-concept implementation. The 🧑/🤖 attribution marks whether a decision was a
deliberate design choice by the human designer (🧑) or a choice made or forced by
Claude while implementing and testing the interpreter (🤖), where running code often
exposed questions or contradictions the prose specification had left implicit. The
most consequential implementer-forced change was decoupling error propagation from
strictness (1.8), which a contradiction in the running interpreter brought to light.
