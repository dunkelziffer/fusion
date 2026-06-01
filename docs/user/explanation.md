# Explanation

*This is **explanation** in the [Diátaxis](https://diataxis.fr/) sense:
understanding-oriented discussion that provides context and answers "why?". It is not
a lesson, a recipe, or a spec — for those see the [Tutorial](./tutorial.md),
[How-to guides](./how-to-guides.md), and [Reference](./reference.md). This article may
hold opinions and approach the subject from several angles. For the formal decision
ledger (who decided what, alternatives, trade-offs) see the
[Design documentation](./design.md).*

---

## What Fusion is, in one breath

Fusion is "functional JSON": take JSON — its atoms, arrays, and objects — and add one
more ingredient, the function. Keep the count of concepts brutally small. From those
pieces, recover everything a small language needs: branching, looping, types,
modules, and error handling. The whole design is an exercise in *not adding things*
and discovering that the pieces you already have are enough.

---

## Why only three ingredients

Most languages accrete features: statements, loops, conditionals, classes,
exceptions, a type system, a module system, each with its own syntax. Fusion's bet is
that almost all of that is unnecessary if your three composite ingredients — arrays,
objects, functions — are chosen well and made to compose.

The discipline pays a recurring dividend. Again and again, a feature that would
normally be its own language construct turns out to be expressible with what already
exists:

- An **`if`** is a function with `true` and `false` clauses.
- A **`for` loop** is recursion that pattern-matches a list down to `[]`.
- A **type** is a predicate function attached with `?`.
- A **module** is a file, and an import is a reference to that file's value.
- **Error propagation** is just how application treats the error value.

None of these required new syntax. That is the aesthetic core of the language: when
you feel the urge to add a construct, look harder at the three you have.

---

## Why functions take exactly one argument

This looks like a severe restriction and is actually a simplification that makes
everything else line up. With exactly one input and one output:

- **Application has one shape:** `value | function`. There is no argument list, no
  call syntax, no arity to track. A pipeline `a | f | g | h` reads like a sentence.
- **Multi-argument needs are met by data:** pass an array `[a, b]` or an object
  `{"f": ..., "xs": ...}`. The "arguments" become a value you can also store, inspect,
  and destructure — there's no separate notion of "argument tuple."
- **Pattern matching has one job:** match the single input. A function's clauses are
  just alternative shapes that one input might have.

The cost is verbosity in arithmetic (`[a, b] | @add` instead of `a + b`) and a little
ceremony for multi-argument library functions. The first is a candidate for later
syntactic sugar; the second is mild. In exchange, the evaluation model is almost
trivially simple, which is exactly what you want in a language meant to be small.

---

## Why bare words are "holes"

The keystone trick is that a bare identifier means *bind* in a pattern and *read* in
an expression. This works because JSON has no bare identifiers — strings are quoted,
so an unquoted word is an unused syntactic slot. Fusion claims that slot for variables.

The consequence is a pleasing symmetry: a pattern and a result are mirror images.
`[a, b] => [b, a]` reads almost pictorially — the same names appear on both sides,
filled from the input on the left and poured into the output on the right. You never
write "get element 0, get element 1, now build a new array"; you draw the shape you
have and the shape you want, and the names connect them. Destructuring stops being an
operation and becomes a *correspondence*.

---

## Why pattern matching is the only control flow

Because functions dispatch by matching their single input against ordered clauses,
"choosing what to do" and "taking apart the data" are the same act. A clause is
simultaneously a condition (does this shape match?) and a binding (here are the
pieces). This collapses two things most languages keep separate — `switch` and
destructuring assignment — into one.

Once control flow *is* matching, recursion naturally absorbs iteration. A list is
either `[]` or `[head, ...tail]`; those two shapes are the two clauses of almost every
list function; the recursive call shrinks the input until the base shape matches. The
"loop" is invisible because it isn't a loop — it's a function rediscovering a smaller
version of its own input.

The one wrinkle this introduces: what should happen when *nothing* matches? Fusion's
answer is `null` by default, which keeps exploration forgiving, with an opt-in `_ =>
!` to make a function strict. That choice deserves its own discussion (below).

---

## Why `null` and `!` are different things

Many languages overload one value (`null`, `nil`, `None`) to mean both "legitimately
nothing here" and "something went wrong." Fusion splits them deliberately:

- `null` is ordinary data. It matches binders and `_`, can be stored, compared, and
  passed around. It means *absence*.
- An error is `!` followed by a **payload** (any value). It means *failure*, and the
  payload says what kind. `!"divide by zero"`, `!42`, `!{"kind":"missing_key",...}`,
  and bare `!` (which is shorthand for `!null`) are all errors with different
  payloads.

The split earns its keep in how the two behave under application. `null` flows like
any value. An error, by contrast, **propagates**: feed it to any function and you
get the *same* error back (payload preserved), unless that function explicitly opts
in to catch it with an error pattern. So a long pipeline short-circuits at the
first failure and carries the original error to the end — the ergonomics of
exceptions or a `Result` type, but with no new machinery, falling out of two small
rules (errors match only error patterns; applying a function to an error returns
that error unless caught).

Two design decisions sharpen this. First, the error's payload is preserved
through propagation, not just the *fact* of an error — so by the time you reach
a catch site, you still know what happened. Second, **errors are not
first-class values**: at any moment of execution there is either a normal value
in motion or an error in motion, never both. An error appearing where a value
is expected always propagates — it cannot sit inside an array, be compared
with `@equals`, or be examined by `@Integer`. To do anything with an error's
payload you must catch it first (with an `!pat` clause), which yields a normal
value you can then inspect. This is what keeps propagation uniform: there are
no exceptions, no "but predicates examine errors as data" carve-outs to
remember.

This propagation behavior was, notably, *not* something we got right on paper. We
originally tied it to strictness ("a strict function propagates errors"), and the
implementation proved that wrong — see the next section.

---

## What the prototype taught us (and why that matters)

Building the interpreter changed the design. The clearest case: we had claimed
"strict ⇔ error-propagating," reasoning that a strict function's `_ => !` clause would
re-emit any incoming error. The running code showed this was false. We had *also*
decided that `_` rejects `!` (so that a catch-all never silently swallows an error as
data). But if `_` rejects `!`, then a strict function's `_ => !` clause can't fire on
an `!` input — so it fell through to `null` instead of propagating. Two rules we liked
independently contradicted each other.

The fix made the language simpler, not more complex: propagation became a property of
*application itself* (any function returns `!` for an `!` input unless it explicitly
matches `!`), fully independent of strictness. "Strict" went back to meaning only
"error on no match."

A later refinement sharpened the same rule. With payloaded errors and clauses that
catch *specific* error shapes (e.g. `!{"kind": "parseNumber"} => 0`), an error of
a *different* shape would silently fall through to the function's lenient default
of `null` — exactly the silent-swallow bug the propagation rule was meant to
prevent. The fix is small: the lenient `null` default only applies to non-error
inputs; an unmatched error propagates. Same lesson: rules that look fine separately
need to be checked against actual value flow.

The lesson is the ordinary one about prototypes, but worth stating: a specification
can be internally inconsistent in ways that feel fine until values actually flow
through it. The interpreter is not just an implementation of the design; it was an
instrument *for* the design.

---

## Why a file is exactly one value

Earlier drafts had a program be a list of top-level `name = value` bindings plus a
"main" expression — essentially a second little language stacked on top of the
expression language, with its own scoping rules (the bindings had to be mutually
recursive, a `letrec`). The "one value per file" rule deletes all of that. The
outermost layer of a program is now the same kind of thing as every inner layer: a
value. A program is just a file whose value happens to be a function, and running it
is `STDIN | thatFunction`.

This also resolved the module system for free. If a file is a value, then referencing
a file *is* importing a value — no separate `import` construct, no namespace syntax.
The directory tree becomes the namespace. The standard library is just a folder of
files. One mechanism (`@`-references) now does top-level structure, modules, and
library delivery — and, in the current design, built-in access too: `@add` and
`@Integer` are looked up through the very same `@name` machinery as files. A bare
`@name` checks for a sibling file, then a built-in, then a standard-library file, so
your own files can locally shadow a built-in or a stdlib function without affecting
any other directory. The cost of folding built-ins into `@` is that a bare word like
`add` is no longer the built-in — it is only ever a pattern hole — so built-ins must
always be written with `@`.

There is a real cost to "one value per file," and it is honest to name it: with one
anonymous value per file and no local binding form, a function can only name itself or
its siblings through the *filesystem*. Recursion works (a bare `@` inside a file means
"this file"), but a small recursive *helper* that doesn't deserve its own file has
nowhere to live. This tension — call it "anonymous local recursion is awkward" — keeps
resurfacing, and it is the strongest argument for eventually adding a single
local-binding form. We have resisted so far, because it would be the first genuine new
construct.

---

## Why references are lazy

If `@`-references resolved eagerly (when a file loads), then a file referencing itself
would loop forever before it could ever run. Lazy resolution — resolve a reference
only when it is actually used — is what makes self-recursion and mutual recursion
possible at all. It is not a performance nicety; it is load-bearing for the whole
recursion story. Memoization on top means a referenced file is evaluated once and
shared, so diamond-shaped dependencies are cheap and a referenced-but-unused file is
never loaded.

A side effect is that *data* cycles (files whose values point at each other directly,
not through a function) are non-productive — there's no pattern match to bottom out
on. The runtime detects the cycle and yields `!` at that point, while keeping whatever
productive structure surrounds it.

---

## The roads not taken (and one we're still tempted by)

Two ideas were explored and deliberately set aside, both documented in the design doc.

**Operator sugar.** We could write `a + b` and desugar it to `[a, b] | @add`. We rolled
this back early to keep the core honest, with the explicit intent to reintroduce it
once the semantics were settled. It is a pure ergonomics layer; it changes nothing
underneath.

**Destructuring functions.** The tantalizing one. Since a function literal is visibly
a list of `pattern => output` clauses, could we pattern-match *on a function*, taking
it apart as data? That would give Lisp-like metaprogramming with the same matching
machinery — and, in its wildest form, the ability to run functions *backwards* (given
an output, find an input), which is logic programming. We kept it out of the grammar
because the clean version requires representing patterns as data (a function's pattern
contains unbound binders, so it isn't an ordinary value), and the wild version would
turn Fusion from a functional language into a relational one. It remains the most
interesting possible future for the language, and the most disruptive.

---

## How the four documentation types relate here

If you came here to *understand*, you're in the right place. If while reading you
found yourself wanting to *try* something, the [Tutorial](./tutorial.md) will teach it
to you by hand; if you wanted to *accomplish* something specific, the
[How-to guides](./how-to-guides.md) have the recipe; if you wanted to *check* an exact
rule, the [Reference](./reference.md) states it precisely. Keeping those needs
separate is itself a small instance of the same principle the language follows: a few
clear kinds of thing, each doing one job, composed rather than blended.
