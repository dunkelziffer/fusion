# Fusion roadmap

Tracked future work and open questions. Decisions that have already been made
live in [design.md](./design.md); this file is only for things still ahead.

---

## 1. Ergonomics: the most-wanted improvements

**Operator sugar (planned).** Reintroduce infix `+ - * / % == != < <= > >= && || !`
and string `++`, desugaring to the existing built-ins over pairs. Pure ergonomics,
no semantic change. This is the single biggest readability win available and was
always intended. Open question: exact precedence table and how it interleaves with
`|` and `=>`.

**`@`-namespace resolution polish.** Decide on project-root confinement
(sandboxing) for `@../` escapes; consider a configurable standard-library search
path; consider tooling to surface *which* target a given `@name` resolves to in
a directory, since shadowing is invisible at the call site.

---

## 2. Error model

**Better diagnostics.** `FUSION_DEBUG` exists for file/parse errors; extend
principled diagnostics to runtime error origins (where did this error first
arise?). One option: attaching a source position to the payload (an extra
`"at": "file.fsn:L:C"` field) when `FUSION_DEBUG` is set.

**Stack traces** *(deferred)*. A propagated error tells you what happened, but
not the chain of function applications it passed through. A capped trace
(last N frames, accessible as an extra payload field, opt-in via env) would
help in deep pipelines.

---

## 3. Standard library completion

Populate Tier 1 (written in Fusion): `filter`, `reduce`/`fold`, `reverse`,
`head`, `tail`, `last`, `init`, `take`, `drop`, `zip`, `flatten`, `member`,
`find`, `all`, `any`, `count`; comparison derivatives `lessEq`, `greaterThan`,
`greaterEq`, `notEquals`; object helpers `entries`, `get`, `set`, `merge`; an
`if` helper. This is also the best stress test of whether the language is
pleasant to *write* in, not just to implement.

---

## 4. Runtime and tooling

- **Streaming I/O** (NDJSON): map a program over a stream of JSON values.
- **A faster implementation** once semantics are frozen.

## 5. Open semantic questions to settle

- Numeric tower: keep int/float split, or move to a single number type /
  arbitrary precision? Affects `divide`, `floor`, `equals`, and the
  `Integer`/`Float` predicates.
- Function equality: `equals` on two functions — always `false`, or an error?
  (Function equality is undecidable beyond trivial identity.)

---

## 6. Bigger experiments

**Destructuring functions (homoiconicity).** Treat a function as a list of
`(pattern, output)` clause-pairs and pattern-match on it, enabling macros and
function transformers with the same matching machinery. The clean path is
explicit, opt-in reflection (`reflect : function → data`,
`reify : data → function`) representing patterns as reflective AST objects, so
normal code keeps functions opaque and "three ingredients" intact. High payoff
(metaprogramming), moderate disruption.

**Running functions backwards (relational mode).** Given an output, find an
input — unification and search, à la Prolog/miniKanren. Clean only for
invertible functions; hopeless for many-to-one. Would change Fusion from
functional to relational and needs backtracking search. The most exciting and
most disruptive possible direction; best pursued as a separate mode or sibling
project rather than folded into the core.

**A static checker.** Because "types" are predicates, an optional static layer
could attempt to verify predicate-guarded clauses and exhaustiveness without
changing the dynamic semantics. Speculative.
