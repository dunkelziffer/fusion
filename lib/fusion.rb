#!/usr/bin/env ruby
# frozen_string_literal: true

# Fusion — a proof-of-concept interpreter (rev 4 of the spec).
#
# A file contains exactly one value. A file is "executable" if that value is a
# function; the runtime computes  STDIN | thatFunction  and prints the result.
#
# Usage:
#   echo '[1,2,3]' | ruby fusion.rb path/to/main.fsn
#   ruby fusion.rb path/to/main.fsn '<json-input>'      # input as an argument
#   ruby fusion.rb -e '(n => [n,2] | multiply)' '21'      # inline program
#
# Values are represented in Ruby as:
#   null   -> :null            (we avoid Ruby nil so "absent" is explicit)
#   !      -> ERROR (a unique singleton)
#   bool   -> true / false
#   int    -> Integer
#   float  -> Float
#   string -> String
#   array  -> Array
#   object -> Hash (String keys, insertion-ordered as Ruby preserves)
#   func   -> Func (closure over an Env)

module Fusion
  # ---- Special singletons -------------------------------------------------
  NULL  = :null
  ERROR = Object.new
  def ERROR.inspect = "!"
  def ERROR.to_s = "!"
  ERROR.freeze

  class FusionError < StandardError; end
  class ParseError < FusionError; end
end

require_relative "fusion/expression"
require_relative "fusion/pattern"
require_relative "fusion/env"
require_relative "fusion/func"
require_relative "fusion/native_func"
require_relative "fusion/file_thunk"
require_relative "fusion/lexer"
require_relative "fusion/serializer"
require_relative "fusion/json_input"
require_relative "fusion/parser"
require_relative "fusion/builtins"
require_relative "fusion/interpreter"


# =========================================================================
# CLI
# =========================================================================
if $PROGRAM_NAME == __FILE__
  args = ARGV.dup
  inline = nil
  if args[0] == "-e"
    inline = args[1]
    program_path = nil
    explicit_input = args[2]
  else
    program_path = args[0]
    explicit_input = args[1]
  end

  stdlib = File.join(__dir__, "../stdlib")
  interp = Fusion::Interpreter.new(stdlib_dir: (Dir.exist?(stdlib) ? stdlib : nil))

  # Determine the program function value.
  program_value =
    if inline
      ast = Fusion::Parser.parse_file(inline)
      env = interp.root_env.child
      env.define("__dir__", Dir.pwd)
      interp.eval_expr(ast, env)
    else
      abort("usage: fusion.rb <file.fsn> [json-input]   or   fusion.rb -e '<src>' [json-input]") unless program_path
      interp.load_file(File.expand_path(program_path)).force
    end

  # Read input: explicit arg wins, else stdin.
  input_text = explicit_input || ($stdin.tty? ? "" : $stdin.read)
  input_text = "null" if input_text.nil? || input_text.strip.empty?
  input_value = Fusion::JsonInput.parse(input_text)

  result = interp.apply(program_value, input_value)

  puts Fusion::Serializer.to_json(result)
  exit(result.equal?(Fusion::ERROR) ? 1 : 0)
end
