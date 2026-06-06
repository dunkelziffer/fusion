# Fusion — Design decision ledger

This document records the design decisions of the Fusion language: every decision made, who made it, the alternatives considered, and the trade-offs.

Future work and open questions are tracked separately in our [Roadmap](./roadmap.md).

**Attribution legend:**

- 🧑 **Designer** — decided by the language designer during the active design conversation (the human author of the language).
- 🤖 **Implementer** — decided by Claude (the implementer): either fleshing out a mechanism the designer left open during the design conversation, or forced while building the proof-of-concept interpreter when the running code exposed a question the spec had left implicit.
- 🔢 **Designer's pick from offered options** — Claude laid out the candidate choices; the designer selected one.

**Status legend:**

- ✅ **Accepted** — the current status quo
- ⏪ **Rewound** — an overruled or superseded decision, or an alternative that was initially implemented and then later revised (see the referenced section).
- ❌ **Rejected alternative** — considered, but rejected.
- 💭 **Hypothetical alternative** — never seriously considered, doesn't fit into the language.
- 🩹 **Remedied con** — a listed drawback later fixed or mitigated.

---

# 1. Values and data structures

## 1.1 Three ingredients beyond atoms

### Decisions

- 🧑 ✅ Besides atomic types (null, booleans, integers, floats, strings), the language has exactly three composite ingredients: arrays/lists, objects/maps and functions.

### Alternatives

- 🤖 💭 Add records/structs as distinct from maps.
- 🤖 💭 Add tuples distinct from arrays.
- 🤖 💭 Add a richer primitive set (dates, symbols, sets).

### Pros

- Minimal concept count.
- Instant familiarity for anyone who knows JSON.
- A clean "JSON + functions" elevator pitch.

### Cons

- No nominal types or tagged unions.
- Everything is structural, which can make large programs harder to keep disciplined.

---

## 1.2 JSON syntax for data

### Decisions

- 🧑 ✅ Syntax for atomic types, arrays and objects is borrowed wholesale from JSON: arrays are `[...]`, objects are `{...}` with quoted string keys, atoms are JSON literals.

### Alternatives

- 🤖 💭 S-expressions (Lisp).
- 🤖 💭 A bespoke literal syntax.
- 🤖 💭 YAML-like indentation.

### Pros

- Zero learning curve for data.
- Trivially serializable I/O.
- The language reads as data because it largely *is* data.

### Cons

- Object keys must be quoted strings, which is verbose for record-like use.
- JSON's lack of bare identifiers is exploited (see 2.2), but JSON's other constraints carry over:
  - Objects only support string keys
  - 🩹 No comments (Comments are added back as whole-line `#` comments — see reference §2.4.)

---

## 1.3 Numeric int/float distinction

### Decisions

- 🧑 ✅ Integers and floats are distinct kinds.
- 🤖 ✅ `divide` returns an integer when evenly divisible and a float otherwise.
- 🤖 ✅ `floor` returns an integer.
- 🤖 ✅ `equals` is exact.

### Alternatives

- 🤖 💭 A single number type (all floats, or arbitrary precision).
- 🤖 💭 A full numeric tower.

### Pros

- Matches JSON's practical number usage.
- Integer results stay integers.

### Cons

- Two kinds to reason about.
- `Integer` vs. `Float` predicates can surprise (e.g. `2.0` is a `Float`, not an `Integer`).
- Equality across kinds is not automatic.

---

## 1.4 Member/index access failures yield `!`

### Decisions

- 🤖 ✅ `x.key` on a missing key or non-object, and `x[i]` out of range or on a wrong type, yield `!` (not `null`).

### Why the implementer decided this

- The spec flagged this as an open question made pressing by object-bundle access (`@lib.map`).
- Choosing `!` means a typo'd member (`@lib.fitler`) fails loudly rather than silently becoming `null` and propagating as a mystery later.

### Alternatives

- 🤖 ❌ Return `null` for missing keys (treat objects as open maps).

### Pros

- Catches typos and shape errors at the access site.
- Consistent with "`!` = something went wrong."

### Cons

- Cannot use `x.maybeMissing` as a convenient "absent → null" probe.
- Callers wanting optionality must catch the `!`.

---

# 2. Functions and errors

## 2.1 Functions: one input, one output, ordered pattern-matching clauses

### Decisions

- 🧑 ✅ Every function takes exactly one argument and returns one value.
- 🧑 ✅ A function literal is `(pattern => result, pattern => result, ...)`.
- 🧑 ✅ Clauses are tried top to bottom; the first match wins.

### Alternatives

- 🤖 💭 Multi-argument functions.
- 🤖 💭 Unordered/guarded clause sets.
- 🤖 💭 A separate `match`/`case` construct distinct from function definition.

### Pros

- Application has a single uniform shape (see 2.3).
- Matching and dispatch are one mechanism.
- Multi-argument needs are met by passing arrays/objects, which are themselves first-class data.

### Cons

- Verbose arithmetic and multi-argument calls.
- Currying must be written explicitly as nested functions.

---

## 2.2 Bare identifiers are "holes"

### Decisions

- 🧑 ✅ Patterns and results are mirror images using the same names — values captured by a pattern are re-inserted in the result.
- 🤖 ✅ A bare (unquoted) identifier is the binder/hole: it binds in a pattern and reads in an expression (Claude's choice to use JSON's one unused syntactic slot, rather than a sigil).

### Alternatives

- 🤖 ❌ A sigil for binders (e.g. `$x`).
- 🤖 💭 Explicit binding keywords.
- 🤖 💭 Separate syntaxes for destructuring vs. construction.

### Pros

- Exploits JSON's one unused syntactic slot.
- Produces a striking pattern/result symmetry.
- Destructuring reads as correspondence, not procedure.

### Cons

- 🩹 A name in pattern position silently shadows a built-in of the same name (e.g. a pattern `add` binds, it does not match the function `add`).
- No visual marker distinguishes a binder from a literal at a glance.

---

## 2.3 Application by pipe: `value | function`

### Decisions

- 🧑 ✅ Function application is written `value | function`, left-associative.

### Alternatives

- 🤖 💭 Conventional `f(x)`.
- 🤖 💭 Reverse-pipe `f <| x`.
- 🤖 💭 Method-style `x.f()`.

### Pros

- Pipelines read left-to-right like a sentence.
- Composes naturally with the one-argument rule.
- No call-syntax or arity.

### Cons

- Unfamiliar to those expecting `f(x)`.
- Deeply nested non-linear data flow can require parentheses that reduce the pipeline's readability.

---

## 2.4 Refinement via `?`; types are predicates

### Decisions

- 🧑 ✅ A pattern may be refined by appending `? predicate`
- 🧑 ✅ Predicate functions double as a runtime type system: the built-in "types" (`Integer`, `String`, …) are ordinary predicate functions, so `a ? @Integer` matches only integers (inspired by the Ruby gem "literal").
- 🔢 ✅ The `?` refinement may follow *any* pattern, not just a lone binder; the clause then matches iff the pattern matches structurally **and** the matched value piped into the predicate yields `true` (Claude offered a restrictive per-binder form vs. this permissive any-pattern form; the designer chose permissive).
- 🧑 ✅ The predicate is any function.

### Alternatives

- 🤖 ❌ A dedicated type-annotation syntax.
- 🤖 ❌ Typed pattern keywords (`n: int`).
- 🤖 💭 A separate static type system.
- 🤖 ❌ `if`-style guards with arbitrary boolean expressions.

### Pros

- Unifies three things (structural matching, type checks, value guards) into one mechanism.
- The "type system" is user-extensible with ordinary functions.
- Nothing new to learn beyond `?`.

### Cons

- All checking is dynamic; no static guarantees.
- A predicate is run at match time, with a cost.
- Expressing relational guards requires the "parent container" idiom (see 2.5).

---

## 2.5 No sibling scope in patterns; relational guards go on a parent

### Decisions

- 🧑 ✅ All bindings in a clause are produced simultaneously.
- 🧑 ✅ A `?` predicate sees only the value matched by the pattern it is attached to, never a sibling binding.
- 🔢 ✅ To compare several captured values, attach the predicate to the enclosing container (Claude's "permissive" option; the designer selected it).

### Alternatives

- 🤖 ❌ Left-to-right binding so later predicates can see earlier bindings (Claude leaned toward it; the designer rejected it).
- 🤖 💭 Allowing predicates to reference the whole clause's bindings.

### Pros

- Matching is a pure structural walk with no scope-threading.
- Predicates can be checked in any order or in parallel.
- The rule is trivially simple to state.

### Cons

- Relational conditions (`a < b` across two bindings) need the slightly awkward "attach `?` to `[a, b]` and re-destructure inside the predicate" idiom.

---

## 2.6 The error mode `!`, distinct from `null`

### Decisions

- 🧑 ✅ Introduce a distinct error mode `!`, separate from `null`.
- 🧑 ✅ `null` = legitimate absence; `!` = failure.
- 🧑 ✅ A function is made *strict* by ending with `_ => !` (error on no match) and is otherwise *lenient* (returns `null` on no match).
- 🧑 ✅ Total predicates end with `_ => false`.
- 🤖 ✅ Built-in operations return `!` on bad input; built-in predicates return `false`.
- 🧑 ✅ The form of `!` (always carrying a payload) is fixed by 2.8.
- 🤖 ✅ `!` matches **only** error patterns (not `_`, not a binder).
- 🔢 ✅ Applying any function to `!` returns `!` unless that function has a clause whose pattern catches it (Claude offered auto-propagation-with-a-`catch`-builtin vs. this "matching `!` is ordinary" option; the designer chose the latter).
- 🤖 ✅ Error propagation is thus a property of application itself, independent of strictness — "strict" means only "error on no match," and propagation is automatic.

### Alternatives

- 🧑 ⏪ Overload `null` for both meanings (the original "no match → `null`" rule, superseded once `!` split absence from failure).
- 🤖 ❌ Make the *pipe operator* short-circuit on `!` with a dedicated `catch` built-in as the only handler (rejected: needs new mechanism; the existing pattern-matching machinery already expresses catches via an error pattern).
- 🤖 ⏪ Couple propagation to strictness so that only strict functions propagate (initially accepted as "a strict function is exactly one that propagates," then revised in implementation: `_` rejecting `!` and `_ => !` re-emitting `!` contradict each other, so propagation was decoupled from strictness and made a property of application).

### Pros

- `Result`/exception-style short-circuiting with no new syntax.
- Absence and failure are cleanly separated.
- Strictness is opt-in per function.

### Cons

- `_` does not mean "literally anything" (it excludes `!`), a subtle asymmetry.
- 🩹 An uncaught error can travel far from its origin, which can make debugging harder. Partially mitigated by more detailed error payloads in 2.9. Could be improved further with stack traces, see roadmap.

---

## 2.7 Non-exhaustive match: `null` for normal inputs, propagate for errors

### Decisions

- 🧑 ✅ If no clause matches and the input is not an error, the result is `null`.
- 🧑 ✅ Strictness (`_ => !`) is opt-in.
- 🧑 ✅ If the input is an error and no clause matched, the original error propagates (it is never silently turned into `null`).
- 🧑 ✅ The split matters because a function with error clauses matching *some* error shapes (e.g. `(!42 => "got 42", _ => "ok")`) and receiving an error of a different shape must still propagate that error — anything else would silently swallow failures that no clause acknowledged.

### Alternatives

- 🤖 ❌ Make non-exhaustive matching an error by default (strict-by-default), with leniency opt-in.
- 🤖 ⏪ Unify "no match" handling so that *all* non-matches return `null` regardless of input kind (the interpreter initially did this and swallowed unmatched errors to `null`; revised so partial error handlers preserve the propagation model).

### Pros

- Forgiving during exploration and prototyping.
- Base cases read naturally for non-error inputs.
- Errors are *never* silently swallowed, so a partially-matching error handler still preserves the original failure for diagnosis.

### Cons

- A typo'd or incomplete function silently yields `null` on non-error inputs, which can hide bugs several layers deep.
- The safer strict behavior must be remembered and added.

---

## 2.8 Payloaded errors

### Decisions

- 🧑 ✅ Every error is `!` followed by a **payload**, which may be any Fusion value (`!42`, `!"divide by zero"`, `!{"kind":"missing_key","key":"id"}`, `!null`).
- 🧑 ✅ Bare `!` in expression position is shorthand for `!null`.
- 🧑 ✅ In expression position, `!expr` is a prefix operator that wraps a value as an error; in pattern position, `!pat` matches an error and destructures its payload (bare `!` matches any error without binding; `!_` does the same but admits a `?` predicate).
- 🧑 ✅ Propagation preserves the *same* error (payload intact), so by the time you reach a catch site you still know what happened.
- 🧑 ✅ The CLI prints the payload (as JSON) to stderr on failure and exits `1`, leaving stdout empty.
- 🧑 ✅ **Errors propagate uniformly — they are not values.** At any moment of execution there is either a value or an error in motion, never both. Built-ins (including `@equals` and the type predicates), array and object literals, `?` predicates, and the function-value position of a pipe all propagate an encountered error. The only way to do anything with an error besides letting it propagate is to catch it in an `!pat` clause, which yields a normal value (the payload).
- 🧑 ✅ **No nested errors.** When `!expr` is evaluated and `expr` itself produces an error, that inner error propagates and the outer `!` is a no-op. This preserves the "never more than one error simultaneously" invariant — there is no `!!` value, ever.
- 🧑 ✅ **Partial matching propagates the unmatched error.** A function with error clauses that match *some* error shapes (e.g. `!42 => ...`) but not the one it receives (e.g. `!"oops"`) propagates the unmatched error rather than turning it into `null`. The "no match → null" lenient default from 2.7 applies only to non-error inputs.
- 🧑 ✅ **`!pat` is a top-level prefix in the clause grammar.** `!` is a prefix on the *clause pattern*, not on any sub-pattern: array elements, object members, and the payload of another `!` all recurse into the non-`!` pattern production. This grammar shape simultaneously enforces two things with no special-case parsing flag: (i) nested error patterns (`[!a, b]`, `{"err": !x}`, `!!42`, `!{"k": !v}`) are syntax errors, matching the runtime invariant that errors never sit inside other values; and (ii) `!pat ? pred` parses as `!(pat ? pred)`, so the `?` binds *inside* the `!`. The runtime payoff is that the predicate of `!a ? pred` naturally sees the payload, with no special case needed in `PGuard`.
- 🧑 ✅ **Predicate-errors bubble up to the function level.** If a `?` predicate evaluates to an error (it crashed, or it was itself an error value), that error becomes the function's result immediately, without trying later clauses. The alternative — treating a predicate-error as "no match" and continuing — would silently hide bugs in the predicate.

### Alternatives

- 🧑 ⏪ Keep `!` opaque with no payload (the original error model, superseded because it was too hard to debug).
- 🤖 💭 Use a `Result`-style two-variant `Ok | Err` (hypothetical: needs new machinery; payloaded errors with propagation give the same ergonomics with two rules).
- 🤖 ❌ Make payloads always strings (Claude's first payload sketch, e.g. `!"divide by zero"`; rejected because built-in mechanics like missing keys benefit from structured payloads).
- 🤖 ⏪ Make errors first-class values that can be stored in collections, compared with `@equals`, and inspected by predicates (Claude implemented this reading; the designer corrected it because it creates carve-outs in propagation that contradict the "never more than one error" invariant).
- 🤖 ⏪ Parse `!pat ? pred` as `(!pat) ? pred` so the predicate refines the whole error rather than the payload (Claude parsed it this way; the designer corrected it to `!(pat ? pred)` so the predicate sees the payload, matching its sibling binders).

### Pros

- Vastly improved debuggability — a propagated error tells you both *that* something failed and *what*.
- The catch site can dispatch on the error kind (`(!{"kind":"missing_key"} => ..., !msg => !msg)`).
- Construction and matching are syntactically symmetric (`!42` builds on the right of `=>`, matches on the left).
- Propagation remains uniform, with no carve-outs to remember.

### Cons

- 🩹 The payload format is part of the language's surface — built-ins originally used string payloads (`"divide: division by zero"`) while runtime mechanics used structured object payloads (`{"kind": ...}`). This inconsistency is resolved in 2.9: every error now carries the same structured payload.
- A payload that itself contains sensitive data becomes part of the program's stderr stream.
- The bare-`!`-means-`!null` rule preserves a simple expression form but means a careless `_ => !` clause gives a maximally unhelpful error.
- Inspecting an error's payload requires a small catch-and-rebind (`(!a => a)`) rather than direct comparison.

---

## 2.9 Standardized error payloads; no raw Ruby errors

### Decisions

- 🧑 ✅ Every error payload produced by the language has the **same shape**: an object with required fields `"kind"`, `"location"`, `"operation"`, `"input"`, and an optional `"message"`. This supersedes the 2.8 split where built-ins used bare-string payloads and runtime mechanics used `{"kind": ...}` objects.
- 🧑 ✅ **`kind`** is one of a closed set: `parse_error`, `reference_error`, `type_error`, `argument_error`, `binding_error`, `access_error`, `math_error`, `conversion_error`, `stack_error`, `serialization_error`.
- 🧑 ✅ **`location`** names where the failing operation lives: `"builtin X"`, `"stdlib X"`, `"code X"`, `"input"`, `"output"`, or `"interpreter"`. `input`/`output` refer to the data channels (stdin/CLI-arg in, stdout out), **never** to the program source — code always reports as `"code X"` (or `"code <inline>"` for a `-e` program).
- 🧑 ✅ **`operation`** describes the operation that failed (`"|"`, `".name"`, `"add"`, `"parsing a guardpat"`); **`input`** lists the operands it received; **`message`** carries optional human detail (`"expected an object"`).
- 🔢 ✅ `argument_error` means a *wrong number* (the input is not the pair/shape the operation needs); `type_error` means *expected X* / a type mismatch. The pair-builtins therefore split a non-pair (→ `argument_error`) from a pair of the wrong element types (→ `type_error`); `equals`, which constrains only shape, only ever raises `argument_error`.
- 🤖 ✅ Member/index access reserves `access_error` for exactly `missing key` and `index out of range`; accessing a member of a non-object or indexing with a wrong-typed key is a `type_error`. File-system access failures (missing file, a directory, permission denied) are `reference_error`, not `access_error`.

### No raw Ruby errors reach the user

- 🧑 ✅ The CLI contract already spends stdout (the result) and stderr (the error payload). There is **no third channel**, so a raw Ruby backtrace on stderr would corrupt the contract. Fusion therefore **catches every Ruby error a program can trigger and converts it to a standardized payload**.
- 🤖 ✅ Conversion happens deep (so an error is a catchable Fusion `!` where possible) *and* at a top-level net (so nothing escapes): each builtin call is wrapped (e.g. `floor` of a non-finite number → `math_error`), file reads rescue `SystemCallError` (→ `reference_error`), `Parser.parse_file` rescues every lexer/parser `ParseError` at that one entry point and returns a `parse_error` value (so files, inline `-e`, and the test harness all get a payload, never a raised error), a function result is reported as `serialization_error`, and a final `rescue Exception` in `exe/fusion` converts anything else — notably `SystemStackError` from unbounded recursion (→ `stack_error`, `location: "interpreter"`). The net must rescue `Exception`, not just `StandardError`, because `SystemStackError` is not a `StandardError`.
- 🤖 ✅ The **two internal-invariant asserts** (`FusionError` "Cannot evaluate node" / "Unknown pattern") are the deliberate exception: reaching them is an interpreter bug, not a user-facing error, so they are allowed to raise. The top-level net re-raises a non-parse `FusionError` rather than masking the bug.
- 🧑 ✅ The old `FUSION_DEBUG` env var (which `warn`ed file-not-found / read-failure detail to stderr during reference resolution) is **removed entirely**. It violated the contract by writing free-form text to stderr — the dedicated error-payload channel — and it added nothing: the `reference_error` payload already carries the same path (`input`/`location`) and Ruby message.

### Duplicate binders

- 🤖 ✅ Binding the same identifier twice in one clause (e.g. `([a, a] => ...)`, `({"x": v, "y": v} => ...)`, or a binder colliding with a `...rest` name) is a `binding_error`, not a non-linear "must be equal" match. It is detected in `match` as the binding is produced, so it surfaces only when the clause's shape otherwise matches (a non-matching shape just means the clause does not apply).

### Alternatives

- 🔢 ❌ Keep both payload shapes and document the rule (built-ins → strings, runtime → objects) — rejected in favor of one uniform shape, since catch clauses (`!{"kind": k}`) want a single dispatchable form.
- 🤖 ❌ A top-level net only — rejected because a mid-program Ruby error would then become a final result rather than a catchable `!`.
- 🤖 💭 An `internal_error` kind for the invariant asserts — declined; they stay as raised Ruby errors.

### Pros

- One payload shape: every catch site dispatches on `kind` the same way, and the five fields make an error self-describing (what failed, where, on what input).
- The CLI contract holds unconditionally — a program can crash the interpreter's host language and the user still gets a clean JSON payload and exit 1.

### Cons

- Payloads are more verbose than the old bare strings (`{"kind":"math_error", ...}` vs `"divide: division by zero"`).
- Some converted Ruby messages still leak host detail (e.g. an `Errno` message), pending per-case cleanup.
- The `location` for a stack overflow is only `"interpreter"` (no single owning file is knowable at that point).

---

# 3. @ references

## 3.1 A file contains exactly one value

### Decisions

- 🧑 ✅ A `.fsn` file contains exactly one expression, which is its value.
- 🧑 ✅ A file is *executable* if that value is a function; the runtime computes `STDIN | thatFunction`.
- 🧑 ✅ No top-level statement list, no top-level bindings.

### Alternatives (all earlier drafts, then dropped)

- 🧑 ⏪ A program as a list of `name = value` bindings executed top-to-bottom.
- 🤖 ⏪ Bindings plus a trailing "main" expression with mutually-recursive (`letrec`) scope.

### Pros

- The outermost layer is the same kind of thing as every inner layer (a value).
- Eliminates a whole second sub-language and its scoping rules.
- Makes the module system fall out for free (see 3.2).

### Cons

- No place for local definitions.
- Arithmetic/glue code can become many tiny files.

---

## 3.2 File references as the module system

### Decisions

- 🧑 ✅ `@a` evaluates to the value in `a.fsn`; `@dir/a` into a subdirectory; `@../a` up a directory.
- 🧑 ✅ A bare `@` is the current file.
- 🧑 ✅ This is the entire module system; there is no `import` primitive, and resolution is relative to the referencing file.
- 🧑 ✅ Recursion is written with a bare `@` (self-reference).
- 🧑 ⏪ The full resolution rules (including how built-ins and the standard library now share this namespace) were revised later — see 3.6.

### Alternatives

- 🤖 ❌ An explicit `import`/`use` construct with a namespace table.
- 🤖 💭 Content-addressed or URL-based imports.
- 🤖 💭 A single global namespace.

### Pros

- A file is a value, so importing is just referencing a value — one mechanism covers top-level structure, modules, and stdlib delivery.
- The directory tree is the namespace.
- Relocatable like Node relative `require`.

### Cons

- Couples module identity to filesystem layout.
- Deep relative paths can be unwieldy.
- Reaching outside the project (`@../../../x`) is possible and needs runtime sandboxing (a runtime concern).

---

## 3.3 References are lazy and memoized

### Decisions

- 🤖 ✅ A reference resolves when used, not when its file loads, and each path is evaluated once per run and cached.

### Why it matters (confirmed in implementation)

- 🤖 Laziness is what makes self- and mutual recursion possible: an eager resolver would loop forever resolving a file that references itself. The interpreter confirmed self-recursion (a bare `@` meaning "this file") and cross-file mutual recursion (`@even`/`@odd`) both work precisely because resolution is deferred to application time.

### Alternatives

- 🤖 ❌ Eager resolution at load (incompatible with self-reference).
- 🤖 ❌ No caching (re-evaluates shared dependencies redundantly).

### Pros

- Enables recursion with no special construct.
- Unused references never load.
- Shared/diamond dependencies load once.

### Cons

- Evaluation order is less obvious.
- 🩹 Data cycles are possible (handled — see 3.4).

---

## 3.4 Data-cycle handling

### Decisions

- 🤖 ✅ A non-productive data cycle (files whose values reference each other as data, not through a function boundary) yields an error at the point of the cyclic self-reference.
- 🤖 ⏪ The surrounding data structure is preserved. Example: `cyclicA = [1, @cyclicB]`, `cyclicB = [2, @cyclicA]` evaluates to `[1, [2, !]]`. Superseded by 2.8 as errors now immediately bubble to the top of each data structure.

### Why the implementer decided this

- The spec said only "detect a cycle → `!`."
- The running thunk-forcing logic naturally produced something more precise and more useful: the error lands exactly where the cycle closes, and the rest of the value survives.

### Alternatives

- 🤖 ❌ Blanket top-level `!` for the whole value (less informative).
- 🤖 ❌ Allow cycles as lazy infinite data (would require a lazy/streaming value model).

### Pros

- Maximally informative failure.
- Localizes the problem.

### Cons

- 🩹 A partially-`!` data structure can be surprising if not expected.

---

## 3.5 Object-bundle access `@file.key` needs no new syntax

### Decisions

- 🧑 ✅ Accessing a function bundled in a file-object, `@lib.map`, requires no new grammar: it is `(@lib)` (a primary) followed by `.map` (postfix member access), and `.` binds tighter than `|` so `xs | @lib.map` parses correctly.
- 🧑 ✅ A bundled function refers to itself and its siblings through `@.map` (a bare `@` for the current file, then a `.member` access), so it never has to name its own file and stays relocatable when the file is renamed.

### Pros

- Two library-organization styles (directory of files, or one object file) with no extra syntax.

### Cons

- The two styles are not equivalent.
- Bundling loads the whole file to reach one member (coarser load granularity), trading that for cohesion.

---

## 3.6 Unified `@` namespace with per-file shadowing

### Decisions

All access goes through `@`:

- 🧑 ✅ **Built-ins require `@`.** `@add`, `@Integer`, etc. A bare identifier is *only* a pattern hole; it never denotes a built-in. Built-ins cannot be shadowed by a clause's bindings — they live in a different namespace entirely.
- 🧑 ✅ **The standard library has no prefix.** `@map` reaches it directly.
- 🧑 ✅ **An `@name` reference (without leading `../`) resolves: sibling file → built-in → stdlib file → error.** First match wins. Consequently siblings can shadow a built-in or a stdlib function, but only for files in that directory (never globally).
- 🧑 ✅ **Built-in/stdlib fallback is gated on `../`, not on `/`.** Downward paths (`@dir/a`, `@math/sqrt`) remain eligible for the built-in/stdlib fallback; only upward paths (`@../a`) are file-only and never fall back.
- 🧑 ✅ **A bare `@`** (nothing after it) means the current file — recursion is written this way rather than by repeating the file's own name.
- 🧑 ✅ **`@ENV`** is a built-in evaluating to an object of environment variables (all string values, no parsing); read with member access (`@ENV.CI`).
- 🧑 ✅ **`@load`** is a built-in taking a filename **verbatim** (no `.fsn` appended), resolved relative to the referencing file, for runtime/non-identifier filenames. Both `@ENV` and `@load` resolve in the `@name` chain, so both are shadowable by a sibling file of that name.

### Why a single uniform chain

- Every bare `@name` follows one precedence order (sibling → builtin → stdlib), so there are no reserved names to remember and no parser carve-outs.
- `ENV` and `load` live in the builtin tier like everything else.
- Gating fallback on `../` rather than on the presence of any `/` keeps downward paths (`@math/sqrt`) eligible for the stdlib, which is what stdlib subpackaging needs.

### Alternatives

- 🤖 ⏪ Keep built-ins as bare globals (the prototype's original scheme, revised so built-ins require `@` and can't be shadowed by bindings).
- 🤖 ⏪ Add an `@std/` prefix for the standard library (used in the early prototype, e.g. `@std/map`; the designer removed it so stdlib has no prefix).
- 🤖 ❌ Reserve `@ENV`/`@load` as unshadowable (Claude raised it as a question; the designer chose to make both shadowable like any built-in).
- 🤖 ⏪ Gate fallback on any `/` (Claude's first implementation; the designer corrected it to gate on `../` only, so downward stdlib subdirectories still work).

### Pros

- One uniform access sigil for files, built-ins, stdlib, self, env, and dynamic load.
- Built-ins cannot be accidentally shadowed by bindings.
- Safe, *per-directory* shadowing of built-ins/stdlib.
- Downward stdlib packages (`@math/...`) work.

### Cons

- Built-ins are verbose (`@add` everywhere).
- Shadowing is invisible at the call site (whether `@map` is yours or the stdlib's depends on directory contents).
- A bare word that *looks* like a function reference is silently just a hole (reading an unbound one yields an error).

---

# 4. Runtime and CLI

## 4.1 Runtime I/O contract

### Decisions

- 🧑 ✅ Read stdin as JSON → value `v`; compute `v | program`; print the result as JSON.
- 🧑 ✅ A final `!` produces a nonzero exit code.
- 🤖 ✅ Empty stdin is treated as `null`.
- 🤖 ✅ Non-JSON stdin yields `!`.

### Alternatives

- 🤖 ❌ NDJSON/streaming input mapping the program over each line (deferred).
- 🤖 ⏪ A richer error report on stderr instead of a bare nonzero exit.

### Pros

- Fusion programs are first-class Unix filters.
- `!` maps onto exit status for free.

### Cons

- No streaming; whole input must be buffered and parsed.
- 🩹 A bare `!` with nonzero exit gives little diagnostic detail. Mitigated for internal errors by more detailed error payloads in 2.9.

---

# 5. Misc

## 5.1 No operator sugar (deferred)

### Decisions

- 🧑 ✅ No infix `+ - * / == < && …`.
- 🧑 ✅ Arithmetic, comparison, and boolean operations are built-in functions applied to a pair, e.g. `[a, b] | @add`.
- 🧑 ✅ Sugar is explicitly deferred, not rejected.

### Alternatives

- 🤖 ⏪ Provide infix operators as sugar desugaring to the built-ins immediately.

### Pros

- Keeps the core grammar tiny and uniform while semantics are being settled.
- Everything is visibly "just application."

### Cons

- Arithmetic-heavy code is verbose and harder to read (`[n, [n, 1] | @subtract | @fact] | @multiply` vs. `n * fact(n-1)`).

---

## 5.2 Standard library as one-function-per-file `.fsn`

### Decisions

- 🧑 ✅ The standard library is a directory of `.fsn` files reached via `@name` (the designer's file-reference scheme — "this should also solve how we build our standard library").
- 🤖 ✅ Each stdlib file is typically one function written in Fusion; only true primitives that cannot be written in Fusion are built into the interpreter.

### Alternatives

- 🤖 💭 A single bundled stdlib object/file.
- 🤖 ❌ Built-ins for everything common (Claude argued against this: include a built-in only if it can't be written in Fusion).

### Pros

- Fine-grained loading (use one function, load one file).
- Dogfoods the language.
- Proves expressiveness (if `map` can't be written in Fusion, that's a red flag).

### Cons

- Many small files.

---

## 5.3 Built-in primitive set (Tier 0)

### Decisions

- 🤖 ✅ Only things that can't be built in Fusion itself become a builtin. Other frequently used functions become part of the standard library.
- 🤖 ✅ The interpreter provides these builtins:
  - arithmetic (`add`, `subtract`, `multiply`, `divide`, `mod`, `negate`, `floor`);
  - comparison (`equals`, `lessThan`);
  - boolean (`and`, `or`, `not`);
  - bridges (`length`, `concat`, `chars`, `join`, `toString`, `parseNumber`, `keys`, `values`);
  - predicates (`Integer`, `Float`, `Number`, `String`, `Boolean`, `Array`, `Object`, `Null`).
- 🤖 ✅ `keys` must be a builtin: pattern matching can pull *known* object keys but cannot enumerate *unknown* ones, so iterating an object of unknown shape is impossible without it.

### Alternatives

- 🤖 ❌ Derive `lessThan`'s siblings as built-ins too (chose to leave `lessEq`/`greaterThan`/etc. to the library).
- 🤖 ❌ Omit `values` (derivable from `keys`).

### Pros

- Small, principled core.
- Clear "can't be written in Fusion" inclusion test.

### Cons

- Boundary cases (`floor`, `values`) are judgment calls.
- The Tier 1 library that would sit on top is only partially populated in the prototype.

---

## 5.4 Whole-line `#` comments

### Decisions

- 🧑 ✅ Comments are whole lines only: a line is a comment iff its first non-whitespace character is `#`. There are no inline or trailing comments.
- 🧑 ✅ Shebang lines (`#!/usr/bin/env fusion`) are supported, but need no special case, since a `#!` line is already a comment by the rule above.
- 🔢 ✅ Raw newlines inside string literals are forbidden (write `\n` instead), matching strict JSON. Claude flagged that the easy-strip guarantee depends on this.
- 🔢 ✅ The previous `// line` and `/* block */` syntax is removed, not kept as an alias

### Why the implementer flagged the string constraint

- The headline goal was "comments can be stripped without understanding the grammar." That holds for a per-line stripper (`grep -v '^[[:space:]]*#'`) **only if** a `#` at line-start can never be inside a string — i.e. strings cannot span physical lines. The old lexer accepted raw newlines in strings, which would have silently broken the guarantee, so the constraint was made explicit.

### Alternatives

- 🤖 ❌ Keep inline/trailing comments (e.g. `x | f  # note`). Rejected: a trailing comment reintroduces the string-vs-comment ambiguity (`"#"` in a string), defeating grammar-free stripping.
- 🤖 ❌ Keep `//` and `/* */` as aliases. Rejected for the same reason — `//` inside a string (`"http://…"`) breaks naive stripping.
- 🤖 💭 Allow multi-line strings and have the stripper track string state. Rejected: that is exactly the "understand the grammar" cost the design set out to avoid.

### Pros

- Comments are strippable by a one-line filter with no parser, and the rule is trivial to state.
- Shebang support falls out for free; the lexer treats `#!` as an ordinary comment.
- Fits the "functional JSON / Unix filter" idiom (shell, Python, YAML, TOML, Make all use `#`).

### Cons

- No way to annotate a single token mid-line; an explanatory comment must occupy its own line above the code.
- A breaking change from the earlier `//` / `/* */` syntax (acceptable at this Alpha stage).
