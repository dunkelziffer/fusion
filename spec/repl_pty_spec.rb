# frozen_string_literal: true

require "rbconfig"
require "timeout"

# Pseudo-terminal tests: drive the real `exe/fusion --repl` in an actual tty, the
# way a human does. The pipe-driven tests in cli_spec.rb cannot exercise Reline's
# raw-mode line editing (multi-line entries, continuation prompts) — only a pty
# can. The pty merges the child's stdout and stderr, exactly as a terminal does,
# so the transcript interleaves the prompts (on stderr) with the results (stdout).
#
# Input is fed one line at a time, each write waiting for that line's echo before
# the next. That keeps the writes from coalescing — Reline treats a bulk write as
# a paste and would swallow the terminating Ctrl-D — and paces the test by actual
# consumption rather than by sleeping.
begin
  require "pty"
  PTY_AVAILABLE = true
rescue LoadError
  PTY_AVAILABLE = false
end

RSpec.describe "REPL in a pseudo-terminal (exe/fusion --repl)", if: PTY_AVAILABLE do
  let(:exe) { File.expand_path("../exe/fusion", __dir__) }

  # Drives one REPL session in a pty. Closes the pty and reaps the child no
  # matter what, so a failed example never leaks a process (leaked sessions
  # exhaust the pty pool and take down later ones).
  def repl_session
    reader, writer, pid = PTY.spawn(RbConfig.ruby, exe, "--repl")
    terminal = Terminal.new(reader, writer)
    # A whole session is sub-second; the outer cap only guards against a wedged
    # child so a single example can never hang the suite.
    Timeout.timeout(30) do
      yield terminal
      terminal.finish
    end
    terminal.transcript
  ensure
    # Close the master (the child reading the slave then gets EOF), then make
    # sure it is dead before reaping, so the reap can never block on a live child.
    [writer, reader].each { |io| io.close rescue nil }
    if pid
      Process.kill("KILL", pid) rescue nil
      Process.wait(pid) rescue nil
    end
  end

  # A thin expect-style driver over the pty master.
  class Terminal
    TIMEOUT = 10

    def initialize(reader, writer)
      @reader = reader
      @writer = writer
      @raw = +""
      @scan = 0
    end

    # Type a line, then block until its echo returns (proof Reline consumed it,
    # so the next write cannot coalesce with it into a "paste").
    def type_line(text)
      @writer.write(text + "\n")
      expect(text)
    end

    # Block until `needle` appears in the transcript past everything already
    # matched. Used both to sync on a line's echo and to assert a result printed.
    # Advancing the scan cursor keeps matches ordered and tolerant of the same
    # text recurring in the redrawn prompt.
    def expect(needle)
      deadline = Time.now + TIMEOUT
      loop do
        if (index = transcript.index(needle, @scan))
          @scan = index + needle.length
          return
        end
        raise "timed out waiting for #{needle.inspect}; transcript so far:\n#{transcript}" if @eof || Time.now > deadline

        pump
      end
    end

    # End the session. Everything asserted has already been read, so just signal
    # Ctrl-D; the ensure in repl_session kills and reaps the child.
    def finish
      @writer.write("\x04")
    end

    # The captured output with terminal control codes (and bare CRs) stripped, so
    # it reads as plain text: the prompt, the echoed input, and the results.
    def transcript = @raw.gsub(/\e\[[\d;?]*[ -\/]*[@-~]/, "").delete("\r")

    private

    def pump
      @raw << @reader.read_nonblock(4096)
    rescue IO::WaitReadable
      @reader.wait_readable(0.1)
    rescue Errno::EIO, EOFError
      @eof = true # the child closed the pty
    end
  end

  it "runs an interactive session: binds, reads bindings, renders, reports errors" do
    transcript = repl_session do |terminal|
      terminal.type_line("seed = 20")                          # a statement: binds `seed`
      terminal.type_line("[seed, 22] | @OP.sum")               # reads the binding ...
      terminal.expect("42")                                    #   ... -> 42
      terminal.type_line("double = (n => [n, 2] | @OP.product)") # a function value ...
      terminal.expect('"<function>"')                          #   ... rendered leniently
      terminal.type_line("missing")                            # an unbound identifier ...
      terminal.expect("unbound identifier")                    #   ... prints, session survives
    end

    expect(transcript).to include("42", '"<function>"', "unbound identifier")
  end

  it "completes a multi-line entry across continuation prompts" do
    transcript = repl_session do |terminal|
      terminal.type_line("[")        # incomplete: Reline opens a continuation line
      terminal.type_line("  100,")
      terminal.type_line("  200")
      terminal.type_line("]")        # now it parses and evaluates ...
      terminal.expect("[100,200]")   #   ... to the joined array
    end

    expect(transcript).to include("...> ", "[100,200]") # continuation prompt shown, entry evaluated
  end
end
