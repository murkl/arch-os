package logging

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// One line, as anything reading the log has to be able to split it.
var line = regexp.MustCompile(`^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| (INFO|WARN|ERROR|DEBUG) \| (.*)$`)

func open(t *testing.T) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "installer.log")
	if err := Init(p); err != nil {
		t.Fatal(err)
	}
	return p
}

func read(t *testing.T, p string) []string {
	t.Helper()
	body, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Split(strings.TrimRight(string(body), "\n"), "\n")
}

func TestEveryLineCarriesAStampAndALevel(t *testing.T) {
	p := open(t)
	Info("prepare %s", "disk")
	Warn("slow mirror")
	Error("it failed")

	got := read(t, p)
	if len(got) != 3 {
		t.Fatalf("got %d lines, want 3: %q", len(got), got)
	}
	for _, want := range []struct{ level, msg string }{
		{"INFO", "prepare disk"},
		{"WARN", "slow mirror"},
		{"ERROR", "it failed"},
	} {
		m := line.FindStringSubmatch(got[0])
		if m == nil {
			t.Fatalf("%q is not a log line", got[0])
		}
		if m[1] != want.level || m[2] != want.msg {
			t.Errorf("got %s | %s, want %s | %s", m[1], m[2], want.level, want.msg)
		}
		got = got[1:]
	}
}

// A script's output arrives in whatever chunks the pipe hands over, and has to
// come out as one log line per text line regardless.
func TestScriptOutputIsSplitIntoLines(t *testing.T) {
	p := open(t)
	w := External()
	w.Write([]byte("first\r\nsec"))
	w.Write([]byte("ond\n\nthird\n"))

	got := read(t, p)
	want := []string{"first", "second", "third"}
	if len(got) != len(want) {
		t.Fatalf("got %d lines, want %d: %q", len(got), len(want), got)
	}
	for i, w := range want {
		m := line.FindStringSubmatch(got[i])
		if m == nil {
			t.Fatalf("%q is not a log line", got[i])
		}
		if m[1] != "DEBUG" || m[2] != w {
			t.Errorf("got %s | %s, want DEBUG | %s", m[1], m[2], w)
		}
	}
}

// A line with no newline behind it yet is not a line.
func TestAPartialLineIsHeldBack(t *testing.T) {
	p := open(t)
	External().Write([]byte("no newline yet"))
	if body, _ := os.ReadFile(p); len(body) != 0 {
		t.Errorf("got %q, want nothing written", body)
	}
}

func TestTheLastRunIsKeptBeside(t *testing.T) {
	p := open(t)
	Info("the run before")
	if err := Init(p); err != nil {
		t.Fatal(err)
	}
	Info("this run")

	if got := read(t, p+".old"); !strings.HasSuffix(got[0], "the run before") {
		t.Errorf("the old log holds %q", got)
	}
	if got := read(t, p); !strings.HasSuffix(got[0], "this run") {
		t.Errorf("the new log holds %q", got)
	}
	if Path() != p {
		t.Errorf("Path is %q, want %q", Path(), p)
	}
}

// Losing the log is worse than not having one, but not much worse: a runtime
// that was never given a file still runs.
func TestWritingWithNoLogOpenIsHarmless(t *testing.T) {
	mu.Lock()
	if file != nil {
		file.Close()
	}
	file, path = nil, ""
	mu.Unlock()

	Info("nowhere to go")
	External().Write([]byte("nor this\n"))
}
