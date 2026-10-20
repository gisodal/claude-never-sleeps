# claude-no-sleep

Keeps a Mac awake, lid close included, while a Claude Code session works, and lets it sleep again about 10 s after the last session goes idle.
It also covers the time between turns, while background agents or background shells still run.

## Install

```bash
git clone <repo url> claude-no-sleep
cd claude-no-sleep
./install.sh
```

`install.sh` asks for your password once, to add a sudoers rule.
Run it as your own user in a desktop session, not over ssh.
Running it again is safe.

Requirements: macOS, an admin account, and Claude Code 2.1.296 or newer (the tested version).

## How it works

Claude Code keeps a file per running session in `~/.claude/sessions/<pid>.json` with a `status` field.
A launchd agent runs `claude-no-sleep poll` every 10 s.
When a live session has status `busy` (a turn or background agents) or `shell` (a background shell), it runs `pmset -a disablesleep 1`; otherwise `pmset -a disablesleep 0`.
A `UserPromptSubmit` hook runs `claude-no-sleep wake`, which turns sleep off at once and holds it off for 60 s, so a lid closed right after a prompt cannot beat the first poll.
`disablesleep 1` is the only setting that stops sleep when the lid closes on battery; `caffeinate` cannot.

## What the installer changes

| Item | Path |
| --- | --- |
| Script and uninstaller | `~/.local/share/claude-no-sleep/` |
| Log and state | `~/.local/state/claude-no-sleep/` |
| launchd agent | `~/Library/LaunchAgents/dev.claude-no-sleep.plist` |
| sudoers rule | `/etc/sudoers.d/claude-no-sleep` |
| Hook | `UserPromptSubmit` in `~/.claude/settings.json` (backup: `settings.json.claude-no-sleep.bak`) |

The sudoers rule allows exactly two commands without a password: `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1`.
If you set `CLAUDE_CONFIG_DIR`, the installer uses that folder instead of `~/.claude`.

## Use

```bash
~/.local/share/claude-no-sleep/claude-no-sleep status
```

```bash
~/.local/share/claude-no-sleep/claude-no-sleep manual-on
```

```bash
~/.local/share/claude-no-sleep/claude-no-sleep manual-off
```

`manual-on` keeps the Mac awake until `manual-off`, whatever the sessions do.
Each change is logged in `~/.local/state/claude-no-sleep/log`.

## Uninstall

```bash
~/.local/share/claude-no-sleep/uninstall.sh
```

It removes everything in the table above except the settings backup, and turns sleep back on. It asks for your password once, to remove the sudoers rule.
If a step fails, it says so, keeps itself, and you run it again after you fix the error.

## Limits

- `~/.claude/sessions` is not a documented Claude Code interface, so an update can change it. An unknown status counts as idle and shows one macOS notification.
- A Mac with the lid closed and sleep off stays on. Do not put it in a bag while a session works.
- Sessions that already ran before the install get the prompt hook only after a restart; the 10 s poll covers them at once.

## Tests

```bash
./test.sh
```

The tests use fakes for `sudo`, `pmset`, `ps`, `visudo` and `launchctl`, and change nothing outside temporary folders.
