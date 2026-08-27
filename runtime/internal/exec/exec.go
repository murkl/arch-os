// Package exec is the only place this program starts a process.
//
// Everything the runtime actually does is shell: a stage's script, a variable's
// option list, the preflight check. The runtime feeds them variables and reads
// back an exit code or stdout — it never knows what any of them do.
package exec

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"

	"installer/internal/logging"

	"github.com/charmbracelet/x/ansi"
)

// Scrollback caps the lines a Session keeps in memory. The whole of the output
// is in the log; this is only what a failure report can still reach for.
const Scrollback = 2000

// Env is the variable set handed to every script, as KEY=value entries.
type Env []string

// Runner starts scripts, each wrapped in the same failure-reporting trap.
//
// Lib is shell the tree hands to every script of its own before that script's
// own text — one place for what several of them share. The runtime never reads
// it and has no idea what is in it; it only makes sure everything it starts
// gets the same one.
type Runner struct {
	Lib string
}

// The ERR trap reports on file descriptor 3 — the first entry of cmd.ExtraFiles.
// A dedicated descriptor keeps the report out of the script's own output, so a
// script may print anything at all without being mistaken for a failure report.
//
// The trap is the single detector, and it is deliberate that -e is NOT set.
// Both react to exactly the same failures, but -e would also kill the shell
// when `source` merely *returns* the status of a benign last line — a guard
// like `[ "$X" = true ] && do_it` leaves status 1 when the test is false — and
// a working step would be reported as failed. The trap fires only for a real
// failure, exits with its code, and so stops at the first one.
//
// It reports on the failure's own terms: BASH_SOURCE and LINENO point into the
// script file, BASH_COMMAND is the command that failed. The empty-BASH_SOURCE
// check drops the status a failing `source` propagates back to this wrapper —
// that frame is not where anything went wrong.
const trapped = `set -Eo pipefail
trap 'c=$?; s=${BASH_SOURCE[0]}; [ -n "$s" ] && { printf "%d\t%s\t%d\t%s\n" "$c" "$s" "$LINENO" "$BASH_COMMAND" >&3; exit $c; }' ERR
`

// The two arguments every invocation is given: the script to run, and the
// shared library to put in front of it. Sourcing the library here is what lets
// a script be plain shell with no preamble at all.
const preamble = `[ -n "$2" ] && source "$2"
`

// scriptWrapper sources a task's own file, under the trap.
const scriptWrapper = trapped + preamble + `source "$1"
exit 0`

// snippet runs a short piece of shell the yaml wrote inline — an option list, a
// prefill. No ERR trap: the caller wants the exit code or the output, and a
// non-zero status is an answer rather than a failure.
const snippet = preamble + `eval "$1"`

// handover runs a script that takes the terminal over. No trap and no pipes:
// what it does is a session somebody is sitting in front of, so its output is
// the terminal's and its exit code is the whole of what comes back.
const handover = preamble + `source "$1"`

// Run executes a one-liner and returns its trimmed stdout. Used for the small
// reads: an option list, a suggested value.
func (r Runner) Run(s string, env Env) (string, error) {
	cmd := exec.Command("bash", "-c", snippet, "--", s, r.Lib)
	cmd.Env = env
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(errb.String()); msg != "" {
			return "", fmt.Errorf("%s: %s", err, msg)
		}
		return "", err
	}
	return strings.TrimRight(out.String(), "\n"), nil
}

// Lines runs a command and returns its stdout, one entry per line, with blank
// lines dropped.
//
// Only the end of a line is trimmed. What is in front of the first character is
// the caller's business: a line may begin with a tab that separates a value
// from the text it is chosen by, and an empty value in front of that tab is a
// real answer — "no variant", "the default" — not an empty line.
func (r Runner) Lines(s string, env Env) ([]string, error) {
	out, err := r.Run(s, env)
	if err != nil {
		return nil, err
	}
	var lines []string
	for l := range strings.SplitSeq(out, "\n") {
		l = strings.TrimRight(l, " \t\r")
		if strings.TrimSpace(l) == "" {
			continue
		}
		lines = append(lines, l)
	}
	return lines, nil
}

// Session is a running script. Its combined output is mirrored to the log raw
// and kept, sanitized, for a failure report.
type Session struct {
	mu     sync.Mutex
	lines  []string
	stderr []string
	done   chan struct{}
	err    error
	cmd    *exec.Cmd
	unit   string
}

// Start runs a script in the background. unit names it in any failure.
func (r Runner) Start(unit, path string, env Env) (*Session, error) {
	cmd, report, err := r.command(path, env)
	if err != nil {
		return nil, err
	}
	s := &Session{done: make(chan struct{}), cmd: cmd, unit: unit}

	out := &sessionWriter{sink: s.write}
	errw := &sessionWriter{sink: func(l string) { s.write(l); s.writeErr(l) }}
	// The log gets the raw bytes; the report gets them sanitized (see write).
	cmd.Stdout = io.MultiWriter(logging.External(), out)
	cmd.Stderr = io.MultiWriter(logging.External(), errw)

	if err := cmd.Start(); err != nil {
		drain(cmd, report)
		return nil, err
	}
	go func() {
		raw := drain(cmd, report)
		err := cmd.Wait()
		out.flush()
		errw.flush()
		s.err = s.failure(err, raw)
		close(s.done) // only after every line has been collected
	}()
	return s, nil
}

// command builds the invocation of a script, with the ERR trap's channel
// attached as fd 3. The returned reader yields the trap's report; the caller
// closes the write end right after starting (see drain).
func (r Runner) command(payload string, env Env) (*exec.Cmd, *os.File, error) {
	cmd := exec.Command("bash", "-c", scriptWrapper, "--", payload, r.Lib)
	cmd.Env = env
	// A process group of its own, so that stopping a stage stops everything it
	// started. A stage is one line of shell that runs a package manager that
	// runs a build; killing only the shell would leave all of that writing to
	// the target disk after the program itself is gone.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	rd, w, err := os.Pipe()
	if err != nil {
		return nil, nil, err
	}
	cmd.ExtraFiles = []*os.File{w}
	return cmd, rd, nil
}

// Terminal builds the invocation of a script that is handed the terminal, for
// the caller to run in place of the interface.
//
// It is deliberately not a Session: nothing is captured, nothing is logged, and
// there is no process group to kill — the user is at the keyboard, and what
// they see is what the script prints. All that comes back is the exit code.
func (r Runner) Terminal(path string, env Env) *exec.Cmd {
	cmd := exec.Command("bash", "-c", handover, "--", path, r.Lib)
	cmd.Env = env
	return cmd
}

// drain closes this side of the write end — without it, reading the report
// blocks until the child exits even though the trap already wrote — and returns
// what the trap reported.
func drain(cmd *exec.Cmd, r *os.File) string {
	for _, f := range cmd.ExtraFiles {
		f.Close()
	}
	defer r.Close()
	raw, _ := io.ReadAll(r)
	return string(raw)
}

// failure turns an exit status into the one error shape, filling in whatever
// the trap managed to report.
func (s *Session) failure(err error, report string) error {
	if err == nil {
		return nil
	}
	f := parseReport(report)
	if f == nil {
		f = &Failure{Code: exitCode(err)}
	}
	f.Unit = s.unit
	f.Stderr = s.lastErr()
	return f
}

// Done closes once the script has exited and all its output is collected.
func (s *Session) Done() <-chan struct{} { return s.done }

// Err holds the result, valid once Done is closed.
func (s *Session) Err() error { return s.err }

// Kill stops the script and everything it started, by signalling the whole
// process group rather than the shell alone.
//
// It is the one thing ctrl+c has to do while a stage is running: leaving a
// package transaction writing to a disk that nobody is watching any more is
// worse than an interrupted one.
func (s *Session) Kill() {
	if s.cmd == nil || s.cmd.Process == nil {
		return
	}
	if pgid, err := syscall.Getpgid(s.cmd.Process.Pid); err == nil {
		syscall.Kill(-pgid, syscall.SIGKILL)
		return
	}
	s.cmd.Process.Kill()
}

// Tail copies the last n lines of output.
func (s *Session) Tail(n int) []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if n < 0 || len(s.lines) <= n {
		return append([]string(nil), s.lines...)
	}
	return append([]string(nil), s.lines[len(s.lines)-n:]...)
}

func (s *Session) write(line string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lines = append(s.lines, sanitize(line))
	if len(s.lines) > Scrollback {
		s.lines = s.lines[len(s.lines)-Scrollback:]
	}
}

// writeErr keeps the tail of stderr, which is where a failing tool says why.
func (s *Session) writeErr(line string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if line = strings.TrimSpace(sanitize(line)); line == "" {
		return
	}
	s.stderr = append(s.stderr, line)
	if len(s.stderr) > stderrKeep {
		s.stderr = s.stderr[len(s.stderr)-stderrKeep:]
	}
}

func (s *Session) lastErr() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return strings.Join(s.stderr, "\n")
}

// sanitize strips what a script's output must not carry into the frame it is
// rendered in: raw colour and cursor sequences would corrupt the TUI.
func sanitize(line string) string {
	line = ansi.Strip(line)
	return strings.Map(func(r rune) rune {
		if r == '\t' {
			return r
		}
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, line)
}

type sessionWriter struct {
	sink func(string)
	buf  []byte
}

func (w *sessionWriter) Write(p []byte) (int, error) {
	w.buf = append(w.buf, p...)
	for {
		i := bytes.IndexByte(w.buf, '\n')
		if i < 0 {
			break
		}
		w.sink(string(bytes.TrimRight(w.buf[:i], "\r")))
		w.buf = w.buf[i+1:]
	}
	return len(p), nil
}

// flush emits a trailing line that never got its newline.
func (w *sessionWriter) flush() {
	if len(w.buf) > 0 {
		w.sink(string(w.buf))
		w.buf = nil
	}
}
