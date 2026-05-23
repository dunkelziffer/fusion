# Fusion — a language grammar (rev 4)

*JSON + pattern-matching functions. Functions take one input, return one output,
and dispatch by destructuring. Application is `value | function`.*

**Changes in rev 4:**
- **A file contains exactly one value** — a function, array, object, or atom.
  Nothing else. No statement list, no top-level bindings.
- A file is **executable** iff its value is a function; the runtime computes
  `STDIN | thatFunction` and serializes the result.
- **File references**: `@a` evaluates to the value in `a.fsn` (same dir).
  `@../a` = parent dir, `@dir/a` = subdirectory. This is the module system AND
  how the standard library is delivered. No `import` primitive needed.
- References are **lazy** (resolved on use) and **memoized** per path. Self- and
  mutual recursion work because resolution is deferred until application.
- Recursion uses self-reference: inside `fact.fsn`, `@fact` means this file.

(Earlier locked decisions from rev 3 unchanged: `?`-predicates as types, error
value `!`, strict ⇔ propagating, no sibling scope in patterns, no operator sugar.)

---

## Core ideas

- **Atoms:** `null`, `!`, booleans, integers, floats, strings.
- **Composites:** arrays `[...]`, objects `{...}` — JSON syntax.
- **Functions:** `(pattern => expr, ...)`; ordered clauses; first match wins;
  lenient → `null` on no match, strict (final `_ => !`) → `!`.
- **Application:** `value | function`, left-associative.
- **Bare identifiers** are holes (bind in patterns, read in expressions).
- **`@path`** references another file's value.
- **A whole file is one expression** — the value above is all the file contains.

---

## Precedence (tightest first)

1. grouping `( )`, literals, array/object/function literals, identifiers, `@path`
2. postfix member/index access: `x.k`, `x[i]`
3. `|`   (pipe / application, left-associative)
4. `=>`  (clause arrow — loosest)

---

## Grammar (EBNF)

```ebnf
(* ===== A file is exactly one value ===== *)
file        = expr ;

(* ===== Expressions ===== *)
expr        = pipe ;
pipe        = postfix { "|" postfix } ;
postfix     = primary { "." identifier | "[" expr "]" } ;
primary     = atom
            | array
            | object
            | function
            | identifier
            | fileref
            | "(" expr ")" ;

fileref     = "@" refpath ;
refpath     = { "../" } segment { "/" segment } ;   (* no extension; .fsn implied *)
segment     = identifier ;

(* ===== Literals ===== *)
atom        = "null" | "!" | "true" | "false" | number | string ;

array       = "[" [ elem { "," elem } [ "," ] ] "]" ;
elem        = expr | spread ;
spread      = "..." expr ;

object      = "{" [ member { "," member } [ "," ] ] "}" ;
member      = string ":" expr | spread ;

(* ===== Functions ===== *)
function    = "(" clause { "," clause } [ "," ] ")" ;
clause      = pattern "=>" expr ;

(* ===== Patterns ===== *)
pattern     = corepat [ "?" predicate ] ;     (* predicate sees ONLY this subtree *)
predicate   = postfix ;
corepat     = literalpat | bindpat | wildcard | arraypat | objectpat ;
literalpat  = atom ;                          (* includes `!` and `null` *)
wildcard    = "_" ;                           (* matches anything except `!` *)
bindpat     = identifier ;
arraypat    = "[" [ pelem { "," pelem } [ "," ] ] "]" ;
pelem       = pattern | "..." [ identifier ] ;
objectpat   = "{" [ pmember { "," pmember } [ "," ] ] "}" ;
pmember     = string ":" pattern | "..." [ identifier ] ;

(* ===== Lexical ===== *)
identifier  = letter { letter | digit | "_" } ;
number      = int_lit | float_lit ;
int_lit     = [ "-" ] digit { digit } ;
float_lit   = int_lit "." digit { digit } [ exp ] | int_lit exp ;
exp         = ("e" | "E") [ "+" | "-" ] digit { digit } ;
string      = '"' { char | escape } '"' ;
```

---

## File / reference semantics

- **`@a` → value of `a.fsn`**, resolved relative to the *referencing file's*
  directory (relocatable, like Node relative `require`).
  - `@a` = `./a.fsn`,  `@../a` = `../a.fsn`,  `@dir/a` = `./dir/a.fsn`.
- **Lazy**: a reference resolves when evaluated/applied, not at load time. This is
  what makes self-recursion (`@fact` inside `fact.fsn`) and mutual recursion
  (`@even` ↔ `@odd`) work, and means unused references are never loaded.
- **Memoized**: each path loads/evaluates once; diamond deps load once.
- **Data cycles** (e.g. `a.fsn` = `[1, @b]`, `b.fsn` = `[2, @a]`) are
  non-productive; the runtime detects them and yields `!`. Function-recursion
  cycles are fine (guarded by pattern matching on input).
- **Standard library** = a directory of `.fsn` files shipped with the runtime.
  TODO: one stdlib root prefix (e.g. `@std/map`) vs pure-relative only — see notes.

### Runtime contract
- Parse stdin as JSON → Fusion value `v`; compute `v | fileFunction`; print result
  as JSON. A final result of `!` → nonzero exit code. Non-JSON stdin → `!` (TBD).

---

## Examples

```fusion
// double.fsn
(n => [n, 2] | multiply)

// fact.fsn — @fact is this file (self-reference = recursion)
(0 => 1, n ? Integer => [n, [n,1]|subtract|@fact] | multiply, _ => !)

// map.fsn
(
  {"f": _, "xs": []} => [],
  {"f": f, "xs": [x, ...rest]} => [x | f, ...({"f": f, "xs": rest} | @map)]
)

// main.fsn — executable; uses two sibling files
(xs => {"f": @double, "xs": xs} | @map)
```
```sh
echo '[1,2,3]' | fusion main.fsn     # => [2,4,6]
```
