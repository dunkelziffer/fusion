# Implementation notes — Fusion

Companion to `design.md`. That file records *decisions*; this one explains *how* a
few non-obvious mechanisms in the interpreter actually work.

## Thunks: laziness, memoization, and bare `@`

A top-level **unit** — a file, an inline (`-e`) program, or a REPL entry — is a
single expression whose value is computed lazily and at most once. That is a `Thunk`
(`lib/fusion/interpreter/thunk.rb`): a small state machine over a compute closure.

- `:unforced` → on the first `force`, it runs the closure, stores the result, and
  becomes `:done`.
- `:done` → returns the stored value. **This is the memoization.** It lives on the
  thunk object itself, not in any lookup table.
- `:forcing` → re-entered while still computing ⇒ a non-productive data cycle,
  reported as a `reference_error` at the point the cycle closes.

A bare `@` means "the value of the current unit", resolved by forcing that unit's
own thunk.

### Two separate jobs — only one was ever keyed by filename

It is tempting to think memoization is keyed by filename. It is not. There are two
distinct mechanisms:

1. **Sharing a file's thunk across references.** `@a` reached from many places must
   load `a.fsn` once. The interpreter keeps `@file_cache` (`abspath → Thunk`); a
   given file always resolves to the same thunk object. *This* is keyed by the
   absolute path.
2. **Memoizing a unit's value, and detecting cycles.** This is the thunk's own
   `@state`/`@value`. It never consults a filename; it just remembers what it
   computed.

So the filename is the key for *finding and sharing* a file's thunk — never for the
memoization itself.

### How a bare `@` reaches its thunk

Each unit puts its own thunk into the **interpreter context** of its environment
(see below) under `:self`, and `@` forces `env.context(:self)`:

- **Files**: the `:self` thunk is the very same object held in `@file_cache` for
  that path (`set_context(:self, load_file(abspath))`). So `@` and a sibling `@a`
  naming the same file share one memoized thunk, and a file that references itself
  mid-load is caught as a cycle.
- **Inline / REPL**: there is no path, so the thunk is *only* reachable through the
  environment binding. A closure captures the env where it was defined, so a bare
  `@` inside a function resolves to that unit's thunk even when the function is
  applied much later — which is what makes recursion work. The older filename-only
  scheme could not express this, which is why inline/REPL had no `@`.

The REPL builds a fresh interpreter per entry, but the thunk object lives in the
captured environment and outlives any single interpreter: once `:done`, forcing it
from a later entry simply returns the stored value. So `f = (… @ …)` defined in one
entry and applied by `5 | f` in the next resolves `@` to `f`.

### When `@` produces something useful

`@` only forces when it is actually evaluated, so the outcome depends on the program,
not on whether stdin is present:

- In a **function** unit, `@` sits in the unevaluated body, so the unit's value is
  just the function. Applying it externally — stdin for `-e`, a later entry in the
  REPL — forces `@` and recurses. With nothing to apply it, the value is the function
  itself (a `serialization_error` on stdout, or a lenient `"<function>"` in the
  REPL). Both are valid; neither is a special case.
- In a **data** position (`[1, @]`), `@` is forced as the unit loads, while its own
  thunk is still `:forcing` — a non-productive data cycle.

## Environment: bindings vs. interpreter context

`Env` (`lib/fusion/interpreter/env.rb`) holds two separate maps, both walking the
parent chain:

- **Bindings** (`@vars`) — user-visible identifiers. Pattern binders insert here via
  `bind`; the REPL keeps a name across entries via `define`. A bare identifier in an
  expression is resolved here (`lookup`); unbound ⇒ `binding_error`.
- **Interpreter context** (`@context`) — ambient state the evaluator needs, written
  with `set_context` and read with `context`, keyed by symbol:

  | key     | contents                                                    | set for                               |
  | ------- | ----------------------------------------------------------- | ------------------------------------- |
  | `:dir`  | the directory `@name` / `@../a` resolve against (a `String`) | every unit (file's dir, else `Dir.pwd`) |
  | `:file` | the absolute path, for error `location`s (a `String`)        | files only (absent ⇒ `code <inline>`) |
  | `:self` | the unit's own `Thunk`, forced by a bare `@`                 | every unit                            |

The two channels are deliberately separate, and a program reads only the first one.
So the context names are **not** identifiers: `__dir__`, `__file__`, and `__self__`
are unbound like any other unknown name (a `binding_error`), not readable values.

In particular `__self__` is **not** a synonym for `@`. `@` *forces* the `:self`
thunk down to the unit's value; the thunk object itself is not a Fusion value, and
exposing it would put a non-value into the value space (where it would crash
serialization). Keeping interpreter context out of the binding namespace is what
prevents that.

## The jail: confining `@`-resolution

A run carries one jail root (`Interpreter#@jail_root`, an absolute path). Every file
reached through an `@`-reference — a sibling, a downward `@dir/a`, an upward `@../a`,
or an `@load` target — is checked with `within_jail?` *before* it is loaded: the
target's expanded absolute path must be inside the jail root, or inside the stdlib
directory (always reachable, since it lives outside any project). A target outside
both is a `reference_error` (`outside the jail`), produced before the filesystem is
touched, so an out-of-jail path cannot even be probed for existence.

The jail does **not** cover two things:

- The top-level program file (given explicitly on the CLI) is loaded directly, not
  through `@`-resolution, so it is never jail-checked — the jail is about what the
  program may *reach*, not whether it may run.
- stdin — it is decoded as JSON, never evaluated as Fusion source, so it holds no
  `@`-references at all.

The check is lexical: `File.expand_path` normalises `..`, and existing symlinks are
followed. The jail confines references to a directory tree; it is not a security
sandbox and needs none, since Fusion cannot write files — so no symlink can be planted
to escape, and any symlink present is part of the legitimate project layout. A nil root
means unconfined — library and test callers use that; the CLI always supplies one,
defaulting to the program's directory.

The same root must reach every interpreter a run builds — the one that loads the
program, and the fresh one `safe_apply`/`safe_evaluate` create to apply it — so the
CLI computes it once (`CLI#jail_root`) and threads it through both.
