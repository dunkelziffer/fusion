# Roadmap and open questions

## 1. Ergonomics: the most-wanted improvements

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

**`@`-namespace resolution polish.** Confirm and document `@std/` as the one magic
prefix; decide on project-root confinement (sandboxing) for `@../` escapes; consider a
configurable library search path.

## 2. Error model

**Payloaded errors.** `!` is currently opaque, conflating divide-by-zero, type errors,
and non-exhaustive matches. A payload (`!"divide by zero"`, or a structured
`{"error": ...}`) would aid debugging and allow selective handling. This is a real
expansion to design carefully, not bolt on.

**Better diagnostics.** `FUSION_DEBUG` exists for file/parse errors; extend principled
diagnostics to runtime `!` origins (where did this error first arise?).

## 3. Standard library completion

Populate Tier 1 (written in Fusion): `filter`, `reduce`/`fold`, `reverse`, `head`,
`tail`, `last`, `init`, `take`, `drop`, `zip`, `flatten`, `member`, `find`, `all`,
`any`, `count`; comparison derivatives `lessEq`, `greaterThan`, `greaterEq`,
`notEquals`; object helpers `entries`, `get`, `set`, `merge`; an `if` helper. This is
also the best stress test of whether the language is pleasant to *write* in, not just
to implement.

## 4. Runtime and tooling

- **Streaming I/O** (NDJSON): map a program over a stream of JSON values.
- **Sandboxed reference resolution** confined to a project root.
- **A real CLI** beyond the prototype (`-e`, file, stdin) with better error reporting.
- **A faster implementation** once semantics are frozen (the current `fusion.rb` is a
  proof of concept, verified by a Python oracle, not optimized).

## 5. Open semantic questions to settle

- Should `_` strictly exclude `!` (current) or match literally anything? The current
  asymmetry is what makes propagation clean; confirm it is acceptable long-term.
- Should `null` ever be "sticky" like `!`? (Almost certainly not — that is `!`'s job.)
- Numeric tower: keep int/float split, or move to a single number type / arbitrary
  precision? Affects `divide`, `floor`, `equals`, and the `Integer`/`Float` predicates.
- Function equality: `equals` on two functions — always `false`, or `!`? (Function
  equality is undecidable beyond trivial identity.)

## 6. Bigger experiments

**Destructuring functions (homoiconicity).** Treat a function as a list of
`(pattern, output)` clause-pairs and pattern-match on it, enabling macros and function
transformers with the same matching machinery. Naïve homoiconicity is blocked by a
fundamental constraint: a pattern contains unbound binders, so it is not an ordinary
value — making patterns first-class would introduce a fourth kind of value and break
the "exactly three ingredients" design choice. The clean path is therefore explicit,
opt-in reflection (`reflect : function → data`, `reify : data → function`) representing
patterns as reflective AST objects, so normal code keeps functions opaque and the
three-ingredients model intact. High payoff (metaprogramming), moderate disruption.

**Running functions backwards (relational mode).** Given an output, find an input —
unification and search, à la Prolog/miniKanren. Clean only for invertible functions;
hopeless for many-to-one. Would change Fusion from functional to relational and needs
backtracking search. The most exciting and most disruptive possible direction; best
pursued as a separate mode or sibling project rather than folded into the core.

**A static checker.** Because "types" are predicates, a optional static layer could
attempt to verify predicate-guarded clauses and exhaustiveness without changing the
dynamic semantics. Speculative.
