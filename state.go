package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"time"
)

// Files in the state dir; a flag or stamp exists or not, and a stamp's age is its modification time.
const (
	keepAwakeFlag     = "keep-awake"
	wakeStamp         = "wake"
	idleSinceStamp    = "idle-since"
	writeFailedMarker = "write-failed"
	logFile           = "log"
)

// state is the folder that keeps flags, stamps and the log between polls.
type state struct {
	dir       string
	osascript string
}

func (s state) path(name string) string { return filepath.Join(s.dir, name) }

func (s state) exists(name string) bool {
	_, err := os.Stat(s.path(name))
	return err == nil
}

// touch creates the file, or empties it and so moves its modification time to now.
func (s state) touch(name string) { s.write(name, "") }

func (s state) remove(name string) { os.Remove(s.path(name)) }

func (s state) read(name string) string {
	data, _ := os.ReadFile(s.path(name))
	return string(data)
}

func (s state) write(name, text string) { os.WriteFile(s.path(name), []byte(text), 0o644) }

// age tells how long ago the file was last touched; false when it does not exist.
func (s state) age(name string) (time.Duration, bool) {
	info, err := os.Stat(s.path(name))
	if err != nil {
		return 0, false
	}
	return time.Since(info.ModTime()), true
}

// idleFor starts the idle stamp when it is missing and tells whether the idle time has lasted at least grace.
func (s state) idleFor(grace time.Duration) bool {
	idle, ok := s.age(idleSinceStamp)
	if !ok {
		s.touch(idleSinceStamp)
	}
	return ok && idle >= grace
}

func (s state) log(message string) {
	file, err := os.OpenFile(s.path(logFile), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer file.Close()
	file.WriteString(time.Now().Format(time.RFC3339) + " " + message + "\n")
}

// reportOnce logs and shows a notification the first time key comes up, so a changed registry does not repeat every poll.
func (s state) reportOnce(key, message string) {
	seen := "seen-" + unsafeNameChars.ReplaceAllString(key, "_")
	if s.exists(seen) {
		return
	}
	s.touch(seen)
	s.log(message)
	s.notify(message)
}

var unsafeNameChars = regexp.MustCompile(`[^A-Za-z0-9-]`)

// notify passes the message as an argument, so quotes in it cannot break the AppleScript.
func (s state) notify(message string) {
	exec.Command(s.osascript,
		"-e", "on run argv",
		"-e", `display notification (item 1 of argv) with title "claude-never-sleeps"`,
		"-e", "end run",
		message).Run()
}
