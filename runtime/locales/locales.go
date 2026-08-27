// Package locales holds the runtime's own words in every language it has been
// translated into, compiled into the binary so a translation is never a file
// that can go missing.
//
// One file per language, named by its code. Adding a language is adding a file:
// copy de.yaml, translate the right-hand side, done. Anything left untranslated
// stays as it is written in the code, which is English — so a partial catalog
// is useful from its first line.
//
// These are the frame's own words only: key hints, buttons, the labels on a
// failure report. Everything an installer says about itself — variables, stages,
// presets — is translated in its own folder, under locales/ there.
package locales

import "embed"

//go:embed *.yaml
var FS embed.FS
