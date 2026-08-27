package exec

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"installer/internal/i18n"
)

// stderrKeep is how many of the last stderr lines a Failure carries. The real
// message is usually the last thing a tool says before it gives up; more than
// that turns an error into a log dump.
const stderrKeep = 8

// Failure is what a script reports back when it dies, in one shape for every
// script there is or will be: the runtime never knows what a script does, so it
// asks bash where it broke rather than guessing from the output.
type Failure struct {
	Unit    string // the step's name, filled in by the caller
	Script  string // the file the ERR trap fired in
	Line    int
	Code    int
	Command string // the command that failed
	Stderr  string
}

// Fields renders the failure as label/value pairs, so the frame can lay them
// out as a table rather than parse a sentence back apart. The labels are
// translated here because this is the one place that knows what each value is.
func (f *Failure) Fields() [][2]string {
	var out [][2]string
	add := func(label, value string) {
		if value != "" {
			out = append(out, [2]string{label, value})
		}
	}
	if f.Script != "" {
		add(i18n.T("Script"), fmt.Sprintf("%s:%d", f.Script, f.Line))
	}
	add(i18n.T("Command"), f.Command)
	if f.Code != 0 {
		add(i18n.T("Exit code"), strconv.Itoa(f.Code))
	}
	return out
}

// Error renders the one format every failure is reported in.
func (f *Failure) Error() string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s failed", f.Unit)
	for _, kv := range f.Fields() {
		fmt.Fprintf(&b, "\n%-11s %s", kv[0]+":", kv[1])
	}
	if f.Stderr != "" {
		fmt.Fprintf(&b, "\n%-11s %s", i18n.T("Error")+":", f.Stderr)
	}
	return b.String()
}

// parseReport reads the ERR trap's line: code, source, line, command.
//
// A script can also die without the trap — a bare `exit 1` does not fire ERR —
// so a missing or unreadable report is normal and simply leaves the fields
// empty. The exit code alone still names the step that failed.
func parseReport(s string) *Failure {
	fields := strings.SplitN(strings.TrimRight(s, "\n"), "\t", 4)
	if len(fields) != 4 {
		return nil
	}
	code, err := strconv.Atoi(fields[0])
	if err != nil {
		return nil
	}
	line, err := strconv.Atoi(fields[2])
	if err != nil {
		return nil
	}
	return &Failure{Code: code, Script: short(fields[1]), Line: line, Command: fields[3]}
}

// short renders a script path the way whoever wrote it knows it — relative to
// the working dir. Absolute is right only when the path is outside it.
func short(p string) string {
	wd, err := os.Getwd()
	if err != nil {
		return p
	}
	rel, err := filepath.Rel(wd, p)
	if err != nil || strings.HasPrefix(rel, "..") {
		return p
	}
	return rel
}

// exitCode digs the status out of whatever error exec returned.
func exitCode(err error) int {
	type coder interface{ ExitCode() int }
	if e, ok := err.(coder); ok {
		return e.ExitCode()
	}
	return 1
}

// Fail wraps whatever comes back from a script that ran outside a Session — one
// that was handed the terminal — in the one shape failures are reported in.
// There is no trap report to fill in: what went wrong was on screen.
func Fail(unit string, err error) error {
	if err == nil {
		return nil
	}
	return &Failure{Unit: unit, Code: exitCode(err)}
}
