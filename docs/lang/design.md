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
- 🤖 ⏪ `@OP.divide` returned an integer when evenly divisible, a float otherwise. Reverted in §5.5. It is now always a float, with integer division split out to `@OP.quotient` (§5.5).
- 🤖 ✅ `@math.floor` returns an integer.
- 🤖 ✅ `@OP.equal` is exact.

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

## 1.4 Member/index access failures yield an error

### Decisions

- 🤖 ✅ `x.key` on a missing key or non-object, and `x[i]` out of range or on a wrong type, yield an error (instead of `null`).

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
- 🧑 ✅ The clause list may be empty: `()` is the empty function (not an empty/invalid grouping).

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

- 🧑 ✅ Patterns and results are mirror images using the same names. Values captured by a pattern are re-inserted in the result.
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
- 🧑 ✅ A predicate may be a `|` chain of functions, the matched value flowing in from the left: `a ? b | c` matches when `a` matches and `a | b | c` is truthy. The grammar's `predicate` is a full `pipe` (was a single `prefix`).

### Alternatives

- 🤖 ❌ A dedicated type-annotation syntax.
- 🤖 ❌ Typed pattern keywords (`n: int`).
- 🤖 💭 A separate static type system.
- 🤖 ❌ `if`-style guards with arbitrary boolean expressions.
- 🤖 💭 Keep predicates single-function and compose via an inline `(x => x | b | c)`. Rejected: pure noise next to `b | c`.

### Pros

- Unifies three things (structural matching, type checks, value guards) into one mechanism.
- The "type system" is user-extensible with ordinary functions.
- Nothing new to learn beyond `?`.
- Predicates compose directly (`a ? @ends | @OP.equal`) instead of requiring a wrapping function (`a ? (x => x | @ends | @OP.equal)`).

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
- 🧑 ⏪ Total predicates end with `_ => false`. Obsoleted by §2.12. Predicates no longer need a `_ => false` clause, because `null` became equivalent to `false`.
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
- 🧑 ✅ **Errors propagate uniformly — they are not values.** At any moment of execution there is either a value or an error in motion, never both. Built-ins (including `@OP.equal` and the type predicates), array and object literals, `?` predicates, and the function-value position of a pipe all propagate an encountered error. The only way to do anything with an error besides letting it propagate is to catch it in an `!pat` clause, which yields a normal value (the payload).
- 🧑 ✅ **No nested errors.** When `!expr` is evaluated and `expr` itself produces an error, that inner error propagates and the outer `!` is a no-op. This preserves the "never more than one error simultaneously" invariant — there is no `!!` value, ever.
- 🧑 ✅ **Partial matching propagates the unmatched error.** A function with error clauses that match *some* error shapes (e.g. `!42 => ...`) but not the one it receives (e.g. `!"oops"`) propagates the unmatched error rather than turning it into `null`. The "no match → null" lenient default from 2.7 applies only to non-error inputs.
- 🧑 ✅ **`!pat` is a top-level prefix in the clause grammar.** `!` is a prefix on the *clause pattern*, not on any sub-pattern: array elements, object members, and the payload of another `!` all recurse into the non-`!` pattern production. This grammar shape simultaneously enforces two things with no special-case parsing flag: (i) nested error patterns (`[!a, b]`, `{"err": !x}`, `!!42`, `!{"k": !v}`) are syntax errors, matching the runtime invariant that errors never sit inside other values; and (ii) `!pat ? pred` parses as `!(pat ? pred)`, so the `?` binds *inside* the `!`. The runtime payoff is that the predicate of `!a ? pred` naturally sees the payload, with no special case needed in `PGuard`.
- 🧑 ✅ **Predicate-errors bubble up to the function level.** If a `?` predicate evaluates to an error (it crashed, or it was itself an error value), that error becomes the function's result immediately, without trying later clauses. The alternative — treating a predicate-error as "no match" and continuing — would silently hide bugs in the predicate.

### Alternatives

- 🧑 ⏪ Keep `!` opaque with no payload (the original error model, superseded because it was too hard to debug).
- 🤖 💭 Use a `Result`-style two-variant `Ok | Err` (hypothetical: needs new machinery; payloaded errors with propagation give the same ergonomics with two rules).
- 🤖 ❌ Make payloads always strings (Claude's first payload sketch, e.g. `!"divide by zero"`; rejected because built-in mechanics like missing keys benefit from structured payloads).
- 🤖 ⏪ Make errors first-class values that can be stored in collections, compared with `@OP.equal`, and inspected by predicates (Claude implemented this reading; the designer corrected it because it creates carve-outs in propagation that contradict the "never more than one error" invariant).
- 🤖 ⏪ Parse `!pat ? pred` as `(!pat) ? pred` so the predicate refines the whole error rather than the payload (Claude parsed it this way; the designer corrected it to `!(pat ? pred)` so the predicate sees the payload, matching its sibling binders).

### Pros

- Vastly improved debuggability — a propagated error tells you both *that* something failed and *what*.
- The catch site can dispatch on the error kind (`(!{"kind":"missing_key"} => ..., !msg => !msg)`).
- Construction and matching are syntactically symmetric (`!42` builds on the right of `=>`, matches on the left).
- Propagation remains uniform, with no carve-outs to remember.
- The previous error model with the single error value `!` can still be emulated:
  - The expression `!` is equivalent to `!null`.
  - The pattern `!` is equivalent to `!_`.

### Cons

- 🩹 The payload format is part of the language's surface. Builtins used string payloads (`"divide: division by zero"`) while the standard library used structured object payloads (`{"kind": ...}`). This inconsistency was resolved in 2.9.
- A payload that itself contains sensitive data becomes part of the program's stderr stream.
- The bare-`!`-means-`!null` rule preserves a simple expression form but means a careless `_ => !` clause gives a maximally unhelpful error.
- Inspecting an error's payload requires a small catch-and-rebind (`(!a => a)`) rather than direct comparison.

---

## 2.9 Standardized error payloads

### Decisions

- 🧑 ✅ Every error payload produced by "the runtime" (the interpreter or a built-in function) has the **same shape**. This shape is enforced by constructing "runtime errors" via `ErrorVal.from_runtime`. The full schema is documented in [reference §6.5](../user/reference.md#65-the-standardized-error-payload).
- 🤖 ⏪ The stdlib is "ordinary unpriviledged Fusion code". It didn't produce runtime errors. Reverted by §2.13. The stdlib now constructs regular `!expr` user errors, but they get marked as runtime errors afterwards.
- 🧑 ✅ All stdlib functions mirror the built-in error shape.
- 🔢 ⏪ During function application we differentiated `argument_error` (bad input *shape*, expressible as a pattern without `?`) from `type_error` (bad input *type*). Reverted in §2.13. Both errors got unified into a single `argument_error`.
- 🧑 ✅ Member/index access reserves `access_error` for exactly `missing key` and `index out of range`:
  - Accessing a member of a non-object or indexing with a wrong-typed key is a `type_error` instead.
  - File-system access failures ("missing file", "directory instead of file", "permission denied") are a `reference_error` instead.

### Alternatives

- 🔢 ⏪ Keep the previous split between builtin errors (string payload) and stdlib errors (object payloads). Only document the rule.
- 🧑 💭 Don't standardize the error payloads at all.

### Pros

- Every catch site (`!` pattern) can rely on this default shape.
- The structured fields make errors self-describing (what failed, where, on what input).

### Cons

- The new structured payloads are more verbose than the old bare strings.
- Some converted Ruby messages still leak host detail (e.g. an `Errno` message). Pending per-case cleanup.

---

## 2.10 Disallow duplicate binders

### Decisions

- 🧑 ✅ Binding the same identifier twice in one clause is a `binding_error`.
- 🤖 ✅ It is detected in `match` as the binding is produced, so it surfaces only when the clause's shape otherwise matches. A non-matching shape just means the clause does not apply.

### Alternatives

- 🧑 ❌ Binding the same identifier twice is a non-linear "must be equal". The pattern only matches, if all parts with the same identifier have the same value.

### Pros

- Less implementation effort than "equal identifiers mean equal value". Already solved by fully generic `?` predicates.
- Runtime detection fits to this language's dynamic nature.

### Cons

- Slightly less expressive pattern language.
- Invalid patterns will only raise an error as soon as a value actually matches. No static guarantees.

---

## 2.11 Stricter objects: unique keys, rest last, closed by default

### Decisions

- 🧑 ✅ A fixed object key may not repeat (in expressions and patterns). Keys arriving via `...spread` / `...rest` are dynamic and not checked.
- 🧑 ✅ In an object pattern, `...rest` must come last.
- 🧑 ✅ An object pattern without a `...rest` is *closed*. It matches only an object whose keys are *exactly* the pattern's

### Alternatives

- 🤖 💭 Last-write-wins for duplicate literal keys (JSON behavior). Rejected: silently dropping a written key hides mistakes.
- 🧑 ⏪ Object patterns always open — extra keys ignored regardless of a rest. Superseded: it gave no way to assert "exactly these keys".

### Pros

- Duplicate keys and misplaced rests are caught statically with a precise message.
- Closed matching regains full-shape matching, with `...` the explicit opt-in to extra keys — symmetric with arrays.

### Cons

- More verbose common case: ignoring extra keys now needs a trailing `...`.

---

## 2.12 Switching to Ruby's truthiness model

### Decisions

- 🧑 ✅ Truthiness is Ruby-style: every value is truthy except `false` and `null`. This applies to the `@and`/`@or`/`@not` built-ins and `?` predicates.

### Alternatives

- 🧑 ⏪ The builtins `@and`/`@or`/`@not` are strict and return a `type_error` for non booleans. Predicates match only on exactly `true`.

### Pros

- Booleans operations return `type_error`s less frequently and are more useful. A lot more functions work as predicates.

### Cons

- If you really wanted "strict booleans", you'd now need to build them yourselves.

---

## 2.13 Refining the error payload

Refines §2.9: same general shape, more orthogonal fields, field values easier to match on, field values contain smarter contents

### Decisions

- 🧑 ✅ The error payload fields are now: `kind`, `origin`, `file` (opt), `operation`, `status`, `input`, `expected` (opt), `message` (opt).
- 🧑 ✅ Split `location` into `origin` (where the operation is *defined*) and an optional `file` (the **innermost user-code file** on the call chain).
- 🧑 ✅ `file` is `Dir.pwd`-relative, so it reads as the route from the location where `fusion` was called to the offending source code.
- 🧑 ✅ Split `status` out from `input`. `status` is `0` (a value) or `1` (an error). On `1`, `input` carries the error's bare payload, so `input` is always valid JSON.
- 🧑 ✅ `operation` now contains the failing operation's own **`@`-reference** (`@`, `@@`, `@range`, `@math.round`, `@../mod`, `@load`) or for Built-in *syntax* its own form (`|`, `.key`, `[]`, `parsing code`). Loading the top-level program file is `loading code` (not an `@`-reference).
- 🧑 ✅ An `@`-reference takes no argument, so its `input` is `null` and its `status` is always `0`. `@load` is the exception: it's a function taking a filename.
- 🧑 ✅ For *access errors* the "key" appears only once:
  - `.name` carries the static key in `operation` and the object alone in `input`
  - `[]` is generic in `operation` and echoes the key in the `input` = `[collection, key]`
  - `[=]` is generic in `operation` and echoes the key in the `input` = `[collection, key, newValue]`
- 🧑 ✅ A failure to read a file (missing file, directory given, access denied) is reported as `"operation": <the literal @-reference>`, `"input": null`, `"file": <the referring call site>`.
- 🧑 ✅ `type_error` is merged into `argument_error`. The distinction between *wrong shape* and *wrong type* didn't fit Fusion's runtime type system.
- 🧑 ✅ `expected` lists the acceptable inputs as Fusion patterns (the input matched none); an error with `expected` never also carries a `message`.
- 🧑 ✅ `internal_error` is the new catch-all for an unexpected host/interpreter failure. It's a Ruby error the engine caught rather than letting it crash the process (`origin` `interpreter` or `builtin`). It's an interpreter bug.
- 🧑 ✅ A runtime resource limit being exceeded is a separate `limit_error` (currently a stack overflow, `"stack level too deep"`): the runtime gave up because a space/time budget ran out — not an engine defect. The general name (vs `stack_error`) lets future runtime resource limits share the kind.
- 🧑 ✅ stdlib functions preemptively handle all *argument* errors. They appear atomic. No input should be able to trigger e.g. an error in a `|` operation. *Argument* errors refer to the stdlib function itself (`origin: "stdlib"`, `operation` = its `@`-reference).
- 🧑 ✅ stdlib functions are *transparent* for *inner errors*. They can't catch every possible error from inner operations, so an inner error bubbles through unchanged. The purest example is `@map`, which knows nothing about the given `f`: an error from `f` originates from `f` and simply bubbles through `map`.
- 🧑 ✅ stdlib higher-order functions (`@all`/`@map`) guard `f ? @Function` in every clause — a non-function `f` errors even on an empty collection — and `expected` shows the guard.
- 🧑 ✅ `@all` short-circuits: the first falsey item yields `false`, the rest go untested.

### Alternatives

- 🔢 ⏪ A variable `location` string embedding the file/builtin name, with the error marker living inside `input` — split into the fixed `origin` + `file`, and the `status` field.
- 🔢 ❌ Over-approximating `expected` patterns for `@join`/`@toObject` (e.g. `[_ ? @Array, _ ? @String]`) — they would match inputs that still fail, breaking "matches ⇒ acceptable"; `@all` keeps them exact.
- 🔢 ❌ `operation` = the *literal source text* of the `|`'s right-hand side. Not implementable: the text isn't available where the error is born; stamping it at `apply` would relabel inner errors bubbling *through* a function (violating §2.9 transparency); and an indirect RHS like `f` is uninformative. The producer's own `@`-reference gives the same result for a direct call and stays correct otherwise.
- 🧑 ❌ Drop `conversion_error` and have a failed conversion (e.g. `@parseNumber` of `"abc"`) return `null` (a "Maybe", as Ruby's `to_i` does). Rejected: the error payload carries more information, `| (! => null)` recovers the lenient form in one token, and forcing a catch keeps errors local — which matters with no backtraces. (A `null` would slip downstream and surface far from its cause.)
- 🧑 ❌ Base the payload path on the jail / program directory instead of `Dir.pwd`. Rejected: `Dir.pwd` gives a path usable straight from your shell; for an installed/shebang tool invoked from elsewhere, a jail-relative path would describe the program's internal layout, which you'd then have to rebase onto your own location.

### Pros

- `input` is always valid JSON as the `status` now lives in its own field
- `expected` documents the acceptable inputs as patterns a caller can reuse.
- `origin` is directly dispatchable as the variable filename now lives in its own `file` field.
- The roles of `file` and `operation` have been clarified and are much more helpful now.

### Cons

- A few `expected` patterns must reference the `@all` stdlib helper, so they aren't purely structural.

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

- 🧑 ✅ **Built-ins require `@`.** `@OP.sum`, `@Integer`, etc. A bare identifier is *only* a pattern hole; it never denotes a built-in. Built-ins cannot be shadowed by a clause's bindings — they live in a different namespace entirely.
- 🧑 ✅ **The standard library has no prefix.** `@map` reaches it directly.
- 🧑 ✅ **An `@name` reference (without leading `../`) resolves: sibling file → built-in → stdlib file → error.** First match wins. Consequently siblings can shadow a built-in or a stdlib function, but only for files in that directory (never globally).
- 🧑 ✅ **Built-in/stdlib fallback is gated on `../`, not on `/`.** Downward paths (`@dir/a`, `@util/helper`) remain eligible for the built-in/stdlib fallback; only upward paths (`@../a`) are file-only and never fall back.
- 🧑 ✅ **A bare `@`** (nothing after it) means the current file — recursion is written this way rather than by repeating the file's own name.
- 🧑 ✅ **`@ENV`** is a built-in evaluating to an object of environment variables (all string values, no parsing); read with member access (`@ENV.CI`).
- 🧑 ✅ **`@load`** is a built-in taking a filename **verbatim** (no `.fsn` appended), resolved relative to the referencing file, for runtime/non-identifier filenames. Both `@ENV` and `@load` resolve in the `@name` chain, so both are shadowable by a sibling file of that name.

### Why a single uniform chain

- Every bare `@name` follows one precedence order (sibling → builtin → stdlib), so there are no reserved names to remember and no parser carve-outs.
- `ENV` and `load` live in the builtin tier like everything else.
- Gating fallback on `../` rather than on the presence of any `/` keeps downward paths (`@util/helper`) eligible for the stdlib, which is what stdlib subpackaging needs.

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

- Built-ins are verbose (`@OP.sum` everywhere).
- Shadowing is invisible at the call site (whether `@map` is yours or the stdlib's depends on directory contents).
- A bare word that *looks* like a function reference is silently just a hole (reading an unbound one yields an error).

---

## 3.7 Bare `@` also works for inline code, not only for files

### Decisions

- 🧑 ✅ A bare `@` is the value of the current top-level **unit**: a file (previously the only case), an inline (`-e`) program, or a REPL entry.Self-recursion works in all three cases.
- 🧑 ✅ Interpreter context is not part of the identifier namespace. `:dir`/`:file`/`:self` are hidden values and not exposed as `__dir__`/`__file__`/`__self__`.

### Alternatives

- 🤖 ❌ Model inline/REPL code as a synthetic "fake file" so the existing file machinery applies — needs temp-file lifecycle or a special-cased reader, and leaves the REPL with no coherent "which file" answer.
- 🧑 ⏪ "Bare `@` = the current file" (3.2/3.6); the "no current file for self-reference" error is gone, as it can no longer occur.
- 🤖 🩹 Claude's first cut kept the self-value as an ordinary binding, so reading `__self__` returned an internal thunk and crashed serialization with a raw Ruby error; the designer caught it. Interpreter context now lives in its own channel, off the binding namespace.

### Pros

- One self-reference rule across files, inline source, and the REPL. The file path is incidental.
- No identifier-namespace pollution. Internals stay internal.

### Cons

- `__dir__` is no longer exposed.

---

## 3.8 The jail: confining `@`-resolution to a directory

### Decisions

- 🧑 ✅ `-j/--jail DIR` confines `@`-resolution to `DIR` and its subtree. It defaults to the program's directory (or cwd for `-e` and the REPL). Available in every use case, the REPL included.
- 🧑 ✅ A relative `--jail` resolves against the default jail, so `-j ..` widens to the parent; `--jail '*'` disables confinement entirely.
- 🧑 ✅ An out-of-jail target is a `reference_error` (`outside the jail`).
- 🧑 ✅ The stdlib is unaffected by the jail. However, an existing file outside the jail raises an error and prevents falling through to a built-in or the stdlib.
- 🧑 ✅ `@`-references still resolve relative to the **referencing file**; the jail only filters the resolved target, it does not move the resolution base.
- 🔢 ✅ Containment is lexical (`expand_path` normalises `..`) and confines references to a directory tree. It is **not** a security sandbox and follows existing symlinks. Fusion cannot write files, so no symlink can be planted to escape. Any encountered symlink is part of the legitimate project layout.

### Alternatives

- 🧑 💭 Resolve `@`-references relative to the **jail root** instead of the referencing file (a `--relative-to-jail` mode). Rejected: it would make `@name` mean `<jail>/name` everywhere and turn per-directory sibling-shadowing (3.6) into jail-global shadowing (project-rooted imports).
- 🤖 ❌ Resolve symlinks (`realpath`) to make the jail a hard boundary. Declined: it buys nothing here (a program that cannot write files cannot plant an escaping symlink) and a real security sandbox is tricky to build.

### Pros

- A `.fsn` program is sandboxed to its own directory by default; reaching out is explicit (`-j ..`) or an opt-out (`-j '*'`).
- The stdlib and stdin are untouched, so confinement never breaks an ordinary program.

### Cons

- Safe symlink-following rests on Fusion being unable to write files; adding a file-writing capability would mean revisiting it.

---

## 3.9 Super-reference `@@`

### Decisions

- 🧑 ✅ `@@name` (and downward `@@dir/name`) resolves `@name` while *skipping its sibling files*. It always references a builtin/stdlib and is immune to local shadowing. Bare `@@` is the special case `@@<current-file>`.
- 🧑 ✅ Inline/REPL `@@` is a `reference_error` (`no enclosing file`). There is no filename to take "super" of.

### Alternatives

- 🤖 ❌ Make `@name` never refer to its own file (so `@range` inside `range.fsn` means the stdlib function). Rejected: the override would name itself (breaking relocatability) and it adds a per-file carve-out to the resolution chain.

### Pros

- An override delegates to the original without a separate handle, and `@name` semantics are untouched.
- Relocatable: no file names itself.
- `@@name` provides a stable mechanism for error-payload patterns that must stay canonical regardless of a caller's shadows.

### Cons

- Reaches only what you shadow under your *own* name, not an arbitrary shadowed built-in.

---

# 4. Runtime and CLI

## 4.1 Runtime I/O contract

### Decisions

- 🧑 ✅ Read stdin as JSON → value `v`; compute `v | program`; print the result as JSON.
- 🧑 ✅ A final `!` produces a nonzero exit code.
- 🤖 ⏪ Empty stdin was treated as `null`. Superseded in 4.4: empty stdin means *no input*.
- 🤖 ✅ Non-JSON stdin yields `!`.

### Alternatives

- 🤖 ❌ NDJSON/streaming input mapping the program over each line (deferred).
- 🤖 ⏪ A richer error report on stderr instead of a bare nonzero exit.

### Pros

- Fusion programs are first-class Unix filters.
- `!` maps onto exit status for free.

### Cons

- No streaming; whole input must be buffered and parsed.
- 🩹 A bare `!` with nonzero exit gives little diagnostic detail. Mitigated for runtime errors by more detailed error payloads in 2.9.

---

## 4.2 No raw Ruby errors reach the user

### Decisions

- 🧑 ✅ The CLI contract already spends stdout (the result) and stderr (the error payload). There is **no third channel**, so a raw Ruby backtrace on stderr would corrupt the contract. Fusion therefore **catches every Ruby error a program can trigger and converts it to a standardized payload**.
- 🔢 ✅ Conversion happens *both* **deep** (so an error becomes catchable by other code as soon as possible) *and* at a **top-level net** (so nothing escapes). Notably `SystemStackError` becomes a regular error value `stack_error` on stderr.
- 🧑 ✅ The internal "assertions" (`raise Unreachable`) are a deliberate exception. Reaching them is an interpreter bug. Interpreter bugs should surface and are allowed to violate our CLI contract.
- 🧑 ✅ The old `FUSION_DEBUG` env var (which wrote to stderr via `warn`) is removed entirely.

### Alternatives

- 🤖 ❌ A top-level net only — rejected because a mid-program Ruby error would then become a final result rather than a catchable `!`.
- 🤖 💭 An `internal_error` kind for the invariant asserts. Rejected, because interpreter bugs shouldn't be catchable and shouldn't be a seemingly regular final result.

### Pros

- The CLI contract holds unconditionally. A program can even crash the interpreter's host language via infinite recursion and the user still gets a clean JSON payload and exit `1`.

### Cons

- Implementation effort.
- Might hide valuable debugging information. However, the "top-level net" could be made opt-out.
- The `location` for a stack overflow is only `"interpreter"`. No single owning file is knowable at that point.

---

## 4.3 Runtime errors and lenient JSON serialization

### Decisions

- 🔢 ✅ To serialize values without a valid JSON representation, we introduce "lenient serialization". Values without JSON representation get turned into string representations (`"<function>"` and `"<Infinity>"`/`"<-Infinity>"`/`"<NaN>"`).
- 🧑 ✅ The remaining data structure gets preserved.
- 🔢 ✅ Runtime errors (`ErrorVal#runtime?`) get serialized leniently by default, so their info isn't obscured by a `serialization_error`.
- 🤖 ⏪ The stdlib doesn't produce runtime errors. Reverted in §2.13. stdlib errors now get marked as runtime errors.
- 🧑 ⏪ All stdlib functions use `@sanitize` to mimick the lenient JSON serialization and preserve as much info as possible. Obsoleted by §2.13. However, `@sanitize` is kept as a utility.
- 🧑 ✅ Ordinary values and user errors are serialized strictly to avoid surprising type conversions. If they fail to serialize, they get turned into a runtime `serialization_error` and will subsequently get serialized leniently.

### Alternatives

- 🤖 ❌ The standard library could create real "runtime errors" via a dedicated `@raise` primitive. Declined: it offers little over the `!` prefix and would let *any* code create runtime errors. Instead a stdlib `!{…}` is marked runtime by its construction *location* — the same benefit (lenient serialization, a consistent shape, call-site `file`), confined to stdlib source.
- 🧑 ❌ Runtime errors also serialize strictly by default. Rejected, because this would turn too many errors into a `serialization_error` and would lose too much information.
- 🧑 💭 All errors serialize leniently by default. Rejected, because this hides real errors (e.g. `NaN` or a function as a result) behind an automatic type conversion.

---

## 4.4 CLI use cases and I/O modes

Extends the single runtime contract of 4.1 into three use cases and four ways an
error value can cross the boundary.

### Decisions

**Use cases:**

- 🧑 ✅ The CLI supports three use cases: **pipe** (apply the program to one input, §4.1), **stream** (apply it to each line of an NDJSON stream), **repl** (interactive).
- 🧑 ✅ **pipe**: Compute `stdin | program`. Empty or whitespace-only stdin means *no input*: return `program` (evaluated on load). So a `.fsn` file doubles as enriched JSON (computations, `@ENV`, `@`-references).
- 🧑 ✅ **stream**: Conforms to NDJSON. Keeps errors in-band and continues the stream. Always exits `0`.
- 🧑 ✅ A blank **stream** input line is echoed as a blank output line (no computation); `--skip-blank-lines` drops it instead.
- 🧑 ✅ **repl**: Can evaluate expressions. Also allows an assignment statement: `identifier = expression`.
- 🤖 ✅ A command-line misuse (unknown flag, more than one use case, conflicting input/output modes, unsupported mode combination, missing program, `-!` with empty stdin) is plain usage text on stderr with exit `1`, never a payloaded error. Most are caught during option parsing, `-!` with empty-stdin while reading input.

**I/O modes** — how an error is marked crossing the boundary; `--input` and `--output` are independent:

TODO: Under `-!` the input is the error payload, so empty stdin is a usage error (nothing to mark).

- 🧑 ✅ Four modes: **unix** (asymmetric, Unix filter) and **bang** / **array** (`[0, value]` / `[1, payload]`), **object** (`{"value": _}` / `{"error": _}`).
- 🧑 ✅ **unix**: input is `stdin` + `-!` flag, output is `value → stdout` + `exit 0` OR `error → stderr` + `exit 1`. stdin/stdout/stderr are always pure JSON.
- 🧑 ✅ **bang**: shortest encoding, errors are simply a `!` prefix and thus not valid JSON.
- 🧑 ✅ **array**: always valid JSON, error encoded via envelope: `[0, value]` / `[1, payload]`.
- 🧑 ✅ **object**: always valid JSON, error encoded via envelope: `{"value": _}` / `{"error": _}`.
- 🧑 ✅ `-!` requires stdin. With absent stdin, it's a usage error.
- 🧑 ✅ pipe supports all four modes; stream all but unix (so errors stay "in-band"); repl has none.
- 🧑 ✅ Defaults: pipe = unix/unix, stream = array/array.
- 🤖 ✅ A malformed `array`/`object` input envelope is a catchable `argument_error` at `location: "input"` (the array tag must be exactly the integer `0`/`1`), flowing into the program like any input error.

**REPL:**

- 🧑 ✅ An entry is an **expression** (evaluated and printed) or an **assignment statement** `identifier = expression` (evaluated, printed, and bound for later entries).
- 🧑 ✅ An entry is evaluated only once it parses as a whole statement/expression. An incomplete or invalid buffer keeps the entry open to finish or correct.
- 🧑 ✅ Error results can also get bound to an identifier via the **assignment statement**. When accessing them, they'll propagate regularly.
- 🤖 ✅ Results print leniently (a function as `"<function>"`, etc.); entries report errors at `location: "code <inline>"`, like `-e`.
- 🤖 ✅ Results go to stdout; the prompt and echoed input go to stderr (like a shell prompt), so stdout is a clean stream of results.
- 🧑 ✅ `stderr` decorations are styled. Styling never touches `stdout`.

### Alternatives

- 🧑 ⏪ pipe was the unconditional default — now repl on a bare `fusion`, otherwise pipe.
- 🤖 ⏪ stream defaulted to `bang`/`bang` — now `array`/`array`, since `bang` lines aren't valid JSON.
- 🤖 ⏪ Empty input was the value `null`, and input could also come from an inline `[json-input]` argument — now empty means *no input* and input is stdin-only.
- 🧑 ⏪ Empty stdin under `-!` supplied `!null` — now a usage error, since there is no payload to mark.
- 🤖 ⏪ Blank `stream` lines were silently skipped — now echoed by default, dropped with `--skip-blank-lines`.
- 🧑 ⏪ REPL accepts only statements (the original "introduces a single statement" sketch); widened so a bare expression is also an entry.
- 🧑 ⏪ Statements terminated by `;` (so several could share a line); dropped — completeness is decided by parsing, so a line that parses is submitted and no terminator is needed.
- 🤖 ⏪ A statement does **not** bind an error result (mirroring pattern binders, which never capture an error). Flipped: a statement is an assignment, not a pattern match; binding an error is harmless and needs no special case.
- 🤖 ❌ unix mode for stream — one exit code and one stdout/stderr pair cannot mark errors per record.
- 🤖 💭 A single `--mode` controlling both directions — input and output modes are deliberately independent.

### Pros

- One small flag surface spans first-class Unix filters (pipe), bulk processing (stream), and interactive exploration (repl).
- Errors cross the boundary in whatever shape the surrounding tool wants — exit code, `!` sentinel, or envelope — with input and output chosen independently.
- The REPL reuses the whole language: an entry is just an expression, with assignment the one addition, and a bound error propagates like any other value-or-error (no carve-out).
- A program with no stdin doubles as enriched JSON (computation, `@ENV`, `@`-references), and `--stream` emits valid NDJSON.

### Cons

- Four error-marking modes are more surface than the original single unix contract.
- Completeness-by-parsing submits a complete-but-maybe-unintended line (e.g. `x = 5` when more was meant) as-is.
- Empty stdin no longer means the value `null`; to feed `null` you pipe the literal `null`.

---

# 5. Misc

## 5.1 No operator sugar (deferred)

### Decisions

- 🧑 ⏪ No infix `+ - * / == && …` until the core semantics are settled. Superseded by §5.6. Syntax sugar is now implemented.
- 🧑 ✅ Arithmetic, comparison, and boolean operations are built-in functions reached via an `@-reference`, e.g. `[a, b] | @OP.sum`.

### Alternatives

- 🤖 ⏪ Provide infix operators as sugar desugaring to the built-ins immediately.

### Pros

- Keeps the core grammar tiny and uniform while semantics are being settled.
- Everything is visibly "just application."

### Cons

- Arithmetic-heavy code is verbose and harder to read (`[n, [n, -1] | @OP.sum | @fact] | @OP.product` vs. `n * fact(n-1)`).

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
- 🤖 ✅ `keys` must be a builtin: pattern matching can pull *known* object keys but cannot enumerate *unknown* ones, so iterating an object of unknown shape is impossible without it.

### Alternatives

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

---

## 5.5 Reworking the builtins and standard library

### Decisions

- 🧑 ✅ Bundle the most important arithmetic and logic operations together into a single `@OP` reference.
- 🧑 ✅ Make the `stdlib` as orthogonal as possible to `@OP`.
- 🧑 ✅ Higher-order helpers (`map`, `filter`, `reduce`, `compact`, `flatten`, `any`, `all`) are implemented via recursion in Fusion, not hidden in Ruby. They work for both arrays and objects where possible.
- 🧑 ✅ Provide access to more advanced mathematical operations in `@math`.
- 🧑 ✅ Where possible, builtins and stdlib functions are n-ary instead of binary.

### Alternatives

- 🤖 ⏪ Keep every operator as its own builtin (the §5.3 set). Superseded: bundling into `@OP` gives a directory one place to shadow them all.
- 🤖 ❌ Resolve `@OP` **dynamically** (at the call site) so stdlib helpers follow a foreign override. Rejected: it breaks per-directory confinement.

### Pros

- By bundling operators into `@OP`, the presence of an `OP.fsn` file will immediately become a warning sign that core operations might behave differently in a given directory.
- By making the `stdlib` orthogonal to `@OP`, a shadowed `@OP` will not create footguns where `stdlib` functions still refer to the original implementation.

### Cons

- Not all operators with syntax sugar have been grouped into `@OP`. Exceptions are the structural operators `@map`, `@filter`, `@reduce`.
- The few helpers that still reference `@OP` (currently only `@range`) will ignore `@OP` overrides. To make them aware of `@OP` overrides, create a copy of their `stdlib` source code next to your `OP.fsn`.
- The native way of writing division `[a, b | @OP.negate] | @OP.product` is numerically incorrect and might produce a double rounding error. For the numerically correct division you have to use `@math.divide`.

---

## 5.6 Syntax sugar

Implements the infix-operator sugar deferred in §5.1. Additionally adds `map` / `filter` / `reduce`
pipe operators. Promotes `[]`/`[=]` to core syntax. Desugaring is purely syntactic. The only new
runtime node is the `[=]` setter.

### Decisions

- 🔢 ✅ Precedence, tightest→loosest: postfix (`.` `[]` `[=]`) → unary prefix (`! - / ~`) → pipe (`| |: |? |+`) → multiplicative (`* / % //`) → additive (`+ -`) → `??` → `==` → `&&` → `||`. Pipe binds just under unary, tighter than every value operator.
- 🧑 ✅ The array/object setter gets promoted to core syntax `container[key = value]`. The `@set` builtin is removed.
- 🧑 ✅ The getter `container[key]` stays core syntax instead of becoming syntax sugar for `@get`. The `@get` builtin is removed.
- 🧑 ✅ A maximal run of `+`/`-` folds to one `[terms] | @OP.sum`; a run of `*`/`/` to one `[terms] | @OP.product`. `-` operands are negated, `/` operands inverted.
- 🧑 ✅ `-` is always an operator; the lexer emits no negative-number literals.
- 🧑 ✅ A `-` before a bare numeric literal folds into a negative literal (in expressions and patterns alike); any other operand becomes `operand | @OP.negate`. In a pattern, `-` may only precede a numeric literal.
- 🧑 ✅ `/` never folds to a literal: `a / 2` → `[a, 2|@OP.invert] | @OP.product`, so `/0` stays a runtime `math_error`.
- 🧑 ✅ A single `/` is a path separator only inside a file-reference path; elsewhere it is division/invert. `@a/b` is the path `a/b`; `@a / b` (any space around the slash) is `@a` divided by `b`.
- 🧑 ✅ The lexer emits a `path` token only immediately after `@`/`@@`, tight: no space after `@`/`@@`, interior slashes abutting their segments. A path starts with an identifier or `..`, never a lone `.` (so `@.map` is `.map` access on bare `@`). Bare `@`/`@@` when no tight path follows.
- 🧑 ✅ Whitespace between `@`/`@@` and its path is no longer allowed (`@ name` is a syntax error).
- 🧑 ✅ Runs of `==`/`&&`/`||` fold n-ary to `@OP.equal`/`@OP.and`/`@OP.or`.
- 🧑 ✅ `??` is its own precedence level, tighter than `==` (compare produces an ordinal that `==` then tests; a boolean can't be compared).
- 🧑 ✅ `xs |: f`, `xs |? f`, `xs |+ f` desugar to `{"c": xs, "f": f}` piped into `@map`/`@filter`/`@reduce`.

### Alternatives

- 🤖 ⏪ Lex negative-number literals (JSON-style). Rewound: `a-3` would be ambiguous between the literal `-3` and subtraction.
- 🤖 ❌ Desugar every `-x` to `x | @OP.negate`, dropping literal negatives. Rejected: `-5` should stay a plain literal, not an `@OP`-routed computation.
- 🤖 ❌ Assemble the path in the parser so `@a / b` is also the path `a/b` (divide via `(@a) / b`). Rejected: a spaced `@a / b` should read as division like every other operator.

### Pros

- Giving `pipe` the tightest precedence keeps the "useful reading" paren-free: a pipe's RHS has to always be a function and arithmetic never yields one, so `x|@f + 1` can only sensibly mean `(x|@f) + 1`.

---

## 5.7 Comparison operators `<` `<=` `>=` `>`

Extends the §5.6 sugar with comparisons; moves the comparison readers from the stdlib
into `@OP`.

### Decisions

- 🧑 ✅ `a < b` is sugar for `[a, b] | @OP.compare | @OP.lt`; likewise `<=` / `>` / `>=` via `@OP.lte` / `@OP.gt` / `@OP.gte`.
- 🧑 ✅ The readers `lt` / `gt` / `lte` / `gte` are `@OP` members: they map an exact `@OP.compare` result (`-1`/`0`/`1`) to a boolean, pass `null` through (a partial order's "incomparable"), and reject anything else.
- 🤖 ✅ The comparisons sit at the ordering level with `??`: binary, left-associative, no folding — `a < b < c` compares a boolean and errors at runtime.

### Alternatives

- 🧑 ⏪ The readers as stdlib helpers (`@lt`, `@gt`, `@lte`, `@gte`), deliberately immune to an `@OP` override. Superseded: as members they live where the sugar points, and the override story stays one object.
- 🧑 ❌ Four direct pair-comparing members (`[a, b] | @OP.lt`); rejected: four coupled orderings an override would have to keep consistent with `compare`.

### Pros

- `compare` stays the single ordering primitive; the four operators are thin readers of its result.
- Overriding `compare` alone reskins `a < b` — both desugared steps resolve through the per-directory `@OP`.

### Cons

- Comparisons don't chain: `a < b < c` is not `a < b && b < c`.

---

## 5.8 Stdlib charter

How stdlib functions are written; §5.2 (one function per file) and §5.5 (orthogonality
to `@OP`) set the frame.

### Decisions

- 🧑 ✅ Stdlib functions never reference `@OP`. `@range` is the grandfathered exception; no new ones.
- 🧑 ✅ Stdlib functions may build on other stdlib functions.
- 🧑 ✅ Stdlib and example code uses the map-pipe sugar `|:` `|?` `|+` — except that `map`/`filter`/`reduce` write their own recursion as an explicit self-recursive `… | @`.
- 🧑 ✅ Validation is structural, in the clause patterns themselves; a positive guard clause (`input ? (…) => computation`) is reserved for conditions patterns cannot express, like `@concat`'s "every element is a string".

### Alternatives

- 🤖 ⏪ Every stdlib function as positive guard → nested computation → error fallback. Rewound: plain clauses read better wherever the condition is structural — pattern matching is the language's strength.

### Pros

- An `OP.fsn` reskin is never silently bypassed by stdlib internals — there is nothing to bypass.
- The stdlib doubles as idiomatic example code.

### Cons

- Helpers deliberately ignore a local `@OP` override; a reskinning caller must vendor them (§5.5, roadmap).

---

## 5.9 Object construction and destructuring

### Decisions

- 🧑 ✅ `@entries` destructures an object into its `[key, value]` entries, in insertion order; `@toObject` builds an object from such entries, later duplicate keys winning. They are inverses: `obj | @entries | @toObject` is `obj`.
- 🔢 ✅ The names complete the JS trio `keys`/`values`/`entries`; `toObject` names its result like `toString`, so a pipe ends in what it produces.
- 🧑 ✅ Both are stdlib, not builtins: the `[=]` setter makes `toObject` expressible in Fusion, so the Tier-0 rule (§5.3) moves it out of the interpreter.

### Alternatives

- 🤖 ❌ `fromEntries` (the JS couple): in a postfix pipe it names the input you already see, not the result. `fromPairs`/`toPairs` (lodash): "pair" already means any two-element array here.

### Pros

- Computed keys become first-class: destructure, transform the entries, rebuild.
- `@map`/`@filter` reduce their object case to the array case via `@entries`.

### Cons

- An object pass builds an intermediate entries array.

---

## 5.10 The `@Collection` predicate

### Decisions

- 🧑 ✅ `@Collection` is a type predicate, true exactly for arrays and objects.
- 🧑 ✅ All type predicates stay builtins, even derivable ones like this.
- 🧑 ✅ `expected` patterns use `_ ? @Collection` wherever the acceptable set is exactly "array or object"; alternatives that couple the collection kind to another slot's type (`[]`, `[=]`) stay split, keeping "matches ⇒ acceptable" exact.

### Alternatives

- 🤖 ❌ A stdlib `Collection.fsn` (it is derivable). Rejected: the type predicates stay one uniform builtin family.

### Pros

- The polymorphic collection functions state their contract in one pattern (`c ? @Collection`, `"c": _ ? @Collection`).

### Cons

- Where the array/object alternatives differ in a coupled slot, both spellings coexist.

---

## 5.11 The matrix and vector modules

TODO

---

## 5.12 Bare-array @all and @any

TODO

---

## 5.13 Error-as-false guards

TODO
