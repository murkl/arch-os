package tui

import "installer/internal/i18n"

// Every word the interface says that does not come from the installer folder:
// the fixed pages, the buttons, the key hints. They are here as functions
// rather than constants because the language can change while the program is
// running — the first screen is the one that changes it — and a constant read
// at package init would be the one word left in the old language.
//
// The English text is the message and also its own key; see internal/i18n.
func labelHintMenu() string     { return i18n.T("↑↓ move · ⏎ select · q quit") }
func labelHintList() string     { return i18n.T("↑↓ move · ⏎ open · esc back") }
func labelHintChoose() string   { return i18n.T("↑↓ move · ⏎ confirm · esc back") }
func labelHintInput() string    { return i18n.T("⏎ confirm · esc back") }
func labelHintRunning() string  { return i18n.T("working …") }
func labelHintContinue() string { return i18n.T("⏎ continue") }
func labelChecking() string     { return i18n.T("Checking this machine …") }
func labelHintBack() string     { return i18n.T("⏎ back") }
func labelHintClose() string    { return i18n.T("⏎ close") }
func labelHintQuit() string     { return i18n.T("⏎ quit") }
func labelHintStart() string    { return i18n.T("⏎ start · esc back") }

// The network screen: checking for internet, and — where the tree describes
// how — joining a wireless one.
func labelNetworkChecking() string { return i18n.T("Checking the internet connection …") }
func labelNetworkScanning() string { return i18n.T("Looking for wireless networks …") }
func labelNetworkJoining(ssid string) string {
	return i18n.T("Joining %s …", ssid)
}
func labelNetworkOffline() string    { return i18n.T("There is no internet connection.") }
func labelNetworkNoNetworks() string { return i18n.T("No wireless networks in range.") }
func labelPassphrase() string        { return i18n.T("Passphrase") }
func labelContinueAnyway() string    { return i18n.T("Continue anyway") }
func labelHintNetworkChoosing() string {
	return i18n.T("↑↓ move · ⏎ join · r rescan · esc skip")
}
func labelHintNetworkOffline() string { return i18n.T("⏎ continue · r retry") }
func labelNetworkOfflineHelp() string {
	return i18n.T("The installation downloads everything it installs, so it will not get far without one. Plug in a cable, or press r to look for a network again.")
}
func labelNetworkOfflineHelpUnjoinable() string {
	return i18n.T("The installation downloads everything it installs, so it will not get far without one. Plug in a cable, or connect to a wireless network before continuing.")
}

// The narrowing box: the key that opens it, appended to a list's own hint, and
// what the keys mean while it is open.
func labelHintFilterKey() string { return i18n.T("/ filter") }
func labelHintFilter() string {
	return i18n.T("type to filter · ↑↓ move · ⏎ select · esc close")
}
func labelFilterPlaceholder() string { return i18n.T("Filter …") }
func labelNoMatch() string           { return i18n.T("No matches") }

func labelLanguage() string     { return i18n.T("Interface language") }
func labelLanguageHelp() string { return i18n.T("Choose the language for this installer.") }

// labelCounter is where something sits in a run of things: which question of
// how many, which task of how many. Bare numbers, because it is read in the
// header beside what it is counting — a word in front of it would only repeat
// what the page already says.
func labelCounter(at, of int) string { return i18n.T("%d of %d", at, of) }

func labelInstall() string     { return i18n.T("Install") }
func labelInstallHelp() string { return i18n.T("Start the installation with the answers below.") }

func labelSettings() string { return i18n.T("Settings") }
func labelSettingsHelp() string {
	return i18n.T("Every value this installer will use. Choose one to change it.")
}

func labelPasswordRepeat() string   { return i18n.T("Repeat") }
func labelPasswordMismatch() string { return i18n.T("The entries do not match.") }

func labelReady() string        { return i18n.T("Ready to install") }
func labelStartInstall() string { return i18n.T("Start installation") }

// The installation, with the clock on it. How long it has been going is the one
// thing somebody watching a list of tasks actually wants to know and cannot work
// out for themselves, and how long it took is the same answer once it is over.
func labelInstalling() string { return i18n.T("Installing") }
func labelInstallingFor(elapsed string) string {
	return i18n.T("Installing for %s", elapsed)
}
func labelSucceededIn(elapsed string) string {
	return i18n.T("Installation complete in %s", elapsed)
}
func labelFailed() string { return i18n.T("Installation failed") }
func labelLogHint(path string) string {
	return i18n.T("The full log is in %s.", path)
}

func labelCannotContinue() string { return i18n.T("Cannot continue") }

// The way out, on a machine where leaving the installer is not quitting a
// program but deciding what happens to the machine — see leave.go.
func labelLeave() string        { return i18n.T("Leave") }
func labelRestart() string      { return i18n.T("Restart") }
func labelRestartHelp() string  { return i18n.T("Close this machine down and start it again.") }
func labelShutdown() string     { return i18n.T("Shut down") }
func labelConsole() string      { return i18n.T("Exit to the console") }
func labelShutdownHelp() string { return i18n.T("Switch this machine off.") }
func labelRestarting() string   { return i18n.T("Restarting …") }
func labelShuttingDown() string { return i18n.T("Shutting down …") }
func labelLeaveFailed() string  { return i18n.T("This machine did not do as it was told.") }

// The two answers to a task that asks before it runs. The same two words a bool
// is read out in, because they are the same question.
func labelYes() string { return i18n.T("Yes") }
func labelNo() string  { return i18n.T("No") }
