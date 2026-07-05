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

      PROMPT              = "#{LIGHT_BLUE}fsn> #{RESET}".freeze
      CONTINUATION_PROMPT = "#{LIGHT_BLUE}...> #{RESET}".freeze
      VALUE_MARKER        = "#{GREEN}✔ #{RESET}".freeze
      ERROR_MARKER        = "#{RED}✗ #{RESET}".freeze

      # REPL entries report errors with the same site as inline (`-e`) code.
      SITE = { origin: "code", file: "<inline>" }.freeze

      def initialize(root_env:)
        @root_env = root_env
      end

      def run
        CLI.prepare!

        require "reline"
        Reline.output = $stderr
        Reline.prompt_proc = proc do |lines|
          lines.each_index.map { |i| i == 0 ? PROMPT : CONTINUATION_PROMPT }
        end

        # The session env is a child of the run's root, so it carries the jail;
        # bindings accumulate here while loaded files stay isolated at the root.
        environment = @root_env.child.set_context(:dir, Dir.pwd)

        loop do
          buffer = begin
            Reline.readmultiline(PROMPT, true) { complete?(_1) }
          rescue Interrupt
            warn("^C") # discard the half-typed entry and re-prompt
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

        ast = Fusion::Parser.parse_repl(buffer, site: SITE)
        ast.is_a?(AST::Expression) || ast.is_a?(AST::Statement::Assignment)
      end

      # String (+ Env) -> String
      def handle(buffer, environment)
        ast = Fusion::Parser.parse_repl(buffer, site: SITE)
        runtime_value = CLI.evaluate(ast, environment)
        wire_pair = Serializer.serialize(runtime_value, lenient: true)
        Encoder.encode(wire_pair, mode: :bang)
      end
    end
  end
end
