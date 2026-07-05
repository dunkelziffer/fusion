# frozen_string_literal: true

# Fusion — a proof-of-concept interpreter.
#
# This file is the interpreter library; the CLI entrypoint lives in exe/fusion.
#
# A file contains exactly one value. A file is "executable" if that value is a
# function; the runtime computes  STDIN | thatFunction  and prints the result.

require_relative "fusion/version"
require_relative "fusion/lexer"
require_relative "fusion/parser"
require_relative "fusion/interpreter"
require_relative "fusion/cli"

module Fusion
  # This gem's regular error taxonomy.
  # None of these should ever bubble up to the user.
  class FusionError < StandardError; end
  class ParseError < FusionError; end

  # Raise this in "unreachable" code paths, e.g. the "else" branch
  # of a case statement that should be exhaustive.
  class Unreachable < StandardError; end

  # NOTE: There's also ErrorVal, which isn't a Ruby error, but
  # a runtime value representing an error in Fusion.
end
