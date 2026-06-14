# frozen_string_literal: true

# === CLI internals ===
#
# Input: ARGV
# Output: Options (use case, input/output modes, program, input)
#
# A misuse of the command line is a UsageError, reported as plain text on
# stderr by exe/fusion — it happens before the input/output contract begins,
# so it is not a payloaded Fusion error.

module Fusion
  module CLI
    class Options
      class UsageError < StandardError; end

      USAGE = <<~TEXT
        usage: fusion [options] <file.fsn>
               fusion [options] -e '<source>'
               fusion --repl

        use cases:
          (default)       pipe: apply the program to stdin; with no input, the
                          program's own value is the result
          --stream        apply the program to each line of an NDJSON stream
          --repl          interactive expressions and `identifier = expression`

        options:
          -e '<source>'   inline program instead of a file
          --input MODE    how the input marks an error value
          --output MODE   how the output marks an error value
          -!              treat the input as an error value (unix input mode only)

        modes: unix, bang, array, object
          unix    pipe only (default there): plain JSON; output: stdout/exit 0
                  for values, stderr/exit 1 for error payloads
          bang    a leading "!" marks an error value; cheapest encoding, but not
                  valid JSON — prefer it only between Fusion programs
          array   [0, value] marks a value, [1, payload] an error (default for --stream)
          object  {"value": _} marks a value, {"error": _} an error
      TEXT

      MODES = %w[unix bang array object].freeze

      attr_reader :use_case, :input_mode, :output_mode, :inline_source, :program_path

      def initialize(use_case:, input_mode:, output_mode:, inline_source:, program_path:, error_input:)
        @use_case = use_case
        @input_mode = input_mode
        @output_mode = output_mode
        @inline_source = inline_source
        @program_path = program_path
        @error_input = error_input
      end

      def error_input?
        @error_input
      end

      def self.parse(argv)
        arguments = argv.dup
        use_case = :pipe
        input_mode = nil
        output_mode = nil
        error_input = false
        inline_source = nil
        positional = []

        until arguments.empty?
          argument = arguments.shift
          case argument
          when "--stream" then use_case = :stream
          when "--repl" then use_case = :repl
          when "--input" then input_mode = shift_mode(arguments, "--input")
          when "--output" then output_mode = shift_mode(arguments, "--output")
          when "-!" then error_input = true
          when "-e"
            inline_source = arguments.shift
            raise UsageError, "-e requires a source argument" if inline_source.nil?
          when /\A--/
            raise UsageError, "unknown option #{argument}"
          else
            # Anything else is positional: the program path (for the non -e form).
            positional << argument
          end
        end

        validate(use_case, input_mode, output_mode, error_input, inline_source, positional)
      end

      # Check the flag combination against the use case and fill in defaults.
      def self.validate(use_case, input_mode, output_mode, error_input, inline_source, positional)
        case use_case
        when :repl
          unless input_mode.nil? && output_mode.nil? && !error_input && inline_source.nil? && positional.empty?
            raise UsageError, "--repl takes no program, no input, and no modes"
          end
          program_path = nil
        when :stream
          input_mode ||= :array
          output_mode ||= :array
          raise UsageError, "--stream does not support the unix mode" if input_mode == :unix || output_mode == :unix
          raise UsageError, "-! requires the unix input mode" if error_input
          program_path = inline_source ? nil : positional.shift
          raise UsageError, "missing program (a .fsn file or -e)" unless inline_source || program_path
          raise UsageError, "--stream reads its input from stdin, not an argument" unless positional.empty?
        when :pipe
          input_mode ||= :unix
          output_mode ||= :unix
          raise UsageError, "-! requires the unix input mode" if error_input && input_mode != :unix
          program_path = inline_source ? nil : positional.shift
          raise UsageError, "missing program (a .fsn file or -e)" unless inline_source || program_path
          raise UsageError, "input arrives on stdin, not an argument: #{positional.join(' ')}" unless positional.empty?
        else
          raise Unreachable, "Unknown use case #{use_case}"
        end

        new(
          use_case: use_case,
          input_mode: input_mode,
          output_mode: output_mode,
          inline_source: inline_source,
          program_path: program_path,
          error_input: error_input
        )
      end

      def self.shift_mode(arguments, flag)
        mode = arguments.shift
        unless MODES.include?(mode)
          raise UsageError, "#{flag} expects one of: #{MODES.join(', ')} (got #{mode.nil? ? 'nothing' : mode})"
        end
        mode.to_sym
      end

      private_class_method :validate, :shift_mode
    end
  end
end
