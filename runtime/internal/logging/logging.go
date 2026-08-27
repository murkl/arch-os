// Package logging is the single sink for everything a run records — the
// runtime's own progress and every line a script prints.
//
// Each line is pipe-separated: timestamp | level | message
//
//	2026-08-26 14:08:01 | INFO | Prepare disk
//	2026-08-26 14:08:02 | DEBUG | :: Synchronizing package databases...
//	2026-08-26 14:08:09 | ERROR | Prepare disk failed
//
// The level says who emitted the line without needing a column of its own: the
// runtime uses INFO/WARN/ERROR, a script's captured output uses DEBUG (see
// External), so third-party noise is filtered by level alone.
//
// This is where every technical detail goes, and it is the only place: the
// interface shows a spinner and a name, never a line of build output. A log
// nobody reads is cheap; a frame torn apart by somebody else's progress bar is
// not.
package logging

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

const stampLayout = "2006-01-02 15:04:05"

// externalLevel tags output that did not originate in the runtime. A distinct,
// low level keeps the noise filterable.
const externalLevel = "DEBUG"

var (
	mu   sync.Mutex
	file *os.File
	path string
)

// Init opens path as the log file, keeping the previous run's log as
// "<path>.old". Without it every write is a no-op, so a failure here never
// stops a run — losing the log is worse than not having one, but not that much
// worse.
func Init(p string) error {
	mu.Lock()
	defer mu.Unlock()
	if file != nil {
		file.Close()
		file = nil
	}
	if _, err := os.Stat(p); err == nil {
		os.Rename(p, p+".old")
	}
	f, err := os.OpenFile(p, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	file, path = f, p
	return nil
}

// Path is the file being written, so the interface can tell someone where to
// look without being told twice.
func Path() string {
	mu.Lock()
	defer mu.Unlock()
	return path
}

// There is no Close: the log stays open for the life of the process, so a
// failure reported on the way out still lands in it. Every line is written
// straight to the file, so nothing is buffered and nothing is lost at exit.

// Info, Warn and Error record one line for messages the runtime itself emits.
func Info(format string, a ...any)  { write("INFO", fmt.Sprintf(format, a...)) }
func Warn(format string, a ...any)  { write("WARN", fmt.Sprintf(format, a...)) }
func Error(format string, a ...any) { write("ERROR", fmt.Sprintf(format, a...)) }

func write(level, msg string) {
	mu.Lock()
	defer mu.Unlock()
	if file == nil {
		return
	}
	fmt.Fprintf(file, "%s | %s | %s\n", time.Now().Format(stampLayout), level, msg)
}

// External returns an io.Writer that logs a script's output, one log line per
// text line, at externalLevel.
func External() io.Writer { return &lineWriter{level: externalLevel} }

type lineWriter struct {
	level string
	buf   []byte
}

func (w *lineWriter) Write(p []byte) (int, error) {
	w.buf = append(w.buf, p...)
	for {
		i := bytes.IndexByte(w.buf, '\n')
		if i < 0 {
			break
		}
		if line := bytes.TrimRight(w.buf[:i], "\r"); len(line) > 0 {
			write(w.level, string(line))
		}
		w.buf = w.buf[i+1:]
	}
	return len(p), nil
}
