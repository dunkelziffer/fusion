# Fusion roadmap

Tracked future work and open questions. Decisions that have already been made
live in [design.md](./design.md); this file is only for things still ahead.

---

## 1. Ergonomics

**Comparison & concat operators** *(planned)*. Add infix `< <= > >= !=` (today
`(a ?? b) | @lt` etc.) and string concatenation `++` (today `@concat`) as further
sugar, following the precedence model of design §5.6 / reference §2.7.

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

## 3. Runtime and tooling

- **A faster implementation** once semantics are frozen.
- **`fusion --stdlib-path`** *(planned)*. Print the absolute path of the bundled
  standard library so a user can find, read, copy, or symlink its `.fsn` files —
  e.g. to make a derived helper like `@range` follow a local `@OP` override:
  `cp "$(fusion --stdlib-path)/range.fsn" .`. This is the one ergonomics gap in the
  "reskin the operators" workflow (see how-to-guides). Needs a stable path: on a
  versioned install the returned directory changes across upgrades, which dangles
  any symlink made against it — copies are unaffected.
- **`fusion vendor <name>…`** *(planned)*. Scaffold command: copy the named stdlib
  files into the current directory as real, editable files. Ergonomic front-end
  over `--stdlib-path` + `cp` for when a directory reskins `@OP` and wants several
  helpers that derive from `@OP` (`range`, …) to follow the local override
  at once. Copies (portable, frozen) rather than symlinks, so it survives upgrades;
  the copied one-liners can then be hand-edited.

---

## 4. Bigger experiments

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
