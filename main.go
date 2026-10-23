// Command claude-never-sleeps keeps the Mac awake, lid close included, while any Claude Code session works.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// version is set at build time with -ldflags "-X main.version=<tag>".
var version = "dev"

const (
	wakeGrace = 60 * time.Second
	// idleGrace stops a short idle moment between turns from letting a closed Mac sleep.
	idleGrace = 15 * time.Second
)

type app struct {
	sessionsDir string
	state       state
	power       power
}

func main() {
	mode := ""
	if len(os.Args) > 1 {
		mode = os.Args[1]
	}
	if mode == "version" {
		fmt.Println(version)
		return
	}
	a := fromEnvironment()
	os.MkdirAll(a.state.dir, 0o755)
	switch mode {
	case "poll":
		a.poll()
	case "wake":
		a.wake()
	case "status":
		a.status()
	case "keep-awake":
		a.state.touch(keepAwakeFlag)
		a.poll()
	case "auto":
		a.state.remove(keepAwakeFlag)
		a.poll()
	default:
		fmt.Fprintln(os.Stderr, "usage: claude-never-sleeps poll|wake|status|keep-awake|auto|version")
		os.Exit(1)
	}
}

// fromEnvironment reads the paths and commands, which tests override with CLAUDE_NEVER_SLEEPS_* variables.
func fromEnvironment() app {
	home, _ := os.UserHomeDir()
	claudeDir := env("CLAUDE_CONFIG_DIR", filepath.Join(home, ".claude"))
	sudo, set := os.LookupEnv("CLAUDE_NEVER_SLEEPS_SUDO")
	if !set {
		sudo = "/usr/bin/sudo -n"
	}
	st := state{
		dir:       env("CLAUDE_NEVER_SLEEPS_STATE_DIR", filepath.Join(home, ".local/state/claude-never-sleeps")),
		osascript: env("CLAUDE_NEVER_SLEEPS_OSASCRIPT", "/usr/bin/osascript"),
	}
	return app{
		sessionsDir: env("CLAUDE_NEVER_SLEEPS_SESSIONS_DIR", filepath.Join(claudeDir, "sessions")),
		state:       st,
		power:       power{pmset: env("CLAUDE_NEVER_SLEEPS_PMSET", "/usr/bin/pmset"), sudo: strings.Fields(sudo), state: st},
	}
}

// env gives the variable's value, or fallback when it is unset or empty.
func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// poll keeps sleep off while anything needs the Mac awake, and turns it on after the idle grace.
func (a app) poll() {
	if reason := a.awakeReason(); reason != "" {
		a.state.remove(idleSinceStamp)
		a.power.setSleepDisabled("1", reason)
	} else if a.state.idleFor(idleGrace) {
		a.power.setSleepDisabled("0", "idle")
	}
}

// awakeReason names why the Mac must stay awake now, or gives "" when nothing needs it.
func (a app) awakeReason() string {
	working := a.anySessionWorking()
	wakeAge, woken := a.state.age(wakeStamp)
	switch {
	case a.state.exists(keepAwakeFlag):
		return "keep-awake"
	case woken && wakeAge < wakeGrace:
		return "prompt"
	case working:
		return "working"
	}
	return ""
}

// anySessionWorking judges every registry file, reports each problem once, and tells whether a session works.
func (a app) anySessionWorking() bool {
	working := false
	for _, path := range sessionFiles(a.sessionsDir) {
		judged := judgeSession(path)
		if judged.Problem != "" {
			a.state.reportOnce(judged.Problem, problemMessage(judged))
		}
		working = working || judged.Working
	}
	return working
}

func problemMessage(judged verdict) string {
	if judged.Problem == "incomplete-file" {
		return "session file without pid, status or procStart, counted as idle"
	}
	return fmt.Sprintf("unknown session status '%s', counted as idle", judged.Status)
}

// wake runs from the UserPromptSubmit hook, so a lid closed right after a prompt cannot beat the next poll.
func (a app) wake() {
	a.state.touch(wakeStamp)
	a.power.setSleepDisabled("1", "prompt")
}

// status prints the setting, the mode and each session; it only reads, so it never logs or notifies.
func (a app) status() {
	fmt.Println("SleepDisabled: " + a.power.sleepDisabled())
	if a.state.exists(keepAwakeFlag) {
		fmt.Println("mode: keep awake (until 'claude-never-sleeps auto')")
	} else {
		fmt.Println("mode: auto (sessions decide)")
	}
	for _, path := range sessionFiles(a.sessionsDir) {
		fmt.Println(sessionLine(path, judgeSession(path)))
	}
}

func sessionLine(path string, judged verdict) string {
	if judged.Problem == "incomplete-file" {
		return fmt.Sprintf("session %s: incomplete file, keeps the Mac awake: no", strings.TrimSuffix(filepath.Base(path), ".json"))
	}
	awake := "no"
	if judged.Working {
		awake = "yes"
	}
	return fmt.Sprintf("session %d: status %s, keeps the Mac awake: %s", judged.Pid, judged.Status, awake)
}
