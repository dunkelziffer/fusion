# Implementation notes — Fusion

Companion to `design.md`. That file records *decisions*; this one explains *how* a
few non-obvious mechanisms in the interpreter actually work.

## Thunks: laziness, memoization, and bare `@`

A top-level **unit** — a file, an inline (`-e`) program, or a REPL entry — is a
single expression whose value is computed lazily and at most once. That is a `Thunk`
(`lib/fusion/interpreter/thunk.rb`): a small state machine over a compute closure.

- `:unforced` → on the first `force`, it runs the closure, stores the result, and
  becomes `:done`. The closure takes **no arguments**, so the stored result is the
  same for every reference.
- `:done` → returns the stored value. **This is the memoization.** It lives on the
  thunk object itself, not in any lookup table.
- `:forcing` → re-entered while still computing ⇒ a non-productive data cycle,
  reported as a `reference_error` at the point the cycle closes.

The subtlety: a unit's *value* is independent of the reference that forced it, but a
**read failure** is not — a missing file reached as `@a` from one place and `@../a`
from another must report each reference's own `operation`/`input`/`site`. So the
closure can't bake those in (it would memoize the *first* reference's error and hand
it to every later one). Instead the closure stays argument-free and produces a
*deferred* read failure (`ErrorVal.read_failure`) whose reference fields are
placeholders; `force` — which does know the reference — completes a fresh copy of it
per call (`#with_reference`). So the thunk still memoizes once, and caches nothing
reference-specific. (A parse or evaluation error *is* part of the file's value and is
memoized and returned as-is.)

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
  `bind`; the REPL keeps a name across entries via `bind(…, checked: false)`. A bare
  identifier in an expression is resolved here (`lookup`); unbound ⇒ `binding_error`.
- **Interpreter context** (`@context`) — ambient state the evaluator needs, written
  with `set_context` and read with `context`, keyed by symbol:

  | key     | contents                                                     | set for                                 |
  | ------- | ------------------------------------------------------------ | --------------------------------------- |
  | `:dir`  | the directory `@name` / `@../a` resolve against (a `String`) | every unit (file's dir, else `Dir.pwd`) |
  | `:file` | the absolute path, for error origins (a `String`)            | files only (absent ⇒ file `"<inline>"`) |
  | `:self` | the unit's own `Thunk`, forced by a bare `@`                 | every unit                              |
  | `:jail` | the run's jail root (a `String`, or nil for unconfined)      | once, on the run's root env             |
  | `:call_site` | the innermost user-code `file`, stamped onto built-in/stdlib errors (a `String`) | a stdlib function's clause env, in `apply` |

The two channels are deliberately separate, and a program reads only the first one.
So the context names are **not** identifiers: `__dir__`, `__file__`, and `__self__`
are unbound like any other unknown name (a `binding_error`), not readable values.

In particular `__self__` is **not** a synonym for `@`. `@` *forces* the `:self`
thunk down to the unit's value; the thunk object itself is not a Fusion value, and
exposing it would put a non-value into the value space (where it would crash
serialization). Keeping interpreter context out of the binding namespace is what
prevents that.

## The jail: confining `@`-resolution

The jail root lives in the environment's `:jail` context (set once on the run's root
env). Every file reached through an `@`-reference is checked with `within_jail?`, which
reads the jail from the interpreter's `@env` (`@env.context(:jail)`): the target's
expanded absolute path must be inside the jail root, or inside the stdlib directory
(always reachable, since it lives outside any project). A target outside both is a
`reference_error` (`outside the jail`).

The time of check differs by reference form, because `@name`/`@dir/a` carry a
built-in/stdlib fallback and `@../a`/`@load` do not:

- `@../a` and `@load` check the jail *before* the file is touched, so an out-of-jail
  target errors whether or not it exists (it is never probed for existence).
- `@name`/`@dir/a` resolves *sibling-first*, so the sibling is `File.exist?`-ed to
  choose between it and the built-in/stdlib fallback. An existing sibling outside the
  jail then errors (`outside the jail`); a missing one falls through to the fallback.

The jail does **not** cover two things:

- The top-level program file (given explicitly on the CLI) is loaded directly, not
  through `@`-resolution, so it is never jail-checked — the jail is about what the
  program may *reach*, not whether it may run.
- stdin — it is decoded as JSON, never evaluated as Fusion source, so it holds no
  `@`-references at all.

The check is lexical: `File.expand_path` normalises `..` and existing symlinks are
followed. The jail confines references to a directory tree; it is not a security
sandbox. Fusion cannot write files, so no symlink can be planted to escape, but
existing ones are part of the legitimate project layout. A nil/unset jail means
unconfined. `CLI.root_environment` defaults it to `Dir.pwd`, and a real CLI run
instead supplies the program's directory.

The jail rides the environment: the CLI builds the root env once (`root_environment`)
and passes it to both program loading and `apply`, so every interpreter the run builds
reads the same `:jail` from its `@env`.

## The error `file`: the innermost user-code call site

A standardized error's `file` is the **innermost user-code file** on the call chain
when the operation failed — a stdlib frame like `@map` is transparent, so a built-in
failing inside it reports *your* file, not the stdlib's. It is `Dir.pwd`-relative, or
`"<inline>"` for an `-e`/REPL entry, or `"<fusion>"` above all user code (a bare
operation applied straight to a value). Present for `code`/`builtin`/`stdlib` errors;
absent for the channel/runtime ones (`input`/`output`/`interpreter`), which have no
call site.

It is filled by two complementary mechanisms, split by *where the error is born*.

### Born in user code → set at birth, from `code_site`

An error raised while evaluating user code (`.name`, `[]`, an unresolved `@`-ref, an
unbound identifier) is created in `eval_expr` with the env in hand, so it takes its
`file` straight from `code_site(env)`. This *must* happen at birth: for such an error
the innermost user file is its own birth location — the deepest user frame, strictly
below any caller — so no later step could recover it. These errors also routinely
surface where no `apply` runs (`[1, @undefined]` as a whole program, emitted directly
with no input applied), so they couldn't be stamped even if we wanted to. (`code_site`
labels any file under the stdlib directory as `origin: "stdlib"`, so an `origin:
"code"` error only ever arises in user code — where `code_site`'s file already *is*
the innermost user file.)

### Born outside user code → stamped at `apply`

A built-in error is built in Ruby; a stdlib error is a `!{…}` raised deep in a stdlib
body. Neither has the user's env in hand. But both are always produced *inside* an
`apply` (a built-in runs as `f.fn.call`; a stdlib body runs in `apply`'s `Func`
branch), and `apply` knows the call site — so `apply` wraps `dispatch_apply` and
stamps the result with `ErrorVal#with_call_site(call_site)`. The call site is the
`:call_site` context (`call_site(env)`); a stdlib function's clause env inherits its
*caller's* `:call_site`, so a built-in failing several stdlib frames deep still reports
the user's file. Stamping is idempotent (a no-op once a `file` is present), so an error
is stamped once — at the innermost `apply` that produced it — and outer applies leave
it alone. No "already-stamped" flag is needed: in the innermost-user-file model the
call site is constant all the way up a stdlib chain.

### Why the stamp keys on `runtime?`, never `origin`

The stamp must fire for interpreter/stdlib errors but never for an arbitrary user
`!{…}`. Keying on the payload's `origin` is **unsound** — `origin` is just data, so a
user writing `!{"origin": "builtin"}` would get a spurious `file`. Provenance isn't
payload; it is interpreter state, recorded by `ErrorVal#runtime?` (the `@runtime`
flag). So the gate is two parts:

```ruby
return self unless @runtime && @payload.is_a?(Hash) && !@payload.key?("file")
origin = @payload["origin"]
return self unless origin == "builtin" || origin == "stdlib"
```

`@runtime` is the **soundness gate** — a user error is never runtime, so a forged
`origin` can never trigger a stamp. The `origin` check runs only *past* that gate,
where `origin` is interpreter-set and therefore safe to read; its narrower job is to
skip runtime errors that have no call site (a JSON-`input` parse `syntax_error` is
`runtime?` but `origin: "input"`, and rightly gets no `file`).

### Why marking stdlib errors `@runtime` is watertight

`@runtime` is set true in exactly two places, both keyed on interpreter state, never
on payload content:

1. `ErrorVal.from_runtime` — every interpreter-built error.
2. An `ErrLit` evaluated **where `code_site(env).origin == "stdlib"`**.

For (2), `env`'s `:file` must lie under `@stdlib_dir` (`file_site` checks
`start_with?`), and `:file` is set there only by `evaluate_file` loading a file
resolved via `resolve_builtin_or_stdlib`'s `File.join(@stdlib_dir, …)`. Every user
route (`@name` siblings, `@../a`, `@load`) resolves into the user's own tree;
inline/REPL has no `:file` at all. So user code always runs under `origin: "code"`;
the only way to reach `origin: "stdlib"` is for the code to physically live in the
interpreter's stdlib directory — which a Fusion program cannot arrange (it can't write
files, and a project isn't installed there), and which *would be* stdlib if it did.
Because the flag is set from *where the code runs*, a user writing `!{"origin":
"stdlib", "runtime": true}` changes only payload fields; the `@runtime` ivar is
untouched, so the error is never stamped.

Marking the flag at construction (a constructor argument, not a later mutation) keeps
`@runtime` write-once. A consequence of stdlib errors being runtime errors is that
they serialize **leniently** (functions → `"<function>"`, non-finite → `"<Infinity>"`),
which made the old `| @sanitize` in stdlib error payloads redundant; it was dropped,
and `sanitize.fsn` remains as a standalone utility.
