#!/usr/bin/env ruby
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
  class FusionError < StandardError; end
  class ParseError < FusionError; end
end
