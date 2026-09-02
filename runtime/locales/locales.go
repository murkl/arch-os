// Package locales holds the runtime's own words in every language it has been
// translated into, compiled into the binary so a translation is never a file
// that can go missing.
//
// One po file per language, named by its code. Adding a language is adding a
// file: copy arch-os.pot to <code>.po, fill in the right-hand side, done.
// Anything left untranslated stays as it is written in the code, which is
// English — so a partial catalog is useful from its first line.
//
// arch-os.pot is the list those files are filled in from, and it is generated:
// it is every string the Go sources hand to T, read out of them rather than
// kept beside them. `make locales` writes it and brings the catalogs up to it.
//
// These are the frame's own words only: key hints, buttons, the labels on a
// failure report. Everything an installer says about itself — variables, stages,
// presets — is translated in its own folder, under locales/ there.
package locales

import "embed"

// The template is deliberately not embedded: it says nothing a running program
// needs, and every message in it is already in the binary as the source text.
//
//go:embed *.po
var FS embed.FS
