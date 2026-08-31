package tui

import "installer/internal/i18n"

// Every word the interface says that does not come from the installer folder:
// the fixed pages, the buttons, the key hints. They are here as functions
// rather than constants because the language can change while the program is
// running — the first screen is the one that changes it — and a constant read
// at package init would be the one word left in the old language.
//
// The English text is the message and also its own key; see internal/i18n.

// say is the interface's own voice: the message in the language showing, in
// marks the terminal can actually draw. Every word below goes through it,
// because the ones that need rewriting are as likely to arrive from a catalog
// as from the line above — a translation of "⏎ continue" carries the same
// symbol, and a console can draw it no better in German.
func say(msg string, args ...any) string {
	return glyphs.spell.Replace(i18n.T(msg, args...))
}

func labelHintMenu() string     { return say("↑↓ move · ⏎ select · q quit") }
func labelHintList() string     { return say("↑↓ move · ⏎ open · esc back") }
func labelHintChoose() string   { return say("↑↓ move · ⏎ confirm · esc back") }
func labelHintInput() string    { return say("⏎ confirm · esc back") }
func labelHintRunning() string  { return say("working …") }
func labelHintContinue() string { return say("⏎ continue") }
func labelChecking() string     { return say("Checking this machine …") }
func labelHintBack() string     { return say("⏎ back") }
func labelHintClose() string    { return say("⏎ close") }
func labelHintQuit() string     { return say("⏎ quit") }
func labelHintStart() string    { return say("⏎ start · esc back") }

// The network screen: checking for internet, and — where the tree describes
// how — joining a wireless one.
func labelNetwork() string         { return say("Wireless network") }
func labelNetworkHelp() string     { return say("Join a wireless network to continue.") }
func labelNetworkChecking() string { return say("Checking the internet connection …") }
func labelNetworkScanning() string { return say("Looking for wireless networks …") }
func labelNetworkJoining(ssid string) string {
	return say("Joining %s …", ssid)
}
func labelNetworkOffline() string    { return say("There is no internet connection.") }
func labelNetworkNoNetworks() string { return say("No wireless networks in range.") }
func labelPassphrase() string        { return say("Passphrase") }
func labelContinueAnyway() string    { return say("Continue anyway") }
func labelHintNetworkChoosing() string {
	return say("↑↓ move · ⏎ join · r rescan · esc skip")
}
func labelHintNetworkOffline() string { return say("⏎ continue · r retry") }
func labelNetworkOfflineHelp() string {
	return say("The installation downloads everything it installs, so it will not get far without one. Plug in a cable, or press r to look for a network again.")
}
func labelNetworkOfflineHelpUnjoinable() string {
	return say("The installation downloads everything it installs, so it will not get far without one. Plug in a cable, or connect to a wireless network before continuing.")
}

// The narrowing box: the key that opens it, appended to a list's own hint, and
// what the keys mean while it is open.
func labelHintFilterKey() string { return say("/ filter") }
func labelHintFilter() string {
	return say("type to filter · ↑↓ move · ⏎ select · esc close")
}

// labelHintFilterBlind is the permanent box's own hint: esc means back rather
// than close, because there is no box left to close first.
func labelHintFilterBlind() string {
	return say("type to filter · ↑↓ move · ⏎ select · esc back")
}

func labelFilterPlaceholder() string { return say("Filter …") }
func labelNoMatch() string           { return say("No matches") }

func labelLanguage() string     { return say("Interface language") }
func labelLanguageHelp() string { return say("Choose the language for this installer.") }

// The fork at the top, where a tree can do more than one thing. Only the page's
// own name is the runtime's: what is on it, and what each of them is, is said in
// the tree's own words.
func labelMode() string { return say("What to do") }

// labelCounter is where something sits in a run of things: which question of
// how many, which task of how many. Bare numbers, because it is read in the
// header beside what it is counting — a word in front of it would only repeat
// what the page already says.
func labelCounter(at, of int) string { return say("%d of %d", at, of) }

func labelInstall() string     { return say("Install") }
func labelInstallHelp() string { return say("Start the installation with the answers below.") }

func labelSettings() string { return say("Settings") }
func labelSettingsHelp() string {
	return say("Every value this installer will use. Choose one to change it.")
}

func labelPasswordRepeat() string   { return say("Repeat") }
func labelPasswordMismatch() string { return say("The entries do not match.") }

func labelReady() string        { return say("Ready to install") }
func labelStartInstall() string { return say("Start installation") }

// The same two, where the tree named what is about to happen. An installer is
// the only thing an unnamed run can be; a named one is whatever it says it is,
// and the runtime supplies the sentence around the name and nothing else.
func labelReadyToStart() string          { return say("Ready to start") }
func labelStartNamed(name string) string { return say("Start %s", name) }
func labelRunFailed(name string) string  { return say("%s failed", name) }
func labelRunningFor(name, elapsed string) string {
	return say("%s · %s", name, elapsed)
}
func labelRunDone(name, elapsed string) string {
	return say("%s complete in %s", name, elapsed)
}

// The installation, with the clock on it. How long it has been going is the one
// thing somebody watching a list of tasks actually wants to know and cannot work
// out for themselves, and how long it took is the same answer once it is over.
func labelInstalling() string { return say("Installing") }
func labelInstallingFor(elapsed string) string {
	return say("Installing for %s", elapsed)
}
func labelSucceededIn(elapsed string) string {
	return say("Installation complete in %s", elapsed)
}
func labelFailed() string { return say("Installation failed") }
func labelLogHint(path string) string {
	return say("The full log is in %s.", path)
}

// What a question put in the middle of a run says when the answers to it turn
// out to be none. A run cannot go on past it — the value it was waiting for
// does not exist on this machine — so it reads as the failure it is.
func labelNothingToChoose(title string) string {
	return say("%s: there is nothing to choose from.", title)
}

func labelCannotContinue() string { return say("Cannot continue") }

// The way out, on a machine where leaving the installer is not quitting a
// program but deciding what happens to the machine — see leave.go.
func labelLeave() string        { return say("Leave") }
func labelRestart() string      { return say("Restart") }
func labelRestartHelp() string  { return say("Close this machine down and start it again.") }
func labelShutdown() string     { return say("Shut down") }
func labelConsole() string      { return say("Exit to the console") }
func labelShutdownHelp() string { return say("Switch this machine off.") }
func labelRestarting() string   { return say("Restarting …") }
func labelShuttingDown() string { return say("Shutting down …") }
func labelLeaveFailed() string  { return say("This machine did not do as it was told.") }

// The two answers to a task that asks before it runs. The same two words a bool
// is read out in, because they are the same question.
func labelYes() string { return say("Yes") }
func labelNo() string  { return say("No") }
