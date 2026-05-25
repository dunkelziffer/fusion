# Fusion documentation

**Fusion** is a small programming language — "functional JSON." It is JSON's data
model (atoms, arrays, objects) plus one more ingredient, the function. Functions take
one input and one output and work by pattern-matching; application is written
`value | function`.

```fusion
// double.fsn — pipe a number in, get it doubled out
(n => [n, 2] | multiply)
```

```sh
echo '21' | ruby lib/fusion.rb examples/double.fsn      # => 42
```

---

## How this documentation is organised

The user documentation follows the [Diátaxis](https://diataxis.fr/) system, which
separates documentation into four kinds by the need each serves. Pick the one that
matches what you want right now:

| If you want to…                                   | Read                                 | Kind         |
| ------------------------------------------------- | ------------------------------------ | ------------ |
| **learn** the language by doing, from scratch     | [Tutorial](./user/tutorial.md)            | learning     |
| **accomplish a specific task** you already have   | [How-to guides](./user/how-to-guides.md)  | task         |
| **look up** exact syntax, built-ins, and behavior | [Reference](./user/reference.md)          | information  |
| **understand why** the language is shaped this way| [Explanation](./user/explanation.md)      | understanding|

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

- **[Design decisions](./lang/design-decisions.md)** — the full decision ledger: every
  design choice, who made it (designer vs. interpreter implementation), the alternatives
  considered, and the pros and cons.
- **[Roadmap](./lang/roadmap.md)** — planned ergonomics, open semantic questions, and
  bigger experiments.

This is the place to understand the language's *evolution* and its *unfinished
business*, including the one decision the running interpreter forced us to change
(error propagation), and the recurring tension (no local recursion form) that most
shapes what comes next.

---

## The interpreter

The current implementation is a proof of concept, `lib/fusion.rb` (Ruby), accompanied by:

- `spec/test.rb` — a 38-case test suite;
- `examples/` — sample `.fsn` programs;
- `stdlib/` — standard-library functions written in Fusion, reached via `@std/...`.

For the runtime contract, the command line, and how `@`-references resolve, see the
[Reference](./user/reference.md#9-files-references-and-the-runtime).

---

## A 30-second taste of the ideas

- **A file is one value.** A program is a file whose value is a function; running it
  is `STDIN | thatFunction`.
- **Bare words are holes** — they bind in patterns and read in results, so a pattern
  and a result are mirror images: `([a, b] => [b, a])` swaps a pair.
- **Pattern matching is the only control flow.** An `if` is a function with `true`/
  `false` clauses; a `for` loop is recursion that peels a list down to `[]`.
- **Types are predicates.** `n ? Integer` matches integers; `Integer` is just a
  function, and you can write your own.
- **Two empties.** `null` is ordinary "absent" data; `!` is the error value, which
  propagates through pipelines unless explicitly caught with an `! =>` clause.
- **Modules are files.** `@map` imports a sibling file's value; `@std/map` reaches the
  standard library. No `import` keyword exists or is needed.

Start with the [Tutorial](./user/tutorial.md).
