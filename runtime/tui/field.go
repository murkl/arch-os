package tui

import (
	"strings"

	"github.com/murkl/arch-os/runtime/internal/runner"
	"github.com/murkl/arch-os/runtime/internal/spec"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// fieldScreen asks for one value.
//
// Which of the two shapes it takes is not a decision this file makes: a
// variable that has a set of answers is a list, and one that does not is a text
// box. The declaration is already a complete description of the question, and
// it is the same page whether it is reached from the opening run of questions
// or from the settings page afterwards — one way of answering, learnt once.
type fieldScreen struct {
	app  *app
	v    *spec.Variable
	done func() tea.Cmd

	// step is where this question sits in the opening run — "3 of 7" — and is
	// zero everywhere else. Somebody being asked a series of questions is owed
	// the length of it; somebody who opened one row of a settings page is not.
	at, of int

	// head is the heading this question stands under, for the few asked in
	// front of the run: they come one after another rather than one inside the
	// other, and a page whose breadcrumb is only its own title reads as if the
	// whole program were this one question.
	head string

	// imports is shell to run once the answer is given, and the page is not got
	// past until it has worked — for the answer whose whole point is what it
	// fetches. A failure is shown exactly where a value that broke a rule is
	// shown: the answer is still in the box, and nothing has moved on.
	imports string
	busy    bool

	picker *picker
	input  textinput.Model
	typing bool

	// The answers as they came back, and the box that narrows them. Kept beside
	// the list, because what a query hides has to still be there to come back:
	// a timezone list is six hundred rows and typing into it is the only sane
	// way through.
	values []item
	filter *filter

	loading bool
	problem string
}

// keyFieldFree is the row that opens the text box under a list of answers. The
// NUL prefix cannot collide with a value, which is what any other row is.
const keyFieldFree = "\x00free"

func newField(a *app, v *spec.Variable, done func() tea.Cmd) *fieldScreen {
	return &fieldScreen{app: a, v: v, done: done, loading: true, filter: newFilter(v.Blind)}
}

// counted marks this question as one of a numbered run.
func (s *fieldScreen) counted(at, of int) *fieldScreen {
	s.at, s.of = at, of
	return s
}

// opening marks this question as one of the few asked before the run proper,
// which is where it is put in the breadcrumb rather than how it is asked.
func (s *fieldScreen) opening() *fieldScreen {
	s.head = labelOpening()
	return s
}

// importing hangs shell on the answer: it runs when the answer is given, off
// the frame, and the page stays where it is until it comes back. See
// Runner.Import — what such a script does is answer further questions.
func (s *fieldScreen) importing(shell string) *fieldScreen {
	s.imports = shell
	return s
}

func (s *fieldScreen) Title() string { return s.v.Label() }

// working puts the turning mark in the header while the answer is being made
// good on. The page itself keeps drawing, so what is on screen is the question
// with its answer in it and something visibly happening about it.
func (s *fieldScreen) working() bool { return s.busy }

// takesText: the text box, and the narrowing box over a list of answers.
// Neither while the answer already given is being made good on, when the page
// is answering nothing at all.
func (s *fieldScreen) takesText() bool { return !s.busy && (s.typing || s.filter.active()) }

func (s *fieldScreen) Init() tea.Cmd {
	// The answers can come from a command and the suggestion from another, and
	// either can take a moment — a timezone guessed over the network does. Both
	// are fetched off the frame rather than in front of a frozen one.
	return tea.Batch(tick(), func() tea.Msg {
		values, _ := s.app.runner.Options(s.v)
		return fieldMsg{values: values, prefill: s.app.runner.Prefill(s.v)}
	})
}

type fieldMsg struct {
	values  []runner.Option
	prefill string
}

func (s *fieldScreen) Hint() string {
	switch {
	case s.busy:
		return labelHintRunning()
	case s.typing:
		return labelHintInput()
	}
	return filterHint(labelHintChoose(), s.filter)
}

// typeIn turns the page into a text box holding value. The constructor and
// Focus are both load bearing: an unfocused textinput silently ignores every
// keystroke.
func (s *fieldScreen) typeIn(value string) {
	s.typing = true
	s.input = textinput.New()
	s.input.SetValue(value)
	s.input.CharLimit = 256
	styleInput(&s.input)
	s.input.Focus()
}

func (s *fieldScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	switch msg := msg.(type) {
	case fieldMsg:
		s.loading = false
		current := s.app.store.Get(s.v.Name)
		if current == "" {
			current = msg.prefill
		}
		if len(msg.values) == 0 {
			// Nothing to choose from, so it is a text box.
			s.typeIn(current)
			return s, textinput.Blink
		}
		s.values = make([]item, 0, len(msg.values))
		for _, o := range msg.values {
			s.values = append(s.values, item{title: o.Label, key: o.Value})
		}
		s.picker = newPicker(s.list())
		s.picker.focus(current)
		if s.filter.permanent {
			return s, textinput.Blink
		}
		return s, nil

	case tickMsg:
		if s.loading {
			return s, tick()
		}
		return s, nil

	case importedMsg:
		s.busy = false
		if err := msg.err; err != nil {
			s.problem = err.Error()
			return s, nil
		}
		// Whatever it wrote is read back on this side, where the answers are
		// only ever touched — and only now saved, so the file holds the merge
		// rather than what was in memory before it.
		if err := s.app.runner.Imported(); err != nil {
			s.problem = err.Error()
			return s, nil
		}
		return s, tea.Batch(s.app.save(), s.done())

	case tea.KeyMsg:
		// Nothing is answerable while the answer already given is being made
		// good on. ctrl+c still leaves, as it does everywhere.
		if s.busy {
			return s, nil
		}
		// The narrowing box gets the key before the page does: / opens it,
		// typing narrows, esc closes it — which is why esc only leaves the
		// question once there is no box left to close. Not while the text box is
		// up, though: there every key is already a character.
		if s.choosing() {
			if took, cmd := s.filter.Update(msg); took {
				s.narrow()
				return s, cmd
			}
		}
		switch {
		// Backspace leaves the question as well, but the text box has the first
		// claim on it: while there is something to delete it deletes, and it
		// only means back once the box is empty.
		case cancels(msg), erases(msg) && !s.hasText():
			// A box opened from a list goes back to that list rather than out of
			// the page: choosing to type an answer is a step inside this
			// question, so undoing it lands on the answers again.
			if s.typing && s.picker != nil {
				s.typing, s.problem = false, ""
				return s, nil
			}
			return s, pop()
		case confirms(msg):
			return s.commit()
		}
		if s.typing {
			var cmd tea.Cmd
			s.input, cmd = s.input.Update(msg)
			return s, cmd
		}
		if s.picker != nil {
			s.picker.Update(msg)
		}
	}
	return s, nil
}

// hasText reports whether the page is holding text a keystroke could still be
// meant for. A list has none, and neither has an empty box.
func (s *fieldScreen) hasText() bool { return s.typing && s.input.Value() != "" }

// choosing reports whether a list of answers is on screen: not the text box,
// and not the moment before the answers have arrived.
func (s *fieldScreen) choosing() bool { return !s.typing && s.picker != nil }

// list is the rows the page shows: the answers the box has left of them, and
// under those the row that opens the text box. That row is never narrowed away —
// it is not an answer among them but the way to give one they do not hold,
// which is exactly what a query that found nothing is looking for.
func (s *fieldScreen) list() []item {
	items := narrow(s.values, s.filter.query())
	if len(items) == 0 && s.filter.query() != "" {
		items = append(items, item{title: labelNoMatch(), disabled: true})
	}
	if s.v.Free != "" {
		items = append(items, item{title: glyphs.add + " " + s.v.FreeLabel(), key: keyFieldFree})
	}
	return items
}

// narrow rebuilds the list for the query now in the box, keeping the cursor on
// its row wherever that row survived.
func (s *fieldScreen) narrow() {
	sel := s.picker.selected()
	s.picker = newPicker(s.list())
	s.picker.focus(sel)
}

// commit checks the answer against the rules the variable itself declares, so a
// value chosen here is held to exactly the same standard as one edited straight
// into the answer file.
func (s *fieldScreen) commit() (screen, tea.Cmd) {
	if s.loading {
		return s, nil
	}
	var value string
	switch {
	case s.typing:
		value = strings.TrimSpace(s.input.Value())
	case s.picker != nil:
		var ok bool
		value, ok = s.picker.chosen()
		// Nothing under the cursor is nothing to commit: enter on a list
		// narrowed to nothing. An empty value under it is a different thing —
		// "no variant", "the default" — and is committed like any other.
		if !ok {
			return s, nil
		}
		// Not an answer but the way to give one the list does not hold. The box
		// opens empty: this row says a new value is being named, and starting it
		// on the answer already in force would invite confirming that instead.
		if value == keyFieldFree {
			s.problem = ""
			s.typeIn("")
			return s, textinput.Blink
		}
	}
	if why := s.app.store.Invalid(s.v, value); why != "" {
		s.problem = why
		return s, nil
	}
	s.app.store.Set(s.v.Name, value)
	// In force before the next page rather than alongside it: an answer that
	// changes the machine this is running on — the console keyboard — has to
	// hold for whatever is typed next, and the next page is where that is typed.
	s.app.runner.Apply(s.v)
	// The one answer that can also be about this program: a module may tie the
	// words on screen to a variable of its own, and then the next frame is
	// already read in the language just chosen.
	if s.v.Name == s.app.module.Language {
		s.app.speakLike(value)
	}
	// An answer with shell hanging on it is not given until that shell has
	// worked. It runs off the frame — it talks to the network — so the page
	// keeps drawing, with the mark turning, and answers the result below.
	//
	// Written down first, and that is load bearing: what such a script writes is
	// read back over the answers held, and the file would otherwise still carry
	// the value this answer replaced — which would quietly undo it.
	if s.imports != "" {
		s.busy, s.problem = true, ""
		run := s.app.runner.Import(s.imports)
		return s, tea.Batch(s.app.save(), func() tea.Msg { return importedMsg{run()} })
	}
	return s, tea.Batch(s.app.save(), s.done())
}

// importedMsg is that shell coming back, with whatever it had to say about why
// it would not work.
type importedMsg struct{ err error }

// View opens with the variable's own description — what this value is for, in
// the folder's own words. It is the reason a list of names is answerable by
// somebody who has never installed anything.
func (s *fieldScreen) View(width, height int) string {
	var b strings.Builder
	if help := s.v.Help(); help != "" {
		head := paragraph(help, width) + "\n\n"
		height -= strings.Count(head, "\n")
		b.WriteString(head)
	}
	switch {
	case s.loading:
		b.WriteString(accentStyle.Render(spinFrame()))
	case s.typing:
		b.WriteString(cursorStyle.Render(glyphs.cursor) + s.input.View())
	default:
		b.WriteString(s.filter.View())
		b.WriteString(s.picker.View(width, height-s.problemRows()-s.filter.rows()))
	}
	if s.problem != "" {
		b.WriteString("\n\n" + failStyle.Render(truncate(s.problem, width)))
	}
	return b.String()
}

// problemRows is what a refusal costs the list under it — nothing until there
// is one, so a page that never refuses anything is never short a row.
func (s *fieldScreen) problemRows() int {
	if s.problem == "" {
		return 0
	}
	return 2
}

// crumbRoot: a question asked in a run stands alone, whichever run it is.
// Which questions came before it is what the counter in the header says, or the
// heading above it, and a growing line of answers already given would say the
// same thing a third time and worse. A question opened from the settings page
// is the exception: there it really is one page inside another.
func (s *fieldScreen) crumbRoot() bool { return s.of > 0 || s.head != "" }

func (s *fieldScreen) crumbHead() string { return s.head }

// status is the question's place in the opening run, shown in the header where
// every other page shows what it is doing. Empty outside that run.
func (s *fieldScreen) status() string {
	if s.of == 0 {
		return ""
	}
	return labelCounter(s.at, s.of)
}
