# Fusion roadmap

Tracked future work and open questions. Decisions that have already been made
live in [design.md](./design.md); this file is only for things still ahead.

---

## 1. Ergonomics

**Operator sugar** *(planned)*. Introduce infix `+ - * / % == != < <= > >= && || !`
and string `++`, desugaring to the existing built-ins over pairs. Pure ergonomics,
no semantic change. This is the single biggest readability win available and was
always intended. Open question: exact precedence table and how it interleaves with
`|` and `=>`.

**Exposing the current call site** *(use case found; needs a sigil)*. The
interpreter tracks the current `:file`/`:dir`/`:call_site` as internal context,
unreadable from a program. User code should be able to mimick our *standardized*
error payloads. It needs access to `:file` for that.

---

## 2. Error model

**Stack traces** *(deferred)*. A propagated error tells you what happened, but
not the chain of function applications it passed through. A capped trace
(last N frames, accessible as an extra payload field, opt-in via env) would
help in deep pipelines.

---

## 3. Standard library completion

Populate Tier 1 (written in Fusion). Done so far: `filter`, `reduce`, `compact`,
`flatten`, `any`, and the comparison operators `eq`/`lt`/`gt`/`lte`/`gte`. Still
ahead: `reverse`, `head`, `tail`, `last`, `init`, `take`, `drop`, `zip`, `member`,
`find`, `count`, `notEquals`; object helpers `entries`, `merge`; an `if` helper.
This is also the best stress test of whether the language is pleasant to *write*
in, not just to implement.

---

## 4. Runtime and tooling

- **A faster implementation** once semantics are frozen.
- **`fusion --stdlib-path`** *(planned)*. Print the absolute path of the bundled
  standard library so a user can find, read, copy, or symlink its `.fsn` files —
  e.g. to make a derived helper like `@compact` follow a local `@OP` override:
  `cp "$(fusion --stdlib-path)/compact.fsn" .`. This is the one ergonomics gap in the
  "reskin the operators" workflow (see how-to-guides). Needs a stable path: on a
  versioned install the returned directory changes across upgrades, which dangles
  any symlink made against it — copies are unaffected.
- **`fusion vendor <name>…`** *(planned)*. Scaffold command: copy the named stdlib
  files into the current directory as real, editable files. Ergonomic front-end
  over `--stdlib-path` + `cp` for when a directory reskins `@OP` and wants several
  helpers that derive from `@OP` (`compact`, `range`, …) to follow the local override
  at once. Copies (portable, frozen) rather than symlinks, so it survives upgrades;
  the copied one-liners can then be hand-edited.

---

## 5. Open semantic questions to settle

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
