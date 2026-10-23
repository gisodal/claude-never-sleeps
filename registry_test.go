package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestFormatProcStartPadsTheDay(t *testing.T) {
	utc := time.Date(2026, 10, 9, 21, 14, 49, 0, time.UTC)
	if got := formatProcStart(utc); got != "Fri Oct  9 21:14:49 2026" {
		t.Errorf("got %q", got)
	}
	amsterdam := utc.In(time.FixedZone("CEST", 2*60*60))
	if got := formatProcStart(amsterdam); got != "Fri Oct  9 21:14:49 2026" {
		t.Errorf("other zone: got %q", got)
	}
}

func TestSameStartIgnoresRunsOfSpaces(t *testing.T) {
	if !sameStart("Fri Oct  9 21:14:49 2026", "Fri Oct 9 21:14:49 2026   ") {
		t.Error("padded start does not match")
	}
	if sameStart("Fri Oct  9 21:14:49 2026", "Fri Oct  9 21:14:50 2026") {
		t.Error("a different second matches")
	}
}

func TestProcessStartMatchesPs(t *testing.T) {
	sleeper := exec.Command("sleep", "30")
	if err := sleeper.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { sleeper.Process.Kill(); sleeper.Wait() })
	pid := sleeper.Process.Pid

	ps := exec.Command("ps", "-o", "lstart=", "-p", strconv.Itoa(pid))
	ps.Env = append(os.Environ(), "LC_ALL=C", "TZ=UTC")
	want, err := ps.Output()
	if err != nil {
		t.Fatal(err)
	}
	started, ok := processStart(pid)
	if !ok {
		t.Fatal("no start for a live process")
	}
	if got := formatProcStart(started); !sameStart(got, string(want)) {
		t.Errorf("got %q, ps says %q", got, want)
	}
}

func TestProcessStartOfAMissingPidIsFalse(t *testing.T) {
	ended := exec.Command("true")
	if err := ended.Run(); err != nil {
		t.Fatal(err)
	}
	if _, ok := processStart(ended.Process.Pid); ok {
		t.Error("an ended process has a start")
	}
}

func TestJudgeSession(t *testing.T) {
	pid := os.Getpid()
	started, ok := processStart(pid)
	if !ok {
		t.Fatal("no start for the test process")
	}
	start := formatProcStart(started)
	cases := []struct {
		name string
		json string
		want verdict
	}{
		{"busy", fmt.Sprintf(`{"pid":%d,"status":"busy","procStart":%q}`, pid, start), verdict{Pid: pid, Status: "busy", Working: true}},
		{"shell", fmt.Sprintf(`{"pid":%d,"status":"shell","procStart":%q}`, pid, start), verdict{Pid: pid, Status: "shell", Working: true}},
		{"idle", fmt.Sprintf(`{"pid":%d,"status":"idle","procStart":%q}`, pid, start), verdict{Pid: pid, Status: "idle"}},
		{"wrong start", fmt.Sprintf(`{"pid":%d,"status":"busy","procStart":"Tue Oct 13 06:00:00 2026"}`, pid), verdict{Pid: pid, Status: "busy"}},
		{"no pid", fmt.Sprintf(`{"status":"busy","procStart":%q}`, start), verdict{Problem: "incomplete-file"}},
		{"no status", fmt.Sprintf(`{"pid":%d,"procStart":%q}`, pid, start), verdict{Problem: "incomplete-file"}},
		{"no procStart", fmt.Sprintf(`{"pid":%d,"status":"busy"}`, pid), verdict{Problem: "incomplete-file"}},
		{"unknown status", fmt.Sprintf(`{"pid":%d,"status":"waiting","procStart":%q}`, pid, start), verdict{Pid: pid, Status: "waiting", Problem: "status-waiting"}},
		{"extra fields", fmt.Sprintf(`{"pid":%d,"status":"busy","procStart":%q,"kind":"interactive","cwd":"/tmp"}`, pid, start), verdict{Pid: pid, Status: "busy", Working: true}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), strings.ReplaceAll(c.name, " ", "-")+".json")
			if err := os.WriteFile(path, []byte(c.json), 0o644); err != nil {
				t.Fatal(err)
			}
			if got := judgeSession(path); got != c.want {
				t.Errorf("got %+v, want %+v", got, c.want)
			}
		})
	}
}

func TestSessionFiles(t *testing.T) {
	dir := t.TempDir()
	for _, name := range []string{"2.json", "1.json", "1.abc.key"} {
		os.WriteFile(filepath.Join(dir, name), nil, 0o644)
	}
	got := sessionFiles(dir)
	want := []string{filepath.Join(dir, "1.json"), filepath.Join(dir, "2.json")}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("got %v, want %v", got, want)
	}
	if missing := sessionFiles(filepath.Join(dir, "missing")); len(missing) != 0 {
		t.Errorf("missing dir: got %v", missing)
	}
}
