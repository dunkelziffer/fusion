# Fusion documentation

## How this documentation is organised

The user documentation follows the [Diátaxis](https://diataxis.fr/) system, which
separates documentation into four kinds by the need each serves. Pick the one that
matches what you want right now:

| If you want to…                                    | Read                                   | Diataxis categories |
| -------------------------------------------------- | -------------------------------------- | ------------------- |
| **learn** the language from scratch                | [Tutorial](user/tutorial.md)           | study / action      |
| **accomplish a specific task** you already have    | [How-to guides](user/how-to-guides.md) | apply / action      |
| **look up** exact syntax, built-ins, and behavior  | [Reference](user/reference.md)         | apply / cognition   |
| **understand why** the language is shaped this way | [Explanation](user/explanation.md)     | study / cognition   |

Keeping these separate is deliberate:
- A recipe should not digress into theory.
- A reference should not try to teach.

If you are new to this language, start with the [Tutorial](user/tutorial.md).

## Design documentation

Separate from the user docs and mostly aimed at language designers and contributors rather
than users:

- **[Design documentation](lang/design.md)** — the full decision ledger: every
  design choice, who made it (designer vs. interpreter implementation), the
  alternatives considered, and the pros and cons.
- **[Roadmap](lang/roadmap.md)** — planned ergonomics, open questions,
  and bigger experiments.

These are the places to understand what the language is and what is still
unfinished.
