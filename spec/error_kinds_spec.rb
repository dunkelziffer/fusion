# frozen_string_literal: true

# Systematic coverage of every error `kind` in the standardized catalog
# (docs/lang/design.md §2.9). Builtin-specific type/argument/math/conversion
# payloads live in builtins_spec.rb; this file covers the interpreter- and
# runtime-level errors and confirms each kind is reachable (or documents why a
# given source cannot be triggered from Fusion code).
RSpec.describe "error kinds" do
  describe "syntax_error" do
    it "from inline source (location: code <inline>)" do
      expect_pipe
        .code("(_ => @")
        .out("❌", a_string_including('"kind":"syntax_error"', '"location":"code <inline>"'))
    end

    it "from a file (location: code <file>)" do
      expect_pipe
        .file_path("badsyntax.fsn")
        .out("❌", a_string_including('"kind":"syntax_error"', '"location":"code badsyntax.fsn"'))
    end

    it "from non-JSON input (location: input)" do
      expect_pipe
        .in("✅", "not json")
        .code("(x => x)")
        .out("❌", '{"kind":"syntax_error","location":"input","operation":"parsing input as JSON","input":"not json","message":"input is not valid JSON"}')
    end
  end

  describe "reference_error" do
    it "unresolved @name" do
      expect_pipe
        .code("(_ => @no_such_module)")
        .out("❌", '{"kind":"reference_error","location":"code <inline>","operation":"resolving @no_such_module","input":"no_such_module","message":"unresolved reference"}')
    end

    it "non-productive data cycle" do
      expect_pipe
        .file_path("cyclicA.fsn")
        .out("❌", a_string_including('"kind":"reference_error"', '"message":"non-productive data cycle"', "cyclicA.fsn"))
    end

    it "missing file via @../ path" do
      expect_pipe
        .code("(_ => @../nonexistent)")
        .out("❌", a_string_including('"kind":"reference_error"', '"operation":"reading file"', '"message":"file not found"'))
    end

    it "missing file via @load" do
      expect_pipe
        .code('(_ => "nope.fsn" | @load)')
        .out("❌", '{"kind":"reference_error","location":"builtin load","operation":"@load","input":"nope.fsn","message":"file not found"}')
    end

    it "a file-system access failure (reading a directory)" do
      # @load of a directory hits Errno::EISDIR, rescued into reference_error.
      expect_pipe
        .code('(_ => "ref" | @load)')
        .out("❌", a_string_including('"kind":"reference_error"', '"operation":"reading file"', "directory"))
    end
  end

  describe "binding_error" do
    it "reading an unbound identifier" do
      expect_pipe
        .code("(_ => x)")
        .out("❌", '{"kind":"binding_error","location":"code <inline>","operation":"reading identifier x","input":"x","message":"unbound identifier"}')
    end

    it "a duplicate binder in a clause" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("([a, a] => a)")
        .out("❌", a_string_including('"kind":"binding_error"', '"message":"identifier already bound"'))
    end
  end

  describe "access_error (only missing key / index out of range)" do
    it "missing member key" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code("(o => o.b)")
        .out("❌", '{"kind":"access_error","location":"code <inline>","operation":".b","input":[{"a":1},"b"],"message":"missing key"}')
    end

    it "missing index key on an object" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code('(o => o["b"])')
        .out("❌", '{"kind":"access_error","location":"code <inline>","operation":"[\"b\"]","input":[{"a":1},"b"],"message":"missing key"}')
    end

    it "array index out of range" do
      expect_pipe
        .in("✅", "[10,20]")
        .code("(a => a[5])")
        .out("❌", '{"kind":"access_error","location":"code <inline>","operation":"[5]","input":[[10,20],5],"message":"index out of range"}')
    end
  end

  describe "type_error (interpreter-level)" do
    it "array spread of a non-array" do
      expect_pipe
        .code("(_ => [...5])")
        .out("❌", '{"kind":"type_error","location":"code <inline>","operation":"[...] array spread","input":5,"message":"expected an array"}')
    end

    it "object spread of a non-object" do
      expect_pipe
        .code("(_ => {...5})")
        .out("❌", '{"kind":"type_error","location":"code <inline>","operation":"{...} object spread","input":5,"message":"expected an object"}')
    end

    it "member access on a non-object" do
      expect_pipe
        .in("✅", "5")
        .code("(n => n.foo)")
        .out("❌", '{"kind":"type_error","location":"code <inline>","operation":".foo","input":[5,"foo"],"message":"expected an object"}')
    end

    it "indexing with a wrong-typed key" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(a => a["x"])')
        .out("❌", '{"kind":"type_error","location":"code <inline>","operation":"[index]","input":[[1,2],"x"],"message":"bad index type"}')
    end

    it "applying a non-function" do
      expect_pipe
        .in("✅", "5")
        .code("(n => n | 42)")
        .out("❌", '{"kind":"type_error","location":"code <inline>","operation":"|","input":[5,42],"message":"applied a non-function"}')
    end
  end

  describe "argument_error" do
    it "a builtin given the wrong number of arguments (not a pair)" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(p => p | @add)")
        .out("❌", a_string_including('"kind":"argument_error"', '"message":"expected [_, _]"'))
    end
  end

  describe "math_error" do
    it "division by zero" do
      expect_pipe
        .in("✅", "[1,0]")
        .code("(p => p | @divide)")
        .out("❌", a_string_including('"kind":"math_error"', '"message":"division by zero"'))
    end
  end

  describe "conversion_error" do
    it "stringifying a value with no string form" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(v => v | @toString)")
        .out("❌", a_string_including('"kind":"conversion_error"', '"message":"cannot stringify this value type"'))
    end
  end

  describe "serialization_error" do
    it "a bare function result" do
      expect_pipe
        .code("(n => (m => m))")
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":"<function>","message":"cannot serialize a function"}')
    end

    it "a function nested in a result value" do
      expect_pipe
        .code("(_ => [(x => x)])")
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":["<function>"],"message":"cannot serialize a function"}')
    end

    it "a non-finite number result (overflow to Infinity has no JSON form)" do
      expect_pipe
        .code("(_ => [1e308, 10] | @multiply)")
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":"<Infinity>","message":"cannot serialize a non-finite number"}')
    end

    it "a -Infinity result" do
      expect_pipe
        .code("(_ => [1e400, -1] | @multiply)")
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":"<-Infinity>","message":"cannot serialize a non-finite number"}')
    end

    it "a NaN result (Infinity - Infinity)" do
      expect_pipe
        .code("(_ => [1e400, 1e400] | @subtract)")
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":"<NaN>","message":"cannot serialize a non-finite number"}')
    end

    # A user error (`!expr`) is serialized strictly, just like a plain result: a
    # payload with no JSON form is itself a serialization_error.
    it "a user error whose payload is a function" do
      expect_pipe
        .code("(_ => !(y => y))")
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":"!\"<function>\"","message":"cannot serialize a function"}')
    end

    it "a user error whose payload is a non-finite number" do
      expect_pipe
        .code("(_ => !1e400)")
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":"!\"<Infinity>\"","message":"cannot serialize a non-finite number"}')
    end

    # A structured payload is rendered as JSON after the `!`, so an unserializable
    # value nested inside it shows up as a placeholder in valid JSON (not Ruby
    # inspect syntax).
    it "a user error whose payload is an object containing a function" do
      expect_pipe
        .code('(_ => !{"a": (y => y)})')
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":"!{\"a\":\"<function>\"}","message":"cannot serialize a function"}')
    end

    it "a user error whose payload is an array containing a non-finite number" do
      expect_pipe
        .code("(_ => ![1e400])")
        .out("❌", '{"kind":"serialization_error","location":"output","operation":"serializing result","input":"![\"<Infinity>\"]","message":"cannot serialize a non-finite number"}')
    end
  end

  # An interpreter-produced error is serialized leniently: a value with no JSON
  # form sitting in its `input` (often the very value that caused the failure) is
  # rendered best-effort rather than masking the error behind a serialization_error.
  describe "internal errors render their input leniently" do
    it "renders a function in input as \"<function>\"" do
      expect_pipe
        .code("(_ => (y => y) | @floor)")
        .out("❌", '{"kind":"type_error","location":"builtin floor","operation":"floor","input":"<function>","message":"expected a number"}')
    end

    it "renders a function nested in input as \"<function>\"" do
      expect_pipe
        .code("(_ => [(y => y), 1] | @add)")
        .out("❌", '{"kind":"type_error","location":"builtin add","operation":"add","input":["<function>",1],"message":"expected numbers"}')
    end

    it "renders a non-finite number in input as \"<Infinity>\"" do
      expect_pipe
        .code("(_ => 1e400 | @floor)")
        .out("❌", '{"kind":"math_error","location":"builtin floor","operation":"floor","input":"<Infinity>","message":"not a finite number"}')
    end
  end

  # NOTE: observable only at the CLI boundary, tested in cli_spec.rb
  describe "stack_error"

  # The interpreter keeps two internal-invariant guards that raise a Ruby
  # Fusion::Unreachable instead of producing a payload (design §2.9, the one deliberate
  # exception to "no raw Ruby errors"). They are NOT reachable from Fusion source
  # — the parser only ever emits the known Expression::*/Pattern::* classes, so
  # the `else raise` branches fire only on an interpreter bug (a malformed AST
  # built in Ruby). We prove the guards exist by feeding a bogus node directly.
  describe "internal invariant guards (not reachable from source)" do
    let(:interp) { Fusion::Interpreter.new }

    it "eval_expr raises on an unknown expression node" do
      expect { interp.eval_expr(Object.new, interp.root_env) }
        .to raise_error(Fusion::Unreachable, /Unknown AST node/)
    end

    it "match raises on an unknown pattern node" do
      expect { interp.match(Object.new, 1, interp.root_env) }
        .to raise_error(Fusion::Unreachable, /Unknown pattern/)
    end
  end
end
