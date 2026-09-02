# scoot-win-term

Part of the `scoot` family (`scoot`, `scoot-chat`, `scoot-pmp`). Replaces
MTPuTTY with Windows Terminal as the central place to manage Claude Code
agent sessions across multiple Linux AI servers.

Two halves, one contract — a JSONL manifest file each server writes and
the Windows side reads over SSH:

```
linux-agent/   sn shell function + manifest writer (deployed per server)
src/           PowerShell: PuTTY/MTPuTTY -> Windows Terminal converter,
               cross-server manifest reader + tab launcher
```

See `PLAN.md` for the full design (architecture, manifest schema,
session-backend abstraction, milestones, verification steps), and
`README_2nd_PC.md` for setting this up on an additional Windows machine.

## Linux agent

Deployed to each AI server. Adds a `sn` shell function that prompts for
a session name + purpose, starts a background session (GNU `screen` by
default, pluggable via `$SCOOT_TERM_BACKEND`), launches Claude Code
inside it, and records the session in `~/.scoot-term/manifest.jsonl`.

Install (per server):

```bash
git clone https://github.com/scuzzydude/scoot-win-term.git ~/scoot-win-term
echo 'source "$HOME/scoot-win-term/linux-agent/shell-integration.bash"' >> ~/.bashrc
```

Requires an existing `claude()` wrapper in `.bashrc` that launches Claude
Code the way you want (`sn` calls it, doesn't replace it).

Two more commands for managing sessions once you've got several running:

- `sl` — lists every live session on this server (purpose, status, and
  how long since it last actually produced output), most recent first,
  with a number to attach to.
- `st [message]` — from inside a running session, sets a one-line status
  shown by `sl` (and by `Start-AgentSession.ps1` on Windows) — use it to
  push a progress update without re-attaching from elsewhere.

## Windows side

PowerShell, run from `cmd.exe` or PowerShell.

**M1a — import PuTTY sessions into Windows Terminal:**

```batch
powershell -File src\Convert-PuttyToTerminal.ps1 -WhatIf
powershell -File src\Convert-PuttyToTerminal.ps1
```

Writes a fragment JSON under
`%LocalAppData%\Microsoft\Windows Terminal\Fragments\scoot-win-term\` —
never touches your real `settings.json`. Re-running it updates profiles
in place (deterministic GUIDs) instead of duplicating them.

MTPuTTY's own grouping/colors aren't imported yet (M1b, format still
unconfirmed) — only raw PuTTY registry sessions for now.

**M2b — list and open live agents across your servers:**

Edit `src\servers.conf` (pipe-delimited `hostname|label|color`) to list
your AI servers, then:

```batch
powershell -File src\Start-AgentSession.ps1
```

Lists every live session across all servers (via SSH — key-based auth
must already work, no password prompts) and opens your pick in a new
Windows Terminal tab, attached.
