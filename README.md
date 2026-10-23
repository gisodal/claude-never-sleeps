# claude-never-sleeps

Keeps a Mac awake, lid close included, while a Claude Code session works, and lets it sleep again about 20 s after the last session goes idle.
It also covers the time between turns, while background agents or background shells still run.

## Install

```bash
curl -fsSL https://github.com/gisodal/claude-never-sleeps/releases/latest/download/get.sh | sh
```

It downloads the latest release, checks its SHA-256 and runs its `install.sh`.
The installer asks for your password once, to add a sudoers rule.
Run it as your own user in a desktop session, not over ssh.
Running it again is safe, and updates the install to the latest release.

From source:

```bash
git clone https://github.com/gisodal/claude-never-sleeps.git
cd claude-never-sleeps
go build -o bin/claude-never-sleeps .
./install.sh
```

Requirements: macOS, an admin account, and Claude Code 2.1.296 or newer (the tested version). Go is needed only for an install from source.

## How it works

Claude Code keeps a file per running session in `~/.claude/sessions/<pid>.json` with a `status` field.
A launchd agent runs `claude-never-sleeps poll` every 10 s; each poll is one run of a small Go binary.
When a live session has status `busy` (a turn or background agents) or `shell` (a background shell), it runs `pmset -a disablesleep 1`; otherwise, once all sessions were idle for 15 s, `pmset -a disablesleep 0`.
The 15 s wait stops a short idle moment between turns from letting a closed Mac sleep.
A `UserPromptSubmit` hook runs `claude-never-sleeps wake`, which turns sleep off at once and holds it off for 60 s, so a lid closed right after a prompt cannot beat the first poll.
`disablesleep 1` is the only setting that stops sleep when the lid closes on battery; `caffeinate` cannot.

## What the installer changes

| Item | Path |
| --- | --- |
| Binary and uninstaller | `~/.local/share/claude-never-sleeps/` |
| Log and state | `~/.local/state/claude-never-sleeps/` |
| launchd agent | `~/Library/LaunchAgents/dev.claude-never-sleeps.plist` |
| sudoers rule | `/etc/sudoers.d/claude-never-sleeps` |
| Hook | `UserPromptSubmit` in `~/.claude/settings.json` (backup: `settings.json.claude-never-sleeps.bak`) |

The sudoers rule allows exactly two commands without a password: `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1`.
If you set `CLAUDE_CONFIG_DIR`, the installer uses that folder instead of `~/.claude`.

## Use

```bash
~/.local/share/claude-never-sleeps/claude-never-sleeps status
```

```bash
~/.local/share/claude-never-sleeps/claude-never-sleeps keep-awake
```

```bash
~/.local/share/claude-never-sleeps/claude-never-sleeps auto
```

```bash
~/.local/share/claude-never-sleeps/claude-never-sleeps version
```

`keep-awake` keeps the Mac awake, whatever the sessions do, until you run `auto`; it stays on across restarts.
`auto` is the normal mode: the sessions decide. `status` shows the current mode, and `version` the installed release.
Each change is logged in `~/.local/state/claude-never-sleeps/log`.

## Uninstall

```bash
~/.local/share/claude-never-sleeps/uninstall.sh
```

It removes everything in the table above except the settings backup, and turns sleep back on. It asks for your password once, to remove the sudoers rule.
If a step fails, it says so, keeps itself, and you run it again after you fix the error.

## Limits

- `~/.claude/sessions` is not a documented Claude Code interface, so an update can change it. An unknown status counts as idle and shows one macOS notification.
- A Mac with the lid closed and sleep off stays on. Do not put it in a bag while a session works.
- Sessions that already ran before the install get the prompt hook only after a restart; the 10 s poll covers them at once.
- One user per Mac: the sudoers rule file and the sleep setting are shared, so a second user's install replaces the first.

## Tests

```bash
./test.sh
```

`./test.sh` needs Go: it builds `bin/claude-never-sleeps` first, then runs every test file.
The tests use fakes for `sudo`, `pmset`, `osascript`, `visudo` and `launchctl`, and change nothing outside temporary folders.
