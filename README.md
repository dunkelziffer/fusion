# Fusion

The reference implementation of the Fusion language.

> :warning: This project is in an Alpha stage and still subject to rapid and unannounced breaking changes.

**Fusion** is a small programming language. It is "functional JSON". It is JSON's data
model (atomic values, arrays, objects) plus one more ingredient, the function. Functions take
one input and one output and work by pattern-matching.

## Elevator pitch - a 1-minute taste of the ideas

**A file is one value**:
- A program is simply a file containing a single function.
- Executing it means evaluating `STDIN | thatFunction`.
- Regular result values get printed to `STDOUT`.
- Errors get printed to `STDERR` and set exit code `1`.

**Pattern matching is the only control flow**:
- Pattern matching is a better `if` statement.
- A `for` loop is recursion on lists.

**Bare words are holes**:
- They bind in patterns and read in results
- So a pattern and a result are mirror images: `([a, b] => [b, a])` swaps a pair.

**Types are predicates**:
- `n ? @Integer` matches only integers.
- `@Integer` is just a built-in function and you could use any of your own functions as well.

**Errors have payloads**:
- An error is `!` followed by a payload value (e.g. `!"divide by zero"`, `!42`, `!{"kind":"missing_key",...}`).
- Errors propagate unless caught with an error pattern like `!msg`, `!42`, or just `!`.
- Pattern matching works the same way on error payloads as on regular values.

**One `@` namespace for everything**:
- `@name` can access a sibling file `name.fsn`, a standard library file `$STDLIB_DIR/name.fsn` or the builtin `name`.
- Sibling files can shadow the standard library and builtins.
- A bare `@` refers to the current file for easier recursion.
- `@ENV` allows read access to environment variables.
- `name | @load` loads a file by name. Useful for dynamic file access or file names with special characters.

## Installation

To use **Fusion** as a real scripting language, install it globally on your system:
```bash
gem install fusion-lang
```

To use any `Fusion` modules from another Ruby program, add it to your `Gemfile`:
```ruby
gem "fusion-lang", require: "fusion"
```

## How to run your code

```sh
echo '5' | fusion examples/factorial.fsn        # => 120
echo '15' | fusion examples/fizzbuzz.fsn        # => "FizzBuzz"
fusion examples/factorial.fsn 5                 # => 120 (input as an argument)
fusion -e '(n => [n,2] | @multiply)' 21         # => 42 (inline program)
printf '[1, 2]\n[3, 4]\n' | fusion --stream examples/double.fsn   # => [2,4] [6,8] (NDJSON, one value per line)
fusion --repl                                   # interactive `name = expression;` statements
```

- Input is read from stdin (or the 2nd CLI arg) as JSON and parsed into a Fusion value.
- The file's function gets applied to this value: `value | function`
- The result gets printed as JSON to stdout.
- Errors get printed to stderr instead and set exit code `1`.
- How errors cross the boundary is configurable per side (`--input` / `--output`);
  see the [reference](docs/user/reference.md) §9.4.

## Documentation

Refer to the [Documentation](docs/index.md) for further information.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Run `bin/console` for an interactive prompt that will allow you to experiment.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
