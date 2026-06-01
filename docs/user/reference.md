# Reference

*This is **reference** material in the [Diátaxis](https://diataxis.fr/) sense:
neutral, complete technical description, structured to mirror the language itself. It
describes **what is**, not how to use it or why it is so. For guided learning see the
[Tutorial](./tutorial.md); for task recipes see the [How-to guides](./how-to-guides.md);
for rationale see the [Explanation](./explanation.md). This documents the prototype as
implemented (`fusion.rb`), grammar rev 4.*

---

## 1. Values

A Fusion value is one of:

| Kind     | Examples                          | Notes                                        |
| -------- | --------------------------------- | -------------------------------------------- |
| null     | `null`                            | Ordinary data: a legitimate "absent" value.  |
| error    | `!42`, `!"oops"`, `!null`         | An error: always a `!` followed by a payload (any value). Distinct from `null`. |
| boolean  | `true`, `false`                   |                                              |
| integer  | `0`, `-7`, `42`                   | Distinct from float.                         |
| float    | `3.14`, `1e9`, `-0.5`             | Distinct from integer.                       |
| string   | `"hi"`, `"a\nb"`                  | JSON string syntax and escapes.              |
| array    | `[]`, `[1, 2, 3]`, `[1, [2]]`     | Ordered, heterogeneous.                      |
| object   | `{}`, `{"k": 1}`                  | String keys; insertion order preserved.      |
| function | `(p => o, ...)`                   | One input, one output. A first-class value.  |

Atoms are `null`, booleans, integers, floats, strings. Composites are arrays and
objects. The three non-atomic "ingredients" are arrays, objects, and functions.
Errors are a compound form (`!` plus a payload) — see §6.

---

## 2. Syntax

### 2.1 Expressions

Precedence, tightest to loosest:

1. Primary: literals, `[...]`, `{...}`, `(...)` grouping, function literals,
   identifiers, `@`-references.
2. Postfix member/index access: `x.key`, `x[expr]`.
3. Error prefix: `!expr` (construct an error). Bare `!` (with no operand) is the
   same as `!null`.
4. Pipe (application): `value | function`. Left-associative
   (`a | f | g` ≡ `(a | f) | g`).
5. Clause arrow: `=>` (loosest, so the entire right-hand side of a clause is one
   expression).

### 2.2 Function literals

```
( pattern => expr , pattern => expr , ... )
```

One or more clauses, comma-separated, parenthesized; an optional trailing comma is
allowed. A single parenthesized expression with no `=>` at the top level is a grouped
expression, not a function.

### 2.3 Array and object literals

Array elements and object members may be **spread** with `...`:

```
[1, ...other, 9]            // splice an array's elements in place
{"a": 1, ...other}          // merge another object's keys in place
```

In a result, `...expr` requires `expr` to be an array (in an array literal) or an
object (in an object literal); otherwise the literal evaluates to `!`.

### 2.4 Comments

`// line comment` to end of line, and `/* block comment */`.

### 2.5 Grammar (EBNF)

```ebnf
file        = expr ;

expr        = pipe ;
pipe        = prefix { "|" prefix } ;
prefix      = "!" [ prefix ] | postfix ;            (* bare "!" -> !null *)
postfix     = primary { "." identifier | "[" expr "]" } ;
primary     = atom | array | object | function | identifier | fileref | "(" expr ")" ;

fileref     = "@" [ refpath ] ;                     (* bare "@" = current file *)
refpath     = { "../" } segment { "/" segment } ;   (* ".fsn" implied *)
segment     = identifier ;

atom        = "null" | "true" | "false" | number | string ;
                                                    (* errors are `!`+payload (see prefix) *)
array       = "[" [ elem { "," elem } [ "," ] ] "]" ;
elem        = expr | spread ;
spread      = "..." expr ;
object      = "{" [ member { "," member } [ "," ] ] "}" ;
member      = string ":" expr | spread ;

function    = "(" clause { "," clause } [ "," ] ")" ;
clause      = pattern "=>" expr ;

(* An error pattern is a top-level construct: a clause can match an error, but
   array elements, object members, and error payloads cannot. This restriction
   falls out of the grammar shape -- `corepat` does not include `errpat`, so
   no recursive descent can re-enter `errpat`. There is no flag-threading,
   look-ahead, or post-parse check involved. *)
pattern     = errpat | guardedpat ;
errpat      = "!" | "!" guardedpat ;                (* bare "!" matches any error, binds nothing *)
guardedpat  = corepat [ "?" predicate ] ;
predicate   = prefix ;                              (* any expression yielding a function *)
corepat     = literalpat | bindpat | wildcard | arraypat | objectpat ;
literalpat  = atom ;
wildcard    = "_" ;
bindpat     = identifier ;
arraypat    = "[" [ pelem { "," pelem } [ "," ] ] "]" ;
pelem       = guardedpat | "..." [ identifier ] ;
objectpat   = "{" [ pmember { "," pmember } [ "," ] ] "}" ;
pmember     = string ":" guardedpat | "..." [ identifier ] ;

identifier  = letter { letter | digit | "_" } ;
number      = int_lit | float_lit ;
int_lit     = [ "-" ] digit { digit } ;
float_lit   = int_lit "." digit { digit } [ exp ] | int_lit exp ;
exp         = ("e" | "E") [ "+" | "-" ] digit { digit } ;
string      = '"' { char | escape } '"' ;
```

---

## 3. Functions and application

A function is an ordered list of clauses. Applying a function to a value `v`:

1. If the function value itself is an error (e.g. piping into an unresolved name),
   that error is the result.
2. Otherwise clauses are tried in order. The first clause whose pattern matches
   `v` produces the result, evaluated with that clause's bindings in scope.
3. If a `?` predicate evaluates to an error during matching, that error becomes
   the function's result; no further clauses are tried (see §6.4).
4. **If no clause matches:** the result is `v` itself when `v` is an error
   (propagation — an unmatched error is never silently swallowed), and `null`
   otherwise (the lenient default).

A consequence of rule 4: a function with error clauses that only match *some*
shapes of error (e.g. `(!42 => "got 42", _ => "ok")`) still propagates any
other-shaped error it receives — `!"oops"` is not caught by `!42`, the `_`
clause rejects errors, no clause matches, so `!"oops"` propagates. To handle
"any unrecognized error" you must add a catch-all error clause: `!` (or
equivalently `!_`) for "catch any error, ignore the payload"; `!msg` to bind
the payload.

Functions take exactly one argument. Multiple arguments are passed as an array or
object. Currying is done by returning a function: `(x => (y => [x, y] | @add))`.

Functions are values: they may be elements of arrays, values of object keys, results
of clauses, and arguments to other functions.

---

## 4. Patterns and binding

A pattern both tests structure and extracts parts. Pattern forms:

| Form              | Matches                                  | Binds                       |
| ----------------- | ---------------------------------------- | --------------------------- |
| literal (`42`, `"x"`, `true`, `null`) | exactly that value                  | nothing                     |
| `!`, `!_`, `!pat` | an error; `!pat` destructures the payload (see §6.2) | as `pat` binds  |
| `_` (wildcard)    | anything **except** an error             | nothing                     |
| identifier (`a`)  | anything **except** an error             | the value, under that name  |
| `[p1, p2, ...]`   | array of matching length, elementwise    | as each `pi` binds          |
| `[p, ...rest]`    | array with ≥ fixed elements              | `rest` = remaining elements |
| `[...init, p]`    | array; `...` may appear before fixed tail | `init` = leading elements  |
| `{"k": p, ...}`   | object having key `k` (and others)       | as `p` binds                |
| `{..., ...rest}`  | object                                   | `rest` = unmatched key/value pairs |
| `corepat ? pred`  | `corepat` matches **and** `value | pred` is `true` | as `corepat` binds  |

Rules:

- **Bare identifiers are holes.** In a pattern they bind; in an expression they read
  the value bound to that name in the current clause. A bare identifier never denotes
  a built-in — built-ins are reached with `@` (see §7, §9.2). Reading an unbound bare
  identifier yields an error.
- **No sibling scope.** All bindings in a clause are produced simultaneously. A `?`
  predicate sees **only** the value matched by the pattern it is attached to — never
  another part of the same clause. For `!pat ? pred`, the `?` binds *inside* the
  `!` (the grammar parses it as `!(pat ? pred)`), so the predicate runs against the
  payload — exactly what `pat` binds. `(!a ? @Integer => ...)` checks whether the
  payload `a` is an integer. If a `?` predicate evaluates to an error, that error
  bubbles up as the function's result (see §6.4).
- **`...rest` in an array** may appear once, anywhere, capturing the middle/remaining
  elements. In an object it captures all keys not explicitly matched. A bare `...`
  with no name matches the remainder without binding.
- An object pattern matches if all its named keys are present; extra keys are allowed
  (and captured by `...rest` if present).

---

## 5. The `?` predicate (refinement / types)

`corepat ? predicate` matches when `corepat` matches structurally **and** piping the
matched value into `predicate` yields exactly `true`. The predicate is any
expression evaluating to a function (a name, a member access, or an inline function
literal).

"Types" are not a separate construct: the built-in predicates `@Integer`, `@String`,
etc. are ordinary functions returning booleans, reached with `@` and used with `?`
(e.g. `n ? @Integer`). User-defined predicates work identically (e.g. `n ? @isEven`).

---

## 6. Errors

An **error value** is `!` followed by a payload: `!42`, `!"divide by zero"`,
`!{"kind":"missing_key","key":"id"}`, `!null`. The payload may be any Fusion value
(including `null`, including another error). The error value is distinct from
ordinary data: `null` means legitimate absence; an error means something went wrong.

### 6.1 Constructing errors

In expression position, `!` is a prefix operator that constructs an error from its
operand:

- `!42` is an error with payload `42`.
- `!"oops"` is an error with payload the string `"oops"`.
- `!` alone (with nothing following it) is shorthand for `!null`.
- `!expr` where `expr` itself evaluates to an error **propagates** that inner error
  rather than wrapping it (so you cannot accidentally bury an error inside another
  error's payload).

Precedence: `!` binds tighter than `|` so `!x | f` is `(!x) | f`; looser than
postfix `.`/`[]` so `!x.foo` is `!(x.foo)`.

### 6.2 Matching errors

In pattern position, `!` introduces an **error pattern**:

| Pattern             | Matches                                                                  |
| ------------------- | ------------------------------------------------------------------------ |
| `!`                 | any error; payload is not bound. Cannot carry a `?` predicate.           |
| `!_`                | any error; payload is not bound. Equivalent to `!` *except* that it can carry a predicate (`!_ ? @pred`). |
| `!x`                | any error; binds the payload to `x`                                      |
| `!42`               | only an error whose payload deep-equals `42` (any literal works here)    |
| `!{"kind": k, ...}` | an error whose payload is an object with key `kind`, binding `k`; other payload keys captured by `...` |
| `![p1, p2, ...]`    | an error whose payload is an array matching that array pattern           |

The payload pattern (the `pat` in `!pat`) is a full `guardedpat` — it uses the
destructuring machinery you'd expect: `_`, binders, literals, `...rest`,
nested arrays/objects, plus an optional `?` predicate. It cannot itself contain
another `!pat`: at runtime there is no error nested inside another error, so
the syntax is rejected at parse time.

**`!pat` may only appear as a clause's top-level pattern.** The grammar
expresses this directly: `errpat` is one of the two alternatives of `pattern`
(see §2.5), and `corepat` does not include `errpat`. So `[!a, b]`,
`{"err": !x}`, `[..., !x]`, `!!42`, and `!{"k": !v}` are all syntax errors.
The reasoning: errors propagate before they can sit inside a collection, so
a value matching `[!a, b]` never exists at runtime, and admitting the syntax
would create dead code.

The `?` predicate of an error pattern lives **inside** the payload pattern,
not after it: `!a ? @Integer` parses as `!(a ? @Integer)`. So the predicate
refines the **payload** `a`, not the error wrapping it. This is what you want:
`(!a ? @Integer => ...)` asks "is the error's payload an integer." A
consequence: `! ? @Integer` is a syntax error — bare `!` has no payload
pattern for the predicate to refer to. Use `!_ ? @Integer` instead.

### 6.3 Propagation

**Errors are not first-class values.** At any moment of execution there is either
a value in motion or an error in motion, never both. An error reaches user code
only through a clause whose pattern catches it; outside of that catch site, an
error encountered where a value is expected always propagates.

The propagation rule is uniform — there is no special handling for predicates or
particular built-ins:

- **Applying any function to an error** returns that same error (payload
  preserved), **unless** a clause's pattern actually matches it. The matching
  is per-call: it is not enough for the function to have *some* error clause;
  that clause must match the specific error received. An error of a shape no
  clause catches propagates unchanged.
- **Built-in operations (`@add`, `@divide`, `@equals`, `@Integer`, …) all
  propagate** their input error without examining it. To inspect or compare an
  error's payload, you must catch it first and operate on the extracted payload:
  `!42 | (!a => a) | @Integer` returns `true` (the payload `42` *is* an integer);
  `!42 | @Integer` returns `!42` (the predicate never runs).
- **Building an array or object propagates** any error encountered while
  evaluating an element/member. `[1, !"bad", 2]` evaluates to `!"bad"`, not to
  an array of three things.
- **Constructing an error from an erroring expression** propagates the inner
  error rather than wrapping it. `!([5,0] | @divide)` evaluates to
  `!"divide: division by zero"`, never to an error wrapping an error. (This
  preserves the rule that there is never more than one error simultaneously.)
- **When the function value itself is an error** (e.g. `value | @undefined_name`
  where `@undefined_name` resolves to an error), that error is the result.

### 6.4 `?`-predicate errors bubble up

If a `?` predicate evaluates to an error (the predicate function itself errored,
or it was a non-function error value), that error becomes the function's return
value immediately. Subsequent clauses are **not** tried — predicate-errors are
treated as program failures, not as "no match." This is the key reason to make
your predicates *total* (end with `_ => false`): a predicate that can crash will
short-circuit your whole function.

### 6.5 Sources of errors

Built-in errors are produced by:

- A strict function (`_ => !`) on no match — payload `null`.
- Built-in operations on bad input — payload is a descriptive string,
  e.g. `"divide: division by zero"`, `"add: expected a pair of numbers"`.
- Member access on a missing key or non-object, index out of range, or bad index
  type — payload is a structured object like
  `{"kind":"missing_key","key":"foo"}` or `{"kind":"index_out_of_range",...}`.
- Spread of a non-array or non-object — `{"kind":"spread_non_array",...}`.
- Unresolved `@`-reference — `{"kind":"unresolved_ref","name":"..."}`.
- Non-productive data cycle — `{"kind":"data_cycle","path":"..."}`.
- Applying a non-function — `{"kind":"apply_non_function","got":"..."}`.

User code constructs errors with `!payload` as described above.

### 6.6 Equality

`@equals` propagates errors like every other built-in: comparing involving an
error returns that error, not a boolean. To compare two errors' payloads,
extract them first with catches:

```fusion
(e1 => e1 | (!a => a)) | (e2 => e2 | (!b => b)) | @equals
```

In practice this isn't a common need — errors are usually caught and inspected
once, then routed.

---

## 7. Built-in functions

All built-ins are ordinary one-argument functions, **reached with an `@` prefix**
(`@add`, `@Integer`, …); see §9.2 for how `@name` resolves. The names in the tables
below are the built-in names; write `@` before them to use them. **Operations** return
`!` on type-invalid or domain-invalid input. **Predicates** return `false` on any
input that is not of the queried type (they never return `!`).

### 7.1 Arithmetic (operations)

| Name       | Input             | Result                                             |
| ---------- | ----------------- | -------------------------------------------------- |
| `add`      | `[number, number]`| sum                                                |
| `subtract` | `[number, number]`| difference                                         |
| `multiply` | `[number, number]`| product                                            |
| `divide`   | `[number, number]`| quotient; integer if evenly divisible, else float; `!` if divisor is 0 |
| `mod`      | `[number, number]`| remainder; `!` if divisor is 0                     |
| `negate`   | `number`          | negation                                           |
| `floor`    | `number`          | floor (integer)                                    |

### 7.2 Comparison (operations)

| Name        | Input                                   | Result          |
| ----------- | --------------------------------------- | --------------- |
| `equals`    | `[any, any]`                            | deep structural equality (boolean) |
| `lessThan`  | `[number, number]` or `[string, string]`| boolean; `!` on mismatched/invalid types |

Other comparisons (`lessEq`, `greaterThan`, `greaterEq`, `notEquals`) are specified
for the standard library, derivable from `equals` and `lessThan`.

### 7.3 Boolean (operations)

| Name  | Input              | Result        |
| ----- | ------------------ | ------------- |
| `and` | `[boolean, boolean]`| logical and  |
| `or`  | `[boolean, boolean]`| logical or   |
| `not` | `boolean`          | logical not   |

### 7.4 Strings and structure bridges (operations)

| Name          | Input                       | Result                                  |
| ------------- | --------------------------- | --------------------------------------- |
| `length`      | string / array / object     | element/character/key count (integer)   |
| `concat`      | `[string, string]`          | concatenation                           |
| `chars`       | string                      | array of single-character strings       |
| `join`        | `[array-of-strings, string]`| joined string                           |
| `toString`    | any                         | string form of the value                |
| `parseNumber` | string                      | integer or float; `!` if not numeric    |
| `keys`        | object                      | array of key strings                    |
| `values`      | object                      | array of values                         |

### 7.5 Type predicates (predicates)

`Integer`, `Float`, `Number`, `String`, `Boolean`, `Array`, `Object`, `Null`. Each
takes any value and returns a boolean. `Number` is true for integers and floats.

### 7.6 Special built-ins: `ENV` and `load`

These resolve in the `@name` chain like other built-ins (so a sibling file of the
same name shadows them), but they are not plain unary value functions:

- **`@ENV`** evaluates directly to an object mapping every environment variable name
  to its value. All values are strings; nothing is parsed. Read one with member
  access: `@ENV.PATH`. A missing variable yields `!`.
- **`@load`** evaluates to a function taking a filename **string verbatim** (no `.fsn`
  appended), resolved relative to the referencing file's directory; it returns that
  file's value, or `!` if the file does not exist. Use it to load files whose names
  are computed at runtime or are not plain identifiers, e.g. `"a.b.fsn" | @load`.

---

## 8. Member and index access

- `x.key` — if `x` is an object containing `key`, its value; otherwise `!`.
- `x[expr]` — if `x` is an array and `expr` is an integer in range, the element
  (negative indices count from the end); if `x` is an object and `expr` is a string
  key that exists, its value; otherwise `!`.

Both `.` and `[]` bind tighter than `|`.

---

## 9. Files, references, and the runtime

### 9.1 Files

A `.fsn` file contains **exactly one expression**, which is its value. A file is
**executable** if that value is a function.

### 9.2 References

A `@` reference takes one of these forms:

- **`@`** (nothing after it) — the **current file**'s value. Used for self-recursion.
- **`@ENV`** — an object of all environment variables (string keys, string values;
  no parsing). Resolved in the `@name` chain below, so it is shadowable.
- **`@name`** — a single bare identifier (no `/`, no `../`).
- **`@dir/name`, `@a/b/c`** — a downward path.
- **`@../name`, `@../../a/b`** — an upward path (contains one or more `../`).

**Resolution of `@name` and downward paths** (any reference *without* `../`) proceeds
in order, first match winning:

1. a **sibling file** at `<referencing dir>/<name>.fsn`;
2. a **built-in** of that exact name (including `ENV` and `load`);
3. a **standard-library file** at `<stdlib root>/<name>.fsn`.

If none match, the result is `!`. Downward paths participate fully: `@math/sqrt`
checks a sibling `math/sqrt.fsn`, then a built-in named `math/sqrt`, then a stdlib
`math/sqrt.fsn`.

**Resolution of upward paths** (any reference containing `../`) is **file-only**: it
resolves solely to a file relative to the referencing directory and never falls back
to a built-in or the standard library.

The `.fsn` extension is implied and never written in a `@` reference. File resolution
is relative to the **referencing file's** directory; built-ins and the standard
library are global to the runtime but, per the order above, are shadowed by a sibling
file of the same name — and that shadowing is per-directory, never global.

**Built-ins are reached through this same mechanism**: `@add`, `@Integer`, etc. are
`@name` references that resolve at step 2. A *bare* identifier (without `@`) is only
a pattern hole; it never denotes a built-in.

Two built-ins are special in how they resolve:

- **`@ENV`** resolves (at step 2) to a fresh object of environment variables.
- **`@load`** resolves (at step 2) to a function that loads a file by a **verbatim**
  filename string — no `.fsn` is appended — relative to the referencing directory,
  returning that file's value. If the argument is not a string, or the file does not
  exist, the result is an error (`{"kind":"load_bad_arg",...}` or
  `{"kind":"file_not_found","path":...}` respectively). This is the only way to load
  a file whose name is computed at runtime or is not a plain identifier (e.g.
  `"data.config.fsn"`).

References are:

- **Lazy** — resolved when evaluated/applied, not when a file loads. A file may
  reference itself (recursion) or another file may reference it back (mutual
  recursion) without an infinite load loop.
- **Memoized** — each file path is loaded and evaluated once per run; shared
  dependencies load once.

A **non-productive data cycle** (files whose values reference each other as data, not
through a function boundary) yields `!` at the point of the cyclic self-reference;
surrounding productive structure is preserved. Recursion through functions is not a
data cycle and terminates normally when guided by pattern matching.

### 9.3 Runtime contract

The interpreter reads standard input as JSON, converts it to a Fusion value `v`,
computes `v | programFunction`, and prints the result on standard output as JSON.

- Empty input is treated as `null`.
- Non-JSON input yields an error (payload `{"kind":"stdin_not_json"}`).
- **If the final result is an error**, the interpreter prints **nothing** to
  standard output, prints the error's **payload** (as JSON) to standard error, and
  exits with status `1`. Otherwise the result is printed to standard output and the
  interpreter exits `0`. This makes Fusion programs first-class Unix filters: the
  stdout stream carries the value-or-nothing, the stderr stream carries the failure
  detail, and the exit code is `0`/`1` accordingly.

### 9.4 Command-line interface

```
ruby fusion.rb <file.fsn> [json-input]
ruby fusion.rb -e '<source>' [json-input]
```

Input comes from the `[json-input]` argument if present, otherwise from standard
input. Setting the environment variable `FUSION_DEBUG` causes file-not-found and
parse errors during reference resolution to be reported on standard error.

---

## 10. Prototype status

This reference describes the proof-of-concept interpreter `fusion.rb`. Its behavior
is covered by a test suite (`test.rb`). Features specified but not fully populated
in the prototype standard library, and deliberately deferred design questions, are
listed in the [Design documentation](./design.md).
