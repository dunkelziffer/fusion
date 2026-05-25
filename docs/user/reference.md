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
| error    | `!`                               | The error value. Distinct from `null`.       |
| boolean  | `true`, `false`                   |                                              |
| integer  | `0`, `-7`, `42`                   | Distinct from float.                         |
| float    | `3.14`, `1e9`, `-0.5`             | Distinct from integer.                       |
| string   | `"hi"`, `"a\nb"`                  | JSON string syntax and escapes.              |
| array    | `[]`, `[1, 2, 3]`, `[1, [2]]`     | Ordered, heterogeneous.                      |
| object   | `{}`, `{"k": 1}`                  | String keys; insertion order preserved.      |
| function | `(p => o, ...)`                   | One input, one output. A first-class value.  |

Atoms are `null`, `!`, booleans, integers, floats, strings. Composites are arrays and
objects. The three non-atomic "ingredients" are arrays, objects, and functions.

---

## 2. Syntax

### 2.1 Expressions

Precedence, tightest to loosest:

1. Primary: literals, `[...]`, `{...}`, `(...)` grouping, function literals,
   identifiers, `@`-references.
2. Postfix member/index access: `x.key`, `x[expr]`.
3. Pipe (application): `value | function`. Left-associative
   (`a | f | g` ≡ `(a | f) | g`).
4. Clause arrow: `=>` (loosest, so the entire right-hand side of a clause is one
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
pipe        = postfix { "|" postfix } ;
postfix     = primary { "." identifier | "[" expr "]" } ;
primary     = atom | array | object | function | identifier | fileref | "(" expr ")" ;

fileref     = "@" refpath ;
refpath     = { "../" } segment { "/" segment } ;   (* ".fsn" implied *)
segment     = identifier ;

atom        = "null" | "!" | "true" | "false" | number | string ;
array       = "[" [ elem { "," elem } [ "," ] ] "]" ;
elem        = expr | spread ;
spread      = "..." expr ;
object      = "{" [ member { "," member } [ "," ] ] "}" ;
member      = string ":" expr | spread ;

function    = "(" clause { "," clause } [ "," ] ")" ;
clause      = pattern "=>" expr ;

pattern     = corepat [ "?" predicate ] ;
predicate   = postfix ;
corepat     = literalpat | bindpat | wildcard | arraypat | objectpat ;
literalpat  = atom ;
wildcard    = "_" ;
bindpat     = identifier ;
arraypat    = "[" [ pelem { "," pelem } [ "," ] ] "]" ;
pelem       = pattern | "..." [ identifier ] ;
objectpat   = "{" [ pmember { "," pmember } [ "," ] ] "}" ;
pmember     = string ":" pattern | "..." [ identifier ] ;

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

1. If `v` is `!`: the result is `!`, **unless** some clause's pattern is the literal
   `!`, in which case matching proceeds normally (see §6).
2. Otherwise clauses are tried in order. The first clause whose pattern matches `v`
   produces the result, evaluated with that clause's bindings in scope.
3. If no clause matches, the result is `null`.

Functions take exactly one argument. Multiple arguments are passed as an array or
object. Currying is done by returning a function: `(x => (y => [x, y] | add))`.

Functions are values: they may be elements of arrays, values of object keys, results
of clauses, and arguments to other functions.

---

## 4. Patterns and binding

A pattern both tests structure and extracts parts. Pattern forms:

| Form              | Matches                                  | Binds                       |
| ----------------- | ---------------------------------------- | --------------------------- |
| literal (`42`, `"x"`, `true`, `null`, `!`) | exactly that value          | nothing                     |
| `_` (wildcard)    | anything **except** `!`                  | nothing                     |
| identifier (`a`)  | anything **except** `!`                  | the value, under that name  |
| `[p1, p2, ...]`   | array of matching length, elementwise    | as each `pi` binds          |
| `[p, ...rest]`    | array with ≥ fixed elements              | `rest` = remaining elements |
| `[...init, p]`    | array; `...` may appear before fixed tail | `init` = leading elements  |
| `{"k": p, ...}`   | object having key `k` (and others)       | as `p` binds                |
| `{..., ...rest}`  | object                                   | `rest` = unmatched key/value pairs |
| `corepat ? pred`  | `corepat` matches **and** `value | pred` is `true` | as `corepat` binds  |

Rules:

- **Bare identifiers are holes.** In a pattern they bind; in an expression they read
  the bound (or built-in) value of that name.
- **No sibling scope.** All bindings in a clause are produced simultaneously. A `?`
  predicate sees **only** the value matched by the pattern it is attached to — never
  another part of the same clause.
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

"Types" are not a separate construct: the built-in predicates `Integer`, `String`,
etc. are ordinary functions returning booleans, used with `?`. User-defined
predicates work identically.

---

## 6. The error value `!`

`!` is a value distinct from `null`. `null` means legitimate absence; `!` means
something went wrong.

- **Matching.** `!` matches **only** the literal `!` pattern. It does not match `_`,
  an identifier binder, or any array/object pattern.
- **Propagation.** Applying any function to `!` yields `!`, unless the function has a
  clause whose pattern is the literal `!`. This makes errors flow through pipelines
  automatically and be caught only by explicit intent.
- **Source.** `!` is produced by: a strict function (`_ => !`) on no match; built-in
  operations on bad input (§7); division/mod by zero; member/index access that fails
  (§8); a spread of a non-array/non-object; an unresolved `@`-reference; a
  non-productive data cycle (§9).
- **Catching.** A clause `! => ...` matches `!` and stops propagation.
- `!` is a single opaque value; it carries no payload distinguishing error kinds.

---

## 7. Built-in functions

All built-ins are ordinary one-argument functions. **Operations** return `!` on
type-invalid or domain-invalid input. **Predicates** return `false` on any input that
is not of the queried type (they never return `!`).

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

`@path` evaluates to the value of another file:

- `@a` → `a.fsn` in the referencing file's directory.
- `@dir/a` → `dir/a.fsn` relative to the referencing file.
- `@../a` → `a.fsn` one directory up (one or more `../` allowed).
- `@std/a` → `a.fsn` in the bundled standard-library directory.

The `.fsn` extension is implied and never written. Resolution is relative to the
**referencing file's** directory, except the `std/` prefix, which resolves against
the runtime's standard-library root.

References are:

- **Lazy** — resolved when evaluated/applied, not when a file loads. A file may
  reference itself (recursion) or another file may reference it back (mutual
  recursion) without an infinite load loop.
- **Memoized** — each path is loaded and evaluated once per run; shared dependencies
  load once.

A **non-productive data cycle** (files whose values reference each other as data, not
through a function boundary) yields `!` at the point of the cyclic self-reference;
surrounding productive structure is preserved. Recursion through functions is not a
data cycle and terminates normally when guided by pattern matching.

### 9.3 Runtime contract

The interpreter reads standard input as JSON, converts it to a Fusion value `v`,
computes `v | programFunction`, and prints the result as JSON.

- Empty input is treated as `null`.
- Non-JSON input yields `!`.
- A final result of `!` causes a nonzero process exit code.

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

This reference describes the proof-of-concept interpreter `fusion.rb`, covered by a
38-case test suite (`test.rb`). Features specified but not fully populated in the
prototype standard library, and deliberately deferred design questions, are listed in
the [Design documentation](../lang/design-decisions.md).
