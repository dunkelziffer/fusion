# frozen_string_literal: true

require "open3"
require "rbconfig"

# Integration tests that drive the real `exe/fusion` binary as a subprocess.
#
# Most behavior is specced in-process via the FusionHelpers harness, but the
# CLI's outermost contract — the top-level `rescue Exception` net, the
# stdout/stderr split, and the exit code — can only be observed by running the
# actual executable. In particular, a stack overflow raises Ruby's
# SystemStackError (not a StandardError), which is converted to a payload only by
# that net; the in-process harness cannot model it (see error_kinds_spec.rb).
RSpec.describe "CLI (exe/fusion)" do
  ROOT = File.expand_path("..", __dir__)
  EXE  = File.join(ROOT, "exe", "fusion")
  FIX  = File.expand_path("fixtures", __dir__)

  # Run the binary with the given args and stdin; returns [stdout, stderr, status].
  def run_cli(*args, stdin: "")
    Open3.capture3(RbConfig.ruby, EXE, *args, stdin_data: stdin)
  end

  describe "the result/error channel split" do
    it "prints the result to stdout and exits 0 on success" do
      out, err, status = run_cli(File.join(FIX, "fact.fsn"), stdin: "5")
      expect(out).to eq("120\n")
      expect(err).to eq("")
      expect(status.exitstatus).to eq(0)
    end

    it "prints only the payload to stderr (stdout empty) and exits 1 on error" do
      out, err, status = run_cli("-e", "(p => p | @divide)", stdin: "[1,0]")
      expect(out).to eq("")
      expect(err).to include('"kind":"math_error"', '"message":"division by zero"')
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "the top-level Ruby-error net" do
    it "converts a stack overflow (SystemStackError) into a stack_error payload" do
      out, err, status = run_cli(File.join(FIX, "loop.fsn"), stdin: "0")
      expect(out).to eq("")
      expect(err).to include(
        '"kind":"stack_error"', '"location":"interpreter"', '"message":"recursion too deep"'
      )
      expect(status.exitstatus).to eq(1)
    end
  end

  describe "boundary conversions also reachable in-process" do
    it "converts an inline parse error" do
      _out, err, status = run_cli("-e", "(_ => @", stdin: "null")
      expect(err).to include('"kind":"parse_error"', '"location":"code <inline>"')
      expect(status.exitstatus).to eq(1)
    end

    it "reports a function result as a serialization_error" do
      _out, err, status = run_cli("-e", "(n => (m => m))", stdin: "null")
      expect(err).to include('"kind":"serialization_error"', '"location":"output"')
      expect(status.exitstatus).to eq(1)
    end
  end
end
