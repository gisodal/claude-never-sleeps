package main

import (
	"fmt"
	"os/exec"
	"strings"
)

// power reads and writes the disablesleep setting with pmset.
type power struct {
	pmset string
	// sudo is the command and flags that run pmset as root; empty runs pmset directly.
	sudo  []string
	state state
}

// sleepDisabled gives the current SleepDisabled value from pmset -g; a missing line reads as "0".
func (p power) sleepDisabled() string {
	output, _ := exec.Command(p.pmset, "-g").Output()
	for _, line := range strings.Split(string(output), "\n") {
		if fields := strings.Fields(line); len(fields) >= 2 && fields[0] == "SleepDisabled" {
			return fields[1]
		}
	}
	return "0"
}

// setSleepDisabled writes value only when it differs from the current one, and logs the change with its reason.
func (p power) setSleepDisabled(value, reason string) {
	if p.sleepDisabled() == value {
		p.state.remove(writeFailedMarker)
		return
	}
	if output, err := p.writeSleepDisabled(value); err != nil {
		p.logFailedWriteOnce(value, fmt.Sprintf("disablesleep %s failed (%s): %s", value, reason, output))
		return
	}
	p.state.remove(writeFailedMarker)
	p.state.log(fmt.Sprintf("disablesleep %s (%s)", value, reason))
}

func (p power) writeSleepDisabled(value string) (string, error) {
	command := append(append([]string{}, p.sudo...), p.pmset, "-a", "disablesleep", value)
	output, err := exec.Command(command[0], command[1:]...).CombinedOutput()
	return strings.TrimRight(string(output), "\n"), err
}

// logFailedWriteOnce logs a failed write once, not on every poll that retries it.
func (p power) logFailedWriteOnce(value, message string) {
	if p.state.read(writeFailedMarker) != value {
		p.state.log(message)
	}
	p.state.write(writeFailedMarker, value)
}
