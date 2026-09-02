// Command potgen writes the runtime's translation template to stdout.
//
// The list of what needs translating is read out of the Go sources rather than
// kept by hand beside them: every T("…") and every say("…") is a message, so a
// word added, reworded or deleted is in the template the next time this runs
// and in front of the translators the next time that is committed. Nothing can
// drift, because there is nothing to keep in step.
//
// Only string literals are taken. T(sp.UI.Title) is a message too, but it is
// the installer tree's rather than the runtime's, and the tree lists its own —
// see the -strings flag on the runtime itself.
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"installer/internal/i18n"
)

// project is what the template says it belongs to: the program as it ships,
// not the module it is built from.
const project = "archos"

// keywords are the calls that put a string in front of somebody — the
// translator itself, and the interface's own voice, which wraps it.
var keywords = map[string]bool{"T": true, "say": true}

// note is the comment a translator gets to see, written above the call the way
// gettext has always done it.
const note = "TRANSLATORS:"

func main() {
	entries, err := collect(".")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := i18n.Template(os.Stdout, project, entries); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// found is one message while it is still being collected: the same text may be
// said in several places, and all of them are worth knowing about.
type found struct {
	note string
	refs []string
	file string
	line int
}

func collect(root string) ([]i18n.Entry, error) {
	fset := token.NewFileSet()
	msgs := map[string]*found{}

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		// Tests say things no user ever reads.
		if d.IsDir() || filepath.Ext(path) != ".go" || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		file, err := parser.ParseFile(fset, path, nil, parser.ParseComments)
		if err != nil {
			return err
		}
		// A note is written above the message it is about, or above whatever
		// holds it — a one-line function is still one thing. It belongs to the
		// first message under it and to no other.
		notes := translatorNotes(fset, file)
		pending := ""
		ast.Inspect(file, func(n ast.Node) bool {
			if written, ok := notes[n]; ok {
				pending = written
			}
			call, ok := n.(*ast.CallExpr)
			if !ok || !keywords[name(call.Fun)] || len(call.Args) == 0 {
				return true
			}
			text, ok := literal(call.Args[0])
			if !ok {
				return true
			}
			at := fset.Position(call.Pos())
			rel := filepath.ToSlash(strings.TrimPrefix(at.Filename, "./"))
			m := msgs[text]
			if m == nil {
				m = &found{file: rel, line: at.Line}
				msgs[text] = m
			}
			m.refs = append(m.refs, fmt.Sprintf("%s:%d", rel, at.Line))
			if m.note == "" {
				m.note = pending
			}
			pending = ""
			return true
		})
		return nil
	})
	if err != nil {
		return nil, err
	}

	out := make([]i18n.Entry, 0, len(msgs))
	for text, m := range msgs {
		out = append(out, i18n.Entry{Text: text, Note: m.note, Refs: m.refs})
	}
	// Where a message is said, so the template reads like the program is laid
	// out and a diff of it stays small.
	sort.Slice(out, func(i, j int) bool {
		a, b := msgs[out[i].Text], msgs[out[j].Text]
		if a.file != b.file {
			return a.file < b.file
		}
		return a.line < b.line
	})
	return out, nil
}

// translatorNotes are the TRANSLATORS: comments in a file, each against the
// thing it was written above. Every other comment is a note to whoever reads
// the code, and putting those in front of a translator would be noise.
func translatorNotes(fset *token.FileSet, file *ast.File) map[ast.Node]string {
	out := map[ast.Node]string{}
	for node, groups := range ast.NewCommentMap(fset, file, file.Comments) {
		for _, group := range groups {
			text := strings.TrimSpace(group.Text())
			if !strings.HasPrefix(text, note) {
				continue
			}
			text = strings.TrimSpace(strings.TrimPrefix(text, note))
			out[node] = strings.Join(strings.Fields(text), " ")
		}
	}
	return out
}

// name is what a call is called, whether it was reached through a package or
// not: i18n.T and T are the same function to this.
func name(fun ast.Expr) string {
	switch f := fun.(type) {
	case *ast.Ident:
		return f.Name
	case *ast.SelectorExpr:
		return f.Sel.Name
	}
	return ""
}

// literal is the text of a string literal, or nothing where the argument is
// anything else.
func literal(arg ast.Expr) (string, bool) {
	lit, ok := arg.(*ast.BasicLit)
	if !ok || lit.Kind != token.STRING {
		return "", false
	}
	s, err := strconv.Unquote(lit.Value)
	if err != nil || strings.TrimSpace(s) == "" {
		return "", false
	}
	return s, true
}
