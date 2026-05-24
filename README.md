# Fusion — "functional JSON"

> :warning: This project is in an Alpha stage an still subject to rapid and unannounced breaking changes.

A reference implementation of the Fusion language:
- JSON + pattern-matching functions, one input / one output, `value | function` application.
- Each file is one value, `@refs` for modules/stdlib.

## Running code

```sh
echo '5' | ruby fusion.rb examples/fact.fsn          # => 120
echo '[1,2,3]' | ruby fusion.rb examples/main.fsn    # => [2,4,6]
ruby fusion.rb examples/fact.fsn 5                   # input as an argument
ruby fusion.rb -e '(n => [n,2] | multiply)' 21       # inline program  => 42
```

Input is read from stdin (or the 2nd CLI arg) as JSON, parsed into a Fusion value,
piped through the file's function, and the result is printed as JSON. A final
result of `!` sets exit code 1.

## Running the tests

```bash
ruby test.rb
```

## Documentation

For further documentation, see the `docs/` directory.
