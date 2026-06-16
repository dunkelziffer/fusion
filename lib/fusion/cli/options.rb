# frozen_string_literal: true

# === CLI internals ===
#
# Input: ARGV
# Output: Options (use case, input/output modes, program, input)
#
# A misuse of the command line is a UsageError, reported as plain text on
# stderr by exe/fusion, never a payloaded Fusion error. Most surface here while
# parsing options; `-!` with empty stdin is the one caught later, while reading
# input.

require "optparse"

module Fusion
  module CLI
    class Options
      class UsageError < StandardError; end

      USAGE = <<~TEXT
        usage: fusion [options] <file.fsn>
               fusion [options] -e '<source>'
               fusion --repl

        use cases (default: --repl with no arguments, otherwise --pipe):
          -p, --pipe      apply the program to stdin; with no input, the
                          program's own value is the result
          -s, --stream    apply the program to each line of an NDJSON stream
          -r, --repl      interactive expressions and `identifier = expression`

        options:
          -e, --execute '<source>'
                          inline program instead of a file
          -i, --input MODE
                          how the input marks an error value
          -o, --output MODE
                          how the output marks an error value
          -j, --jail DIR  confine @-references to DIR and its subtree
                          (default: the program's directory; the stdlib is
                          always reachable, stdin is never affected)
          -!              treat the input as an error value (unix input mode only)
          -b, --skip-blank-lines
                          drop blank input lines instead of echoing them (--stream only)

        modes: unix, bang, array, object
          unix    pipe only (default there): plain JSON; output: stdout/exit 0
                  for values, stderr/exit 1 for error payloads
          bang    a leading "!" marks an error value; cheapest encoding, but not
                  valid JSON — prefer it only between Fusion programs
          array   [0, value] marks a value, [1, payload] an error (default for --stream)
          object  {"value": _} marks a value, {"error": _} an error
      TEXT

      MODES = %w[unix bang array object].freeze

      attr_reader :use_case, :input_mode, :output_mode, :inline_source, :program_path, :jail

      def initialize(use_case:, input_mode:, output_mode:, inline_source:, program_path:, error_input:, skip_blank_lines:, jail:)
        @use_case = use_case
        @input_mode = input_mode
        @output_mode = output_mode
        @inline_source = inline_source
        @program_path = program_path
        @error_input = error_input
        @skip_blank_lines = skip_blank_lines
        @jail = jail
      end

      def error_input?
        @error_input
      end

      def skip_blank_lines?
        @skip_blank_lines
      end

      def self.parse(argv)
        pipe = false
        stream = false
        repl = false
        input_modes = []
        output_modes = []
        error_input = false
        skip_blank_lines = false
        inline_source = nil
        jail = nil

        parser = OptionParser.new do |option|
          option.on("-p", "--pipe") { pipe = true }
          option.on("-s", "--stream") { stream = true }
          option.on("-r", "--repl") { repl = true }
          option.on("-i", "--input MODE") { |mode| input_modes << check_mode!(mode, "--input") }
          option.on("-o", "--output MODE") { |mode| output_modes << check_mode!(mode, "--output") }
          option.on("-e", "--execute SOURCE") { |source| inline_source = source }
          option.on("-j", "--jail DIR") { |dir| jail = dir }
          option.on("-!") { error_input = true }
          option.on("-b", "--skip-blank-lines") { skip_blank_lines = true }
        end
        parser.require_exact = true # no abbreviations: "--s" is not a stand-in for "--stream"

        # Whatever survives option parsing is positional: the program path.
        positional = run_parser(parser, argv)

        use_case = resolve_use_case(pipe: pipe, stream: stream, repl: repl, no_arguments: argv.empty?)
        input_mode = resolve_mode(input_modes, "--input")
        output_mode = resolve_mode(output_modes, "--output")

        validate(use_case, input_mode, output_mode, error_input, skip_blank_lines, inline_source, jail, positional)
      end

      # Collapse the use-case flags into one use case; more than one is a misuse.
      # With none: a bare `fusion` (no arguments) starts the REPL, while any other
      # invocation is a pipe run.
      def self.resolve_use_case(pipe:, stream:, repl:, no_arguments:)
        selected = [(:pipe if pipe), (:stream if stream), (:repl if repl)].compact

        case selected.length
        when 0 then no_arguments ? :repl : :pipe
        when 1 then selected.first
        else raise UsageError, "choose one use case: --pipe, --stream, or --repl"
        end
      end

      # The single mode for one direction, or nil if unset. Repeats of the same
      # mode are fine; two different modes for the same flag are a misuse.
      def self.resolve_mode(modes, flag)
        distinct = modes.uniq

        case distinct.length
        when 0 then nil
        when 1 then distinct.first
        else raise UsageError, "conflicting #{flag} modes: #{distinct.join(', ')}"
        end
      end

      # Run OptionParser, translating its parse errors into our UsageError so
      # exe/fusion reports them as plain usage text (never a payloaded error).
      def self.run_parser(parser, argv)
        parser.parse(argv)
      rescue OptionParser::InvalidOption => error
        raise UsageError, "unknown option #{error.args.join(' ')}"
      rescue OptionParser::MissingArgument => error
        raise UsageError, missing_argument_message(error.args.first)
      rescue OptionParser::ParseError => error
        raise UsageError, error.message
      end

      # A MODE value -> its symbol, or a UsageError naming the valid modes.
      def self.check_mode!(value, flag)
        return value.to_sym if MODES.include?(value)

        raise UsageError, "#{flag} expects one of: #{MODES.join(', ')} (got #{value})"
      end

      # Mirror the old per-flag wording when a value-taking option has no value.
      # OptionParser reports whichever alias the user typed, so match both.
      def self.missing_argument_message(flag)
        case flag
        when "-e", "--execute" then "-e/--execute requires a source argument"
        when "-i", "--input" then "--input expects one of: #{MODES.join(', ')} (got nothing)"
        when "-o", "--output" then "--output expects one of: #{MODES.join(', ')} (got nothing)"
        when "-j", "--jail" then "-j/--jail requires a directory argument"
        else "#{flag} requires an argument"
        end
      end

      # Check the flag combination against the use case and fill in defaults.
      def self.validate(use_case, input_mode, output_mode, error_input, skip_blank_lines, inline_source, jail, positional)
        raise UsageError, "--skip-blank-lines is only for --stream" if skip_blank_lines && use_case != :stream

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
          raise UsageError, "too many positional arguments" unless positional.empty?
        when :pipe
          input_mode ||= :unix
          output_mode ||= :unix
          raise UsageError, "-! requires the unix input mode" if error_input && input_mode != :unix
          program_path = inline_source ? nil : positional.shift
          raise UsageError, "missing program (a .fsn file or -e)" unless inline_source || program_path
          raise UsageError, "too many positional arguments" unless positional.empty?
        else
          raise Unreachable, "Unknown use case #{use_case}"
        end

        new(
          use_case: use_case,
          input_mode: input_mode,
          output_mode: output_mode,
          inline_source: inline_source,
          program_path: program_path,
          error_input: error_input,
          skip_blank_lines: skip_blank_lines,
          jail: jail
        )
      end

      private_class_method :validate, :resolve_use_case, :resolve_mode, :run_parser, :check_mode!, :missing_argument_message
    end
  end
end
