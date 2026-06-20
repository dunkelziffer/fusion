# frozen_string_literal: true

# === CLI internals ===

require_relative "serializer"
require_relative "encoder"
require_relative "../interpreter/env"

module Fusion
  module CLI
    class Repl
      RESET      = "\e[0m"
      LIGHT_BLUE = "\e[94m"
      GREEN      = "\e[32m"
      RED        = "\e[31m"

      PROMPT              = "#{LIGHT_BLUE}fsn> #{RESET}"
      CONTINUATION_PROMPT = "#{LIGHT_BLUE}...> #{RESET}"
      VALUE_MARKER        = "#{GREEN}✔ #{RESET}"
      ERROR_MARKER        = "#{RED}✗ #{RESET}"

      # REPL entries report errors with the same location as inline (`-e`) code.
      LOCATION = "code <inline>"

      # `jail_root` confines @-resolution for every entry (defaults to cwd; see
      # CLI#jail_root). `@dir`-relative refs resolve against cwd too.
      def initialize(jail_root:)
        @jail_root = jail_root
      end

      def run
        CLI.prepare!

        require "reline"
        Reline.output = $stderr
        Reline.prompt_proc = proc do |lines|
          lines.each_index.map { |i| i.zero? ? PROMPT : CONTINUATION_PROMPT }
        end

        environment = Interpreter::Env.new.set_context(:dir, Dir.pwd)

        loop do
          buffer = begin
            Reline.readmultiline(PROMPT, true) { complete?(_1) }
          rescue Interrupt
            $stderr.puts("^C") # discard the half-typed entry and re-prompt
            next
          end

          break if buffer.nil? # Ctrl-D on an empty line ends the session
          next if buffer.strip.empty?

          output = handle(buffer, environment)

          marker = output.start_with?("!") ? ERROR_MARKER : VALUE_MARKER
          $stderr.print(marker) # decoration on stderr
          $stdout.puts(output)  # the clean value on stdout
        end
      end

      # String -> yes/no
      def complete?(buffer)
        return true if buffer.strip.empty?

        ast = Fusion::Parser.parse_repl(buffer, location: LOCATION)
        ast.is_a?(AST::Expression) || ast.is_a?(AST::Statement::Assignment)
      end

      # String (+ Env) -> String
      def handle(buffer, environment)
        ast = Fusion::Parser.parse_repl(buffer, location: LOCATION)
        runtime_value = CLI.evaluate(ast, environment, jail_root: @jail_root)
        wire_pair = Serializer.serialize(runtime_value, lenient: true)
        Encoder.encode(wire_pair, mode: :bang)
      end
    end
  end
end
