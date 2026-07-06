# Reference

## 1. Values

A Fusion value is one of:

| Kind     | Examples                          | Notes                                         |
| -------- | --------------------------------- | --------------------------------------------- |
| null     | `null`                            | Ordinary data: a legitimate "absent" value.   |
| boolean  | `true`, `false`                   |                                               |
| integer  | `0`, `-7`, `42`                   | Distinct from float.                          |
| float    | `3.14`, `1e9`, `-0.5`             | Distinct from integer.                        |
| string   | `"hi"`, `"a\nb"`                  | JSON string syntax and escapes.               |
| array    | `[]`, `[1, 2, 3]`, `[1, [2]]`     | Ordered, heterogeneous.                       |
| object   | `{}`, `{"k": 1}`                  | String keys; insertion order preserved.       |
| function | `(p => o, ...)`                   | One input, one output. A first-class value.   |
| error    | `!42`, `!"oops"`, `!null`         | An error with a payload. Not a regular value. |

The only atomic values are `null`, booleans, integers, floats and strings.

The only composite data structures are arrays and objects.

Functions are first-class values. They behave like all other values with 3 small exceptions:
- They can't cross the CLI boundary. All values on STDIN, STDOUT and STDERR may only
  contain regular JSON values.
- In contrast to arrays and objects, there's no syntax for pattern matching on functions.
- Functions can't be an error payload.

Errors are not regular values:
- They contain a regular value as "payload", but aren't regular values themselves.
- They can't be stored in arrays or objects. They always "bubble" and turn that whole
  data structure into an error.

---

## 2. Syntax

### 2.1 Expressions

Precedence, tightest to loosest:

1. Primary: literals, `[...]`, `{...}`, `(...)` grouping, function literals,
   identifiers, `@`-references.
2. Postfix: member access `x.key`, index read `x[expr]`, index write `x[key = value]`.
3. Unary prefix: `!x` (construct an error; bare `!` is `!null`), `-x` (negate),
   `/x` (invert), `~x` (logical not).
4. Pipe (application) and map-pipes: `value | function`, `|:` (map), `|?` (filter),
   `|+` (reduce). Left-associative (`a | f | g` ≡ `(a | f) | g`).
5. Multiplicative: `*`, `/`, `%`, `//`. Left-associative.
6. Additive: `+`, `-`. Left-associative.
7. Ordering: `??` and the comparisons `<`, `<=`, `>`, `>=`. Binary, left-associative.
8. Equality: `==`.
9. Logical and: `&&`.
10. Logical or: `||`.
11. Clause arrow: `=>` (loosest, so the entire right-hand side of a clause is one
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

```fusion
# Splice an array's elements in place
[1, ...other, 9]
```

```fusion
# Merge another object's keys in place
{"a": 1, ...other}
```

In a result, `...expr` requires `expr` to be an array (in an array literal) or an
object (in an object literal); otherwise the literal evaluates to `!`.

### 2.4 Comments

Fusion only has **whole-line comments**. A line is a comment iff its first non-whitespace
character is `#`. Comments can be stripped without parsing the language, because string
literals cannot span physical lines:

```bash
# Canonical specification of comment stripping
grep -v '^[[:space:]]*#' program.fsn
```

A shebang line needs no special treatment — `#!/usr/bin/env fusion` is just a comment
by the same rule.

### 2.5 Grammar (EBNF)

```ebnf
file           = expr ;

expr           = logical_or ;
logical_or     = logical_and { "||" logical_and } ;
logical_and    = equality { "&&" equality } ;
equality       = ordering { "==" ordering } ;
ordering       = additive { ( "??" | "<" | "<=" | ">" | ">=" ) additive } ;
additive       = multiplicative { ( "+" | "-" ) multiplicative } ;
multiplicative = pipe { ( "*" | "/" | "%" | "//" ) pipe } ;
pipe           = unary { ( "|" | "|:" | "|?" | "|+" ) unary } ;
unary          = "!" [ unary ]                          (* bare "!" -> !null; "!x" builds an error *)
               | ( "-" | "/" | "~" ) unary              (* negate / invert / not; operand required *)
               | postfix ;
postfix        = primary { "." identifier | "[" expr [ "=" expr ] "]" } ;   (* "[e]" reads, "[e = e]" writes *)
primary        = atom | array | object | function | identifier | fileref | "(" expr ")" ;

identifier     = letter { letter | digit | "_" } ;

atom           = "null" | "true" | "false" | number | string ;
number         = int_lit | float_lit ;                 (* unsigned; a negative is unary "-" *)
int_lit        = digit { digit } ;
float_lit      = int_lit "." digit { digit } [ exp ] | int_lit exp ;
exp            = ("e" | "E") [ "+" | "-" ] digit { digit } ;
string         = '"' { char | escape } '"' ;           (* char excludes raw newline; use \n *)

array          = "[" [ item { "," item } [ "," ] ] "]" ;
item           = expr | spread ;
object         = "{" [ pair { "," pair } [ "," ] ] "}" ;
pair           = string ":" expr | spread ;
spread         = "..." expr ;

function       = "(" [ clause { "," clause } [ "," ] ] ")" ;   (* "()" is the empty function *)
clause         = pattern "=>" expr ;

fileref        = ( "@" | "@@" ) [ path ] ;             (* bare "@"/"@@" = current unit / its super *)
path           = { ".." "/" } segment { "/" segment } ;   (* one tight lexer token; ".fsn" implied *)
segment        = identifier ;

pattern        = p_error | p_guarded ;
p_error        = "!" | "!" p_guarded ;                 (* bare "!" matches any error, binds nothing *)
p_guarded      = p_core [ "?" predicate ] ;
predicate      = pipe ;                                (* a `|` chain of functions; the matched value flows in *)
p_core         = p_literal | p_bind | p_wildcard | p_array | p_object ;
p_literal      = atom | "-" number ;                   (* "-" number is a negative literal *)
p_wildcard     = "_" ;
p_bind         = identifier ;

p_array        = "[" ( p_fixed_items | p_rest_items ) "]" ;
p_fixed_items  = [ p_items [ "," ] ] ;
p_rest_items   = [ p_items "," ] p_rest [ "," p_items ] [ "," ] ;
p_items        = p_item { "," p_item } ;
p_item         = p_guarded ;

p_object       = "{" ( p_fixed_pairs | p_rest_pairs ) "}" ;
p_fixed_pairs  = [ p_pairs [ "," ] ] ;
p_rest_pairs   = [ p_pairs "," ] p_rest [ "," ] ;
p_pairs        = p_pair { "," p_pair } ;
p_pair         = string ":" p_guarded ;

p_rest         = "..." [ identifier ] ;

```

### 2.6 Context-sensitive rules the grammar cannot express

Object literals and object patterns may not repeat a fixed key. `{"a": …, "a": …}`
is a `syntax_error`. Keys arriving through `...spread` / `...rest` are dynamic and
not checked.

A file-reference **path** is a single token, lexed only immediately after `@` or `@@`
with no intervening whitespace: tight `/`-separated `segment`s (identifiers) with an
optional leading `../` chain. So a `/` that is not part of such a path is division/invert:
`@a/b` is the path `a/b`, but `@a / b` is `@a` divided by `b`. `//` is always the
integer-quotient operator, never a path separator.

There are no negative-number tokens: `-` is always the negation/subtraction operator.
A negative literal is written `-` directly before a number — the parser folds it into a
literal in expressions, and `p_literal` admits it directly in patterns.

### 2.7 Operators (syntactic sugar)

Every operator here is **pure syntactic sugar**: it desugars to a pipe into an `@OP.*`
member (§7.6), or, for the map-pipes, into a stdlib call.

```
  -a           →  negative literal if a is a number, else  a | @OP.negate
  /a           →  a | @OP.invert
  ~a           →  a | @OP.not
  a + b + c    →  [a, b, c] | @OP.sum
  a - b        →  [a, b | @OP.negate] | @OP.sum      (numeric b folds: a - 42 → [a, -42] | @OP.sum)
  a * b * c    →  [a, b, c] | @OP.product
  a / b        →  [a, b | @OP.invert] | @OP.product
  a % b        →  [a, b] | @OP.modulo
  a // b       →  [a, b] | @OP.quotient
  a ?? b       →  [a, b] | @OP.compare
  a < b        →  [a, b] | @OP.compare | @OP.lt     (likewise <= / > / >= via @OP.lte / @OP.gt / @OP.gte)
  a == b == c  →  [a, b, c] | @OP.equal
  a && b && c  →  [a, b, c] | @OP.and
  a || b || c  →  [a, b, c] | @OP.or
  xs |: f      →  {"c": xs, "f": f} | @map
  xs |? f      →  {"c": xs, "f": f} | @filter
  xs |+ f      →  {"c": xs, "f": f} | @reduce
```

Folding and associativity:

- A maximal run of `+`/`-` folds into one `@OP.sum` over all terms; each `-` term is
  negated (a numeric literal folds to a negative literal, otherwise via `@OP.negate`).
- A maximal run of `*`/`/` folds into one `@OP.product`; each `/` term is inverted via
  `@OP.invert` (never a literal, so `1/x` stays a float and `/0` stays a runtime error).
- Runs of `==`, `&&`, `||` fold n-ary into `@OP.equal` / `@OP.and` / `@OP.or`.
- `%`, `//`, `??`, `<`, `<=`, `>`, `>=` are binary and left-associative; they sit at
  their level and break a fold run: `a * b % c` is `(a * b) % c`; `a ?? b == 0` is
  `(a ?? b) == 0`. Comparisons do not chain: `a < b < c` is `(a < b) < c`, which
  errors at runtime (a boolean is not comparable).

Because pipe binds tighter than the value operators, `x|@f + 1` is `(x|@f) + 1`; to pipe a
computed value onward, parenthesize it: `(a + b)|@f`, `(a < b)|@f`.

Comparisons: `a == b` is equality; `a < b` (and `<=` / `>` / `>=`) orders two numbers
or two strings. `??` exposes the underlying `-1`/`0`/`1` ordering that the comparison
desugaring reads through `@OP.lt` / `@OP.lte` / `@OP.gt` / `@OP.gte` (§7.2).

---

## 3. Functions and application

A function is an ordered list of clauses `pattern => expression`. The literal `()`
is the empty function, with no clauses.

Functions take exactly one argument. Multiple arguments are passed as an array or
object.

Applying a function to a value (`value | function`):
1. Clauses are tried in order. The first clause whose pattern matches `value`
   produces the result, evaluated with that clause's bindings in scope.
2. If a `?` predicate evaluates to an error during matching, that error becomes
   the function's result; no further clauses are tried (see §6.4).
3. If no clause matches:
   - Unmatched errors propagate.
   - For unmatched regular values the function returns `null`.

Functions are values: they may be elements of arrays, values of object keys, results
of clauses, and arguments to other functions. However, they may not cross the CLI
boundary (see §9.3).

---

## 4. Patterns and binding

A pattern both tests structure and extracts parts. Pattern forms:

| Form                                       | Matches                                    | Binds                              |
| ------------------------------------------ | ------------------------------------------ | ---------------------------------- |
| literal (`42`, `"x"`, `true`, `null`)      | exactly that value                         | nothing                            |
| `_` (wildcard)                             | anything **except** an error               | nothing                            |
| identifier (`a`)                           | anything **except** an error               | the value, under that name         |
| Fixed size arrays, e.g. `[x_1, x_2]`       | array of matching length, elementwise      | each `x_i` binds                   |
| Variable arrays, e.g. `[p, ...rest]`       | array with ≥ fixed elements                | `rest` = remaining elements        |
| Fixed member objects, e.g. `{"a": p}`      | object whose keys are **exactly** `a`      | as `p` binds                       |
| Variable objects, e.g. `{"a": p, ...rest}` | object having key `a` (extra keys allowed) | `rest` = unmatched key/value pairs |
| `p_core ? pred`                            | `p_core` matches **and** pred is `true`    | as `p_core` binds                  |
| `!`, `!_`, `!pat`                          | an error; `!pat` destructures the payload  | as `pat` binds                     |

Rules:

**Bare identifiers are holes**:
- In a pattern they bind. In an expression they read the value bound to that name in
  the current clause.
- Reading an unbound bare identifier yields an error.
- A bare identifier never denotes a builtin. Builtins are reached with `@` (see §7,
  §9.2).

**No sibling scope**:
- All bindings in a clause are produced simultaneously. A `?` predicate sees **only**
  the value matched by the pattern it is attached to and never another part of the
  same clause.
- For `!pat ? pred`, the `?` binds *inside* the `!` (the grammar parses it as
  `!(pat ? pred)`), so the predicate runs against the error's payload and sees exactly
  what `pat` binds. `(!a ? @Integer => ...)` checks whether the payload `a` is an integer.
- If a `?` predicate evaluates to an error, that error bubbles up as the function's
  result (see §6.4).

**`...rest` in patterns**:
- May appear at most once.
- In an array pattern it may appear in any position and captures the start / middle / end
  of the array.
- In an object pattern it must be the last member and captures all keys not explicitly matched.
- A bare `...` with no name matches without binding.
- An object pattern is **open** if it carries a `...rest` (named or bare `...`). Otherwise
  it is **closed**. A **closed** object pattern matches only objects whose keys are *exactly*
  the named keys. An **open** object pattern also matches objects with additional keys.

---

## 5. The `?` predicate (refinement / types)

`p_core ? predicate` matches when `p_core` matches structurally **and** piping the
matched value through `predicate` yields a **truthy** result. Truthiness is
Ruby-style: every value is truthy except `false` and `null` (so `0` and `""` are
truthy). The operators `@OP.and` / `@OP.or` / `@OP.not` apply the same test.

The predicate is a `|` chain of functions, and the matched value flows in from the
left: `a ? b | c` matches when `a` matches and `a | b | c` is truthy. A single-stage
predicate (`n ? @Integer`) is just the one-function case. Each stage is any
expression evaluating to a function (a name, a member access, or an inline function
literal). If applying the predicate produces an error, that error bubbles up as the
function's result (see §6.4).

"Types" are not a separate construct: the built-in predicates `@Integer`, `@String`,
etc. are ordinary functions returning booleans, reached with `@` and used with `?`
(e.g. `n ? @Integer`). User-defined predicates work identically (e.g. `n ? @isEven`).

---

## 6. Errors

An **error value** is `!` followed by a payload:
- `!null`
- `!42`
- `!"oops"`
- `!{"kind":"missing_key","key":"id"}`

The payload may be any regular Fusion value. Errors can't nest (§6.3). Instead the inner
error will propagate.

Error values are distinct from ordinary data:
- `null` means legitimate absence.
- An error means something went wrong.

Errors produced by the interpreter itself all share one standardized payload shape,
documented in §6.5.

### 6.1 Constructing errors

In expression position, `!` is a prefix operator that constructs an error from its
operand:

- `!42` is an error with payload `42`.
- `!"oops"` is an error with the string `"oops"` as payload.
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
| `!_`                | any error; payload is not bound. Can carry a predicate (`!_ ? @pred`).   |
| `!pattern`          | any error with a **payload** that matches `pattern`                      |

The payload pattern (the `pattern` in `!pattern`) is a full `p_guarded`:
- It uses the same destructuring semantics you know from regular values.
- It fully supports `?` predicates. Predicates only refer to the payload, not the `!`.
  Caution: `! ? @Integer` is a syntax error. The bare `!` has no payload pattern
  for the predicate to refer to. Use `!_ ? @Integer` instead.
- It cannot itself contain another `!`. At runtime there is no error nested inside another error
  or value. Errors propagate before they can sit inside a collection, so this syntax is rejected
  at parse time.

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
- **Built-in and stdlib operations (`@math.divide`, `@OP.sum`, `@Integer`, …) all
  propagate** their input error without examining it. To inspect or compare an
  error's payload, you must catch it first and operate on the extracted payload:
  `!42 | (!a => a) | @Integer` returns `true` (the payload `42` *is* an integer);
  `!42 | @Integer` returns `!42` (the predicate doesn't handle the error,
  evaluates to `!42` and that becomes the return value of the whole function).
- **Building an array or object propagates** any error encountered while
  evaluating an element/member. `[1, !"bad", 2]` evaluates to `!"bad"`, not to
  an array of three things.
- **Constructing an error from an erroring expression** propagates the inner
  error rather than wrapping it. `!([5,0] | @math.divide)` evaluates to the division
  error itself (a `math_error`, §6.5), never to an error wrapping an error. (This
  preserves the rule that there is never more than one error simultaneously.)
- **When the function value itself is an error** (e.g. `value | @undefined_name`
  where `@undefined_name` resolves to an error), that error is the result.

### 6.4 `?`-predicate errors bubble up

If a `?` predicate evaluates to an error (the predicate function itself errored,
or it was a non-function error value), that error becomes the function's return
value immediately. Subsequent clauses are **not** tried — predicate-errors are
treated as program failures, not as "no match." This is the key reason to keep a
`?` predicate from raising: a predicate that can crash will short-circuit your
whole function. A non-matching input is not a crash — it falls through to `null`
(falsey) — so a predicate needs no `_ => false` catch-all to be safe here.

### 6.5 The standardized error payload

There are two origins of error values, and they differ in payload:

- **Interpreter errors** — produced by the language itself (a bad built-in call,
  an unresolved `@`-reference, a parse failure, …). Every interpreter error
  carries one **standardized payload**: a JSON object with a fixed set of fields,
  documented here. The uniform shape lets one catch clause dispatch on a single
  field, e.g. `(!{"kind": "math_error"} => …)`. Standard library functions
  adhere to this same structure.
- **User errors** — built with `!payload` (§6.1). The payload is whatever you
  give it: any Fusion value, with no required shape.

#### Payload shape

```json
{"kind": "argument_error", "origin": "builtin", "operation": "@math.divide", "status": 0, "input": [1, "x"], "expected": ["[_ ? @Number, _ ? @Number]"]}
```

| Field       | Required | Meaning                                                                                                                    |
| ----------- | -------- | -------------------------------------------------------------------------------------------------------------------------- |
| `kind`      | yes      | The error category. Possible values are defined below.                                                                     |
| `origin`    | yes      | Where the failing operation is *defined*. Possible values are defined below.                                               |
| `file`      | no       | The **innermost user-code file** on the call chain. `builtin`/`stdlib` frames are skipped. The path is **relative to** `Dir.pwd`. Contains `"<inline>"` for errors in the CLI `-e` option or the REPL. Contains `"<fusion>"` for an error above all user code (e.g. `stdin` present, but `code` is not a function). Present for `builtin`/`stdlib`/`code` origins; absent for a channel/runtime origin (`input`/`output`/`interpreter`). |
| `operation` | yes      | The operation that failed. All `@`-references are named by their **source text**. A syntactic operation uses its form (`"\|"`, `".name"`, `"[]"`, `"parsing code"`, `"parsing JSON"`). Loading the top-level program file uses `"loading code"`. |
| `status`    | yes      | `0` or `1`. Whether the operation received an ordinary value (`0`) or an error value (`1`)                                 |
| `input`     | yes      | The operation's input. A 0-argument operation (every `@`-reference except `@load`) carries `null`.                         |
| `expected`  | no       | The acceptable inputs as a list of Fusion **patterns**. The input matched none of them.                                    |
| `message`   | no       | Extra human-readable detail, e.g. `"division by zero"`. Absent whenever `expected` is present.                             |

#### Possible values for `kind`

| `kind`                | Raised when                                                                                                    |
| --------------------- | -------------------------------------------------------------------------------------------------------------- |
| `syntax_error`        | source code or the JSON input fails to parse.                                                                  |
| `reference_error`     | an `@`-reference cannot be resolved: unknown name, file not found, a file-system failure, a non-productive data cycle, a target outside the jail (§9.2), no enclosing file for `@@` (§9.2). |
| `argument_error`      | a value has the wrong shape or type for an operation: a built-in given the wrong number/shape of arguments (e.g. not a pair) or a wrong-typed value, applying a non-function, spreading a non-array/object, member access on a non-object, a wrong-typed index, or an `array`/`object`-mode input envelope of the wrong shape (§9.4). Its `expected` lists the acceptable inputs as patterns. |
| `binding_error`       | reading an unbound identifier, or binding the same name twice in one clause.                                   |
| `access_error`        | a missing object key or an out-of-range array index.                                                           |
| `math_error`          | division or modulo by zero, or a non-finite number.                                                            |
| `conversion_error`    | a value cannot be converted (`@toString` of an unconvertible type, `@parseNumber` of a non-numeric string).    |
| `limit_error`         | a runtime resource limit was exceeded. `"stack level too deep"`.                                               |
| `internal_error`      | an interpreter BUG. Please open an issue.                                                                      |
| `serialization_error` | a result/error value has no JSON form. It contains functions or non-finite numbers. See §9.                    |

#### Possible values for `origin`

| `origin`      | Meaning                                                                  |
| ------------- | ------------------------------------------------------------------------ |
| `builtin`     | a built-in operation (named by its `@`-reference in `operation`).        |
| `stdlib`      | a standard-library function (named by its `@`-reference in `operation`). |
| `code`        | user source core (a file or an inline expression (`-e`/REPL).            |
| `input`       | the input channel (stdin). Usually syntax errors.                        |
| `output`      | the output channel. Usually serialization errors.                        |
| `interpreter` | the interpreter itself, e.g. a stack overflow.                           |

`input` and `output` name the data channels; they **never** refer to the program
source, which always reports as `code`.

User errors don't have to adhere to this standard.

---

## 7. Built-in functions

All built-ins are ordinary one-argument functions, **reached with an `@` prefix**
(`@size`, `@Integer`, …); see §9.2 for how `@name` resolves. The names in the tables
below are the built-in names; write `@` before them to use them. **Operations** return
`!` on type-invalid or domain-invalid input. **Predicates** return `false` on any
input that is not of the queried type (they never return `!`).

The operators (`+ - * / == < …` and the boolean ops) live in the shadowable `@OP`
object (§7.6); a directory reskins them by placing an `OP.fsn`.

### 7.1 Arithmetic

In source you normally write the infix sugar of §2.7 — `a + b`, `-a`, `a * b`, `a % b`,
`a // b` — which desugars to the members below. Addition, multiplication and negation are
`@OP.sum` / `@OP.product` / `@OP.negate` (§7.6); subtraction is `[a, b | @OP.negate] | @OP.sum`.
Integer division/remainder are `@OP.quotient` / `@OP.modulo`. Numerically correct
division and the other numeric functions live in `@math` (§7.6a): `@math.divide`,
`@math.floor`, `@math.round`, `@math.abs`, `@math.log`, `@math.sqrt`, etc.

### 7.2 Comparison

Equality is `@OP.equal` (deep structural equality of a pair; §7.6) — used directly,
there is no `@eq` helper. Ordering is `@OP.compare`, which returns `-1`/`0`/`1`. The
comparison members **interpret that result** and are applied *after* it:

| Member   | `-1`   | `0`    | `1`    | `null` |
| -------- | ------ | ------ | ------ | ------ |
| `OP.lt`  | `true` | `false`| `false`| `null` |
| `OP.gt`  | `false`| `false`| `true` | `null` |
| `OP.lte` | `true` | `true` | `false`| `null` |
| `OP.gte` | `false`| `true` | `true` | `null` |

`a < b` desugars to exactly this pipeline: `[a, b] | @OP.compare | @OP.lt` (likewise
`<=` / `>` / `>=`; equality is `a == b` — see §2.7). Both steps resolve `@OP` per
directory, so an override reskins the ordering and its reading together. A partial
order whose `compare` returns `null` for incomparable operands passes that `null`
straight through; any other input is an `argument_error`. A type mismatch surfaces
as `@OP.compare`'s own error, before the reader runs.

### 7.3 Boolean

The truthiness operators live in `@OP` (§7.6): `@OP.and`, `@OP.or`, `@OP.not`, written
with the sugar `a && b`, `a || b`, `~a` (§2.7). They
judge truthiness (every value is truthy except `false` and `null`), not strict
booleans, and always return a boolean. There are no top-level `@and`/`@or`/`@not`.
The stdlib helpers `@truthy` and `@falsey` reduce any single value to its truthiness
by **pattern matching** (independent of any `@OP` override): `@truthy` is `true` for
everything except `false`/`null`, and `@falsey` is its complement.

### 7.4 Strings and structure bridges (operations)

| Name          | Input                       | Result                                  |
| ------------- | --------------------------- | --------------------------------------- |
| `size`        | string / array / object     | element/character/key count (integer)   |
| `join`        | `[array-of-strings, separator]` | the elements joined by the separator string |
| `split`       | `[string, separator]`       | array split on the **literal** separator (an empty separator splits into characters), keeping empty fields |
| `toString`    | any                         | string form of the value                |
| `parseNumber` | string                      | integer or float; `!` if not numeric    |
| `keys`        | object                      | array of key strings                    |
| `values`      | object                      | array of values                         |
| `toObject`    | `[[string-key, value], …]`  | object built from entries; later duplicate keys win |

`concat` (`[string, string]` → concatenation) and `chars` (string → array of its
characters) are **standard-library** functions built on `join` / `split`, not
built-ins.

Indexed read (`x[k]`) and write (`x[k = v]`) are **core syntax**, not built-ins — there
is no `@get`/`@set`; see §8.

### 7.5 Type predicates (predicates)

Each of these functions takes any input value and returns a boolean. This set of
functions provides a runtime type system.

| Name        | `true` for                           | Equivalent pattern |
| ----------- | ------------------------------------ | ------------------ |
| `Null`      | `null`                               | `null`             |
| `Boolean`   | `true`, `false`                      |                    |
| `Integer`   | integers                             |                    |
| `Float`     | floats                               |                    |
| `Number`    | integers and floats                  |                    |
| `String`    | strings                              |                    |
| `Array`     | arrays                               | `[_]`              |
| `Object`    | objects                              | `{_}`              |
| `Function`  | any function (builtin, stdlib, user) |                    |
| `NonFinite` | "Infinity", "-Infinity", "NaN"       |                    |

Notes:
- Booleans are separate from numbers. There's no automatic type conversion (`false` <-> `0`, `true` <-> `1`).
- The set of values without JSON representation (§9.3) is exactly `Function` + `NonFinite`

### 7.6 The `@OP` object (the operators)

`@OP` is a built-in **object**, reached by member access (`@OP.sum`, `@OP.and`, …),
holding the arithmetic/comparison/boolean operators. Its members generalise to an
**array of any length** (`sum`/`product`/`and`/`or` fold; `equal` is deep over all
elements); `compare` reports an ordering. The infix operators (§2.7) desugar to these members.

`@OP` is **shadowable per directory**: place an `OP.fsn` sibling that overrides members
(spread the originals with `@@`) to reskin the operators — complex numbers, matrices,
ternary logic — for that directory only. The comparison members (§7.2: `lt`, `gt`,
`lte`, `gte`) interpret an `@OP.compare` *result* rather than comparing values
themselves, so an override of `compare` alone already reskins `a < b` (see the
how-to guide).

| Member        | Input                                    | Result                                                   |
| ------------- | ---------------------------------------- | -------------------------------------------------------- |
| `OP.sum`      | array of numbers                         | sum (`0` for `[]`)                                        |
| `OP.product`  | array of numbers                         | product (`1` for `[]`)                                    |
| `OP.negate`   | number                                   | negation                                                 |
| `OP.invert`   | number                                   | reciprocal `1/x`, always a float; `!` if `0`             |
| `OP.quotient` | `[integer, integer]`                     | integer division; `!` on a non-integer or a `0` divisor  |
| `OP.modulo`   | `[integer, integer]`                     | integer remainder; `!` on a non-integer or a `0` divisor |
| `OP.equal`    | array (any element types)                | deep equality: `true` iff every element equals the first |
| `OP.compare`  | `[number, number]` or `[string, string]` | `-1` / `0` / `1` (first smaller / equal / larger)        |
| `OP.lt`       | a compare result (`-1`/`0`/`1`/`null`)   | `true` for `-1`, else `false`; `null` passes through     |
| `OP.gt`       | a compare result                         | `true` for `1`                                           |
| `OP.lte`      | a compare result                         | `true` for `-1` / `0`                                    |
| `OP.gte`      | a compare result                         | `true` for `0` / `1`                                     |
| `OP.and`      | array                                    | `true` if every element is truthy (`true` for `[]`)      |
| `OP.or`       | array                                    | `true` if any element is truthy (`false` for `[]`)       |
| `OP.not`      | `_`                                      | `true` if the operand is falsey                          |

### 7.6a The `@math` object (numeric functions and constants)

`@math` is a built-in object (shadowable like `@OP`) of numeric functions and two
constants. `pi`/`e` are plain values; the rest are one-argument functions. A
non-finite input to `round`/`floor`/`ceil`, a `log` of a non-positive number, and a
`pow` with a complex result are `math_error`s.

| Member        | Input                | Result                                                     |
| ------------- | -------------------- | ---------------------------------------------------------- |
| `math.pi`     | —                    | `3.141592653589793` (a value, not a function)              |
| `math.e`      | —                    | `2.718281828459045` (a value)                              |
| `math.round`  | number               | nearest integer (half away from zero)                      |
| `math.floor`  | number               | floor (integer)                                            |
| `math.ceil`   | number               | ceiling (integer)                                          |
| `math.divide` | `[number, number]`   | quotient, always a **float**; `!` if divisor is 0          |
| `math.sign`   | number               | `-1` / `0` / `1`                                           |
| `math.abs`    | number               | absolute value (keeps int/float)                           |
| `math.rand`   | `null` or a positive integer `n` | float in `[0, 1)`, or integer in `[0, n)`      |
| `math.sin`    | number               | sine (radians), float                                      |
| `math.cos`    | number               | cosine (radians), float                                    |
| `math.exp`    | number               | `e^x`, float                                               |
| `math.log`    | positive number      | natural log, float; `!` on a non-positive number           |
| `math.pow`    | `[base, exponent]`   | `base^exp` (integer when base and non-negative integer exponent; else float); `!` on a complex result |
| `math.sqrt`   | non-negative number  | square root (float); `!` on a negative number              |

### 7.7 Special built-ins: `ENV` and `load`

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

Member access (`.`), index read (`[]`), and index write (`[=]`) are **core syntax**,
evaluated directly by the runtime. There are no `@get`/`@set` built-ins.

- `x.key` — if `x` is an object containing `key`, its value; otherwise `!`.
- `x[expr]` — **read**: if `x` is an array and `expr` is an integer in range, the element
  (negative indices count from the end); if `x` is an object and `expr` is a string key
  that exists, its value; otherwise `!`.
- `x[key = value]` — **write**: a **new** array/object with that one entry set; `x` itself
  is unchanged. An array index must already exist (arrays are not extended; negative
  indices count from the end); an object key may be new. `!` on a bad index/type.

`.`, `[]`, and `[=]` are postfix and bind tighter than every operator (including `|`).

---

## 9. Files, references, and the runtime

### 9.1 Files

A `.fsn` file contains **exactly one expression**, which is its value. A file is
**executable** if that value is a function.

### 9.2 References

A `@` reference takes one of these forms:

- **`@`** (nothing after it) — the value of the **current top-level unit**: the
  current file, or the inline (`-e`) / REPL entry being evaluated. Used for
  self-recursion.
- **`@@`** (super) — the built-in or standard-library value the current file
  **shadows**: the file's own name resolved by steps 2–3 below, skipping the
  sibling step (which would be the file itself). Lets an override refer to the
  original method, e.g. `add.fsn` containing `@@` refers to the stdlib `add`.
  Outside a file (inline `-e` / REPL) there is no name to take super of, so it is a
  `reference_error` (`no enclosing file`).
- **`@@name`, `@@dir/name`** — super with an explicit name: resolve `name` by
  steps 2–3 below, skipping its sibling. The **stable** form of a reference — a
  local shadow cannot intercept it (used inside an `OP.fsn` as `@@OP`, and by
  error patterns that must stay canonical). `@@../…` is a syntax error.
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

If none match, the result is `!`. Downward paths participate fully: `@util/helper`
checks a sibling `util/helper.fsn`, then a built-in named `util/helper`, then a stdlib
`util/helper.fsn`.

**Resolution of upward paths** (any reference containing `../`) is **file-only**: it
resolves solely to a file relative to the referencing directory and never falls back
to a built-in or the standard library.

The `.fsn` extension is implied and never written in a `@` reference. File resolution
is relative to the **referencing file's** directory; built-ins and the standard
library are global to the runtime but, per the order above, are shadowed by a sibling
file of the same name. That shadowing is per-directory, not global.

**Confinement (the jail).** File-backed resolution is confined to a *jail*: a directory
and its subtree, set by `-j`/`--jail` and defaulting to the program's directory (the
working directory for `-e` and the REPL). All `@`-references and the builtin `@load`
respect the jail. Referencing a file outside the jail is a `reference_error`
(`outside the jail`). An existing sibling outside the jail fails this way too — it does
*not* fall back to a built-in or the stdlib, so a forbidden file fails loudly rather than
silently resolving elsewhere. References still resolve relative to the referencing file;
the jail only filters the result. The standard library is always reachable regardless of
the jail, and stdin is never affected — it is plain JSON, never an `@`-reference.
Confinement is lexical (it normalises `..`) and follows existing symlinks. It confines
references to a directory tree; it is not a security sandbox and needs none, since Fusion
cannot write files. Pass `--jail '*'` to disable confinement entirely.

**Built-ins are reached through this same mechanism**: `@size`, `@Integer`, etc. are
`@name` references that resolve at step 2. A *bare* identifier (without `@`) is only
a pattern hole; it never denotes a built-in.

Two built-ins are special in how they resolve:

- **`@ENV`** resolves (at step 2) to a fresh object of environment variables.
- **`@load`** resolves (at step 2) to a function that loads a file by a **verbatim**
  filename string — no `.fsn` is appended — relative to the referencing directory,
  returning that file's value. A non-string argument is an `argument_error`; a
  missing file is a `reference_error` (`file not found`). This is the only way to load
  a file whose name is computed at runtime or is not a plain identifier (e.g.
  `"data.config.fsn"`).

References are:

- **Lazy** — resolved when evaluated/applied, not when a file loads. A file may
  reference itself (recursion) or another file may reference it back (mutual
  recursion) without an infinite load loop.
- **Memoized** — each file path is loaded and evaluated once per run; shared
  dependencies load once.

A **non-productive data cycle** (files whose values reference each other as data, not
through a function boundary) yields `!` at the point of the cyclic self-reference.
This error then immediatly bubbles up according to the propagation semantics described
above. Recursion through functions is not a data cycle.

### 9.3 Runtime contract

The **pipe** use case (`--pipe`, and the default whenever any argument is given —
see §9.7) reads standard input as JSON, converts it to a Fusion value `v`,
computes `v | programFunction`, and prints the result on standard output as JSON.
When standard input is empty, the program get evaluated and immediately becomes
the result instead.

- Input always arrives on standard input; there is no input argument.
- **Empty input means "no input": the program's own value is the result.** A
  `.fsn` file therefore doubles as enriched JSON data — it can compute, read
  `@ENV`, and pull in `@`-references, then print the value with no pipeline
  input. (Under `-!` the input is an error value instead; empty input then has no
  payload to mark, which is a usage error — see §9.4.)
- Non-JSON input yields a `syntax_error` at `origin: "input"` (§6.5).
- **If the final result is an error**, the interpreter prints **nothing** to
  standard output, prints the error's **payload** (as JSON) to standard error, and
  exits with status `1`. Otherwise the result is printed to standard output and the
  interpreter exits `0`. This makes Fusion programs first-class Unix filters: the
  stdout stream carries the value-or-nothing, the stderr stream carries the failure
  detail, and the exit code is `0`/`1` accordingly.

This stdout/stderr/exit-code split is the **unix** output mode — the default for
the pipe use case. §9.4 describes the other ways an error can cross the boundary,
§9.5 the streaming use case, and §9.6 the REPL.

**Serialization.** A function and a non-finite float number have no JSON form.
How one is rendered depends on where it sits:

- In a **result** or inside a **user error's** payload, they can't be serialized.
  The whole output becomes a `serialization_error`.
- Inside an **interpreter error's** payload, it is serialized leniently as a
  string:
  - a function renders as `"<function>"`
  - a non-finite number as `"<Infinity>"` / `"<-Infinity>"` / `"<NaN>"`

Note:
- If a regular value or user error fails to serialize strictly, the resulting
  `serializaton_error` will be an interpreter error and will subsequently
  serialize leniently to preserve as much information about the root error as
  possible.

### 9.4 Input and output modes

An error value cannot cross the CLI boundary as plain JSON — something must mark
it as an error. The **input mode** and the **output mode** define that marking.
They are independent of each other and selected with the `--input` and `--output`
flags:

- **`unix`** — the input is plain JSON and always a value; the `-!` flag marks
  the whole input as an error value instead (its JSON becomes the payload). `-!`
  therefore requires input: with empty input there is no payload to mark, which
  is a usage error (the program does not run). Output: a value goes to stdout
  with exit code `0`; an error's payload goes to stderr with exit code `1`
  (§9.3).
- **`bang`** — a leading `!` marks an error value; the payload is the JSON after
  the `!`. A lone `!` is `!null`, like the language's bare `!`. Output is always
  on stdout and the exit code is always `0`. A `!`-marked line is not valid JSON;
  that is the price of the most lightweight marking, so `bang` is recommended only
  between Fusion programs — for anything that must stay valid JSON, use `array` or
  `object`.
- **`array`** — everything is wrapped in an envelope: `[0, value]` for a value,
  `[1, payload]` for an error. Every line is valid JSON, which is why it is the
  `--stream` default (§9.5). Output is always on stdout, exit code always `0`.
- **`object`** — the envelope is `{"value": value}` for a value, `{"error": payload}`
  for an error. Output is always on stdout, exit code always `0`.

A malformed `array`/`object` input envelope (any other shape; the array tag must
be exactly the integer `0` or `1`) is an `argument_error` at `origin: "input"`.
Like any input failure it flows into the program as an error and is catchable.

Mode support per use case (defaults in bold):

| Use case   | `unix`   | `bang`   | `array` | `object` |
| ---------- | -------- | -------- | ------- | -------- |
| pipe       | **yes**  | yes      | yes     | yes      |
| `--stream` | no       | yes      | **yes** | yes      |
| `--repl`   | —        | —        | —       | —        |

The unix mode spends the process's only exit code and both standard streams on a
single result, so it cannot mark errors per record in a stream; the stream use
case therefore excludes it. Stream defaults to `array` rather than `bang` so each
record stays valid JSON (NDJSON, §9.5); `bang` remains available as the cheapest
encoding for Fusion-to-Fusion pipelines. The REPL is interactive and has no modes
at all.

### 9.5 Streaming (`--stream`)

`fusion --stream` loads the program once, then treats standard input and output
as [NDJSON](https://github.com/ndjson/ndjson-spec) streams: each input line is
decoded per the input mode, piped through the program, and printed as one output
line encoded per the output mode. Input and output default to the **array** mode
(not `bang`) so every line is valid JSON. The media type is
`application/x-ndjson` and the file extension for storing such a stream should
be `.ndjson`.

NDJSON conformance:
- Every output record is a single JSON text in UTF-8, terminated by `\n`, and
  never contains an embedded newline or carriage return.
- Both `\n` and `\r\n` are accepted as input line delimiters.
- A blank input line (empty or whitespace-only) carries no record, so the program
  never runs on it. By default it is echoed as a blank output line, keeping input
  and output aligned line-for-line. Pass `--skip-blank-lines` to drop blank lines
  instead. Every non-blank line produces exactly one output line.

- Errors stay in-band, so a failing record — including a stack overflow — becomes
  that record's output line and the stream continues. The exit code is always `0`.
- A program that fails to load will return the same load error for every record.

### 9.6 The REPL (`--repl`)

`fusion --repl` starts an interactive session — as does a bare `fusion` with no
arguments at all (§9.7). It loads no program, takes no pipeline input, has no
input/output mode, and always exits `0`. Each entry is read, evaluated, and its
result printed. An entry is one of:

- an **expression** — evaluated and printed; or
- a **statement** — an assignment that also binds a name:

```ebnf
statement = identifier "=" expr ;
```

A statement evaluates `expr`, prints the result, and binds it to `identifier`
for later entries. Bare identifiers read earlier bindings; `@`-references resolve
relative to the working directory.

- Results print leniently (§9.3): a function prints as `"<function>"` instead of
  becoming a `serialization_error`.
- An error prints as `!payload`. A statement binds an error result like any other
  result; reading that identifier later propagates the error, exactly as reading an
  `@`-reference that resolved to one. (Pattern binders never capture an error, but a
  statement is an assignment, not a pattern match.)
- Rebinding a name is allowed; later entries see the new value.
- A bound function can call itself through its own name
  (`fact = (0 => 1, n => [n, [n,-1] | @OP.sum | fact] | @OP.product)`), because
  the name is looked up at application time.
- Entries report errors at `origin: "code"` with `file: "<inline>"`, like `-e` programs.

**Input editing.** An entry is submitted only once it parses as a complete
statement or expression; until then the session opens a new line so the entry
can be finished or corrected. An entry may therefore span multiple lines
(continuation lines show `...> `); on an empty continuation line, backspace
returns to the previous line. The prompt and the echoed input render on **stderr**
(like a shell prompt), so stdout carries only the stream of results.
The prompt is shown in light blue, and each result is preceded **on stderr**
by a green `✔` (a value) or a red `✗` (an error); these
are decorations only — the result itself stays unstyled on stdout. End the
session with Ctrl-D; Ctrl-C discards the entry being typed.

### 9.7 Command-line interface

```
usage: fusion [options] <file.fsn>
       fusion [options] -e '<source>'
       fusion --repl

use cases (default: --repl with no arguments, otherwise --pipe):
  -p, --pipe      apply the program to stdin; with no input, the
                  program's own value is the result
  -s, --stream    apply the program to each line of an NDJSON stream
  -r, --repl      interactive expressions and `identifier = expression`

options:
  -e, --execute '<source>'
                  inline program instead of a file
  -i, --input MODE
                  how the input marks an error value (§9.4)
  -o, --output MODE
                  how the output marks an error value (§9.4)
  -j, --jail DIR  confine @-references to DIR and its subtree
                  (default: the program's directory; '*' disables it; §9.2)
  -!              treat the input as an error value (unix input mode only)
  -b, --skip-blank-lines
                  drop blank input lines instead of echoing them (--stream, §9.5)
```

**Selecting a use case.** At most one of `--pipe`, `--stream`, `--repl` may be
given; passing two is a command-line misuse. With none, a bare `fusion` (no
arguments at all) starts the REPL, while any other invocation is a pipe run. So
`--pipe` is needed only to be explicit, `fusion file.fsn` already implicitly
use `--pipe`.

In the pipe use case, input comes from standard input; when standard input is
empty, the program's own value is the result (§9.3). The stream use case also
reads standard input. Neither accepts an input argument.

Every flag has a short and a long form (`-p`/`--pipe`, `-i`/`--input`, …), except
`-!`, which has only the short form. Each of `--input`/`--output` may only be used
once. Multiple different modes for one direction is a misuse.

A command-line misuse (an unknown flag, more than one use case, two different
modes for one direction, an unsupported mode combination, a missing program) is
reported as plain usage text on stderr with exit code `1`. It happens before the
input/output contract begins, so it is not a payloaded error.
