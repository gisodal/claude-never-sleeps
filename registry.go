package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// verdict is what one session file says about its Claude Code session.
type verdict struct {
	Pid     int
	Status  string
	Working bool
	// Problem is "" for a usable file, "incomplete-file", or "status-<status>" for an unknown status.
	Problem string
}

// sessionFile is the part of a registry file we read; a nil field was missing.
type sessionFile struct {
	Pid       *int    `json:"pid"`
	Status    *string `json:"status"`
	ProcStart *string `json:"procStart"`
}

// judgeSession tells whether the session in one registry file keeps the Mac awake.
func judgeSession(path string) verdict {
	session, ok := readSessionFile(path)
	if !ok {
		return verdict{Problem: "incomplete-file"}
	}
	judged := verdict{Pid: *session.Pid, Status: *session.Status}
	if !processAlive(judged.Pid, *session.ProcStart) {
		return judged
	}
	switch judged.Status {
	case "busy", "shell":
		judged.Working = true
	case "idle":
	default:
		judged.Problem = "status-" + judged.Status
	}
	return judged
}

// readSessionFile decodes one registry file; false when it is unreadable or lacks pid, status or procStart.
func readSessionFile(path string) (sessionFile, bool) {
	var session sessionFile
	data, err := os.ReadFile(path)
	if err != nil || json.Unmarshal(data, &session) != nil {
		return session, false
	}
	return session, session.Pid != nil && session.Status != nil && session.ProcStart != nil
}

// processAlive tells whether pid still runs the process that wrote the file, not a later one that reused the pid.
func processAlive(pid int, procStart string) bool {
	started, ok := processStart(pid)
	return ok && sameStart(formatProcStart(started), procStart)
}

// sessionFiles lists the registry files in dir, sorted; none when dir is missing.
func sessionFiles(dir string) []string {
	files, _ := filepath.Glob(filepath.Join(dir, "*.json"))
	return files
}

// processStart gives the start time of pid to the second, as ps shows it; false when no such process runs.
func processStart(pid int) (time.Time, bool) {
	proc, err := unix.SysctlKinfoProc("kern.proc.pid", pid)
	if err != nil || int(proc.Proc.P_pid) != pid {
		return time.Time{}, false
	}
	return time.Unix(proc.Proc.P_starttime.Sec, 0), true
}

// formatProcStart writes t the way the registry stores procStart: ps lstart in UTC.
func formatProcStart(t time.Time) string {
	return t.UTC().Format(time.ANSIC)
}

// sameStart compares two start times as text, ignoring runs of spaces.
func sameStart(a, b string) bool {
	return strings.Join(strings.Fields(a), " ") == strings.Join(strings.Fields(b), " ")
}
