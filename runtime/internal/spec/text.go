package spec

import "strings"

// Expand fills {{VAR}} in a sentence from the answers given.
//
// Deliberately not a template language and deliberately not $VAR: this text is
// read next to shell that uses $VAR for something else entirely — the
// environment a script sees — and one notation meaning two things in one tree
// is how a warning ends up naming the wrong disk. A name nothing answers is
// left empty rather than left as its own braces, which would put the machinery
// on screen at the one moment somebody has to read carefully.
func Expand(s string, get func(string) string) string {
	if !strings.Contains(s, "{{") {
		return s
	}
	var b strings.Builder
	for {
		i := strings.Index(s, "{{")
		if i < 0 {
			break
		}
		j := strings.Index(s[i:], "}}")
		if j < 0 {
			break
		}
		b.WriteString(s[:i])
		b.WriteString(get(strings.TrimSpace(s[i+2 : i+j])))
		s = s[i+j+2:]
	}
	b.WriteString(s)
	return b.String()
}
