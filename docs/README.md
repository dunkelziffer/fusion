# Fusion documentation

**Fusion** is a small programming language — "functional JSON." It is JSON's data
model (atoms, arrays, objects) plus one more ingredient, the function. Functions take
one input and one output and work by pattern-matching; application is written
`value | function`.

```fusion
// double.fsn — pipe a number in, get it doubled out
(n => [n, 2] | @multiply)
```

```sh
echo '21' | ruby fusion.rb double.fsn      # => 42
```

---

## How this documentation is organised

The user documentation follows the [Diátaxis](https://diataxis.fr/) system, which
separates documentation into four kinds by the need each serves. Pick the one that
matches what you want right now:

| If you want to…                                   | Read                                 | Kind         |
| ------------------------------------------------- | ------------------------------------ | ------------ |
| **learn** the language by doing, from scratch     | [Tutorial](./tutorial.md)            | learning     |
| **accomplish a specific task** you already have   | [How-to guides](./how-to-guides.md)  | task         |
| **look up** exact syntax, built-ins, and behavior | [Reference](./reference.md)          | information  |
| **understand why** the language is shaped this way| [Explanation](./explanation.md)      | understanding|

The split mirrors the Diátaxis compass: tutorials and how-to guides are about *action*
(doing); reference and explanation are about *cognition* (knowing). Tutorials and
explanation serve *study* (acquiring skill and understanding); how-to guides and
reference serve *work* (applying it). Keeping these separate is deliberate — a recipe
should not digress into theory, and a reference should not try to teach.

```
                 ACTION                    COGNITION
            (doing things)              (knowing things)

  STUDY     Tutorial                    Explanation
 (skill)    learn by doing              understand the why

  WORK      How-to guides               Reference
 (applying) solve a task                look up the facts
```

---

## Design documentation

Separate from the user docs, and aimed at language designers and contributors rather
than users:

- **[Design documentation](./design.md)** — the full decision ledger: every design
  choice, who made it (designer vs. interpreter implementation), the alternatives
  considered, the pros and cons, and the forward roadmap (planned ergonomics, open
  questions, and bigger experiments).

This is the place to understand the language's *evolution* and its *unfinished
business*, including the one decision the running interpreter forced us to change
(error propagation), and the recurring tension (no local recursion form) that most
shapes what comes next.

---

## The interpreter

The current implementation is a proof of concept, `fusion.rb` (Ruby), accompanied by:

- `test.rb` — the core test suite;
- `error_test.rb` — additional tests for error handling
- `examples/` — sample `.fsn` programs;
- `stdlib/` — standard-library functions written in Fusion, reached via `@name`.

For the runtime contract, the command line, and how `@`-references resolve, see the
[Reference](./reference.md#9-files-references-and-the-runtime). For the original
working notes that predate this documentation, see `fusion-grammar.md` and
`fusion-open-questions.md`.

---

## A 30-second taste of the ideas

- **A file is one value.** A program is a file whose value is a function; running it
  is `STDIN | thatFunction`.
- **Bare words are holes** — they bind in patterns and read in results, so a pattern
  and a result are mirror images: `([a, b] => [b, a])` swaps a pair.
- **Pattern matching is the only control flow.** An `if` is a function with `true`/
  `false` clauses; a `for` loop is recursion that peels a list down to `[]`.
- **Types are predicates.** `n ? @Integer` matches integers; `@Integer` is just a
  built-in function reached with `@`, and you can write your own predicates.
- **Two empties.** `null` is ordinary "absent" data; an error is `!` followed by a
  payload (e.g. `!"divide by zero"`, `!42`, `!{"kind":"missing_key",...}`). Errors
  propagate through pipelines, preserving their payload, unless caught with an
  error pattern like `!msg`, `!_`, or just `!`.
- **One `@` namespace for everything.** `@helper` is a sibling file, `@add`/`@Integer`
  are built-ins, `@map` is the standard library, a bare `@` is the current file (for
  recursion), `@ENV` is the environment, and `@load` loads a file by name. A bare
  `@name` resolves sibling → built-in → stdlib, so siblings can shadow either,
  per-directory. No `import` keyword exists or is needed.

Start with the [Tutorial](./tutorial.md).
