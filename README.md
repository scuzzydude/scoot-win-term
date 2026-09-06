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

- `sls` — lists every live `screen` session on this server straight from
  `screen -ls` (no manifest involved), with a number to attach to;
  automatically does `-d -r` instead of a plain `-r` for a session
  that's attached elsewhere, so taking it over never just errors out. If
  nothing's live — or you pick the trailing "session history" entry —
  it falls back to the last 10 directories Claude Code actually ran in
  (from Claude Code's own session store) and starts `claude --continue`
  in whichever one you pick.
- `st [message]` — from inside a running session, sets a one-line status
  shown by `Start-AgentSession.ps1` on Windows — use it to push a
  progress update without re-attaching from elsewhere.

### Event log (`scoot-rim`)

`manifest.jsonl` answers *"what can I attach to right now"* — it's a snapshot,
and an ended session is simply dropped from it. That's the wrong shape for
*"what was running before the host rebooted, and what was left unfinished"*.

So alongside it, `~/.scoot-rim/events.jsonl` records **transitions** rather than
state: `session_start`, `agent_bound`, `session_exit`, plus optional
`claim`/`release`/`handoff`/`defer`/`resume`/`escalate`/`decide`. Current state is
a fold over the log, so restart recovery needs no separate mechanism — anything
with a `session_start` and no `session_exit` was live at shutdown.

```bash
linux-agent/scoot-rim live          # the recovery set: started, not exited
linux-agent/scoot-rim restore-plan  # what a reboot recovery WOULD run (prints only)
linux-agent/scoot-rim reconcile     # close sessions the backend says are gone
linux-agent/scoot-rim open          # defer/escalate with no resume/decide
linux-agent/scoot-rim tail 20
```

Two things worth knowing:

- **`reconcile` is required, not optional.** `sn` returns when you *detach*, not
  when the session ends, and a killed session never logs its own exit. Without a
  periodic `reconcile` (cron/systemd timer), dead sessions look live forever.
- **`agent_bound` is what makes restore meaningful.** Resuming by *directory*
  (`claude --continue`) picks the most recent conversation there, which is wrong
  once a directory has hosted several. `sn` snapshots the existing conversation
  ids before launch and a detached watcher records the *new* one, so
  `restore-plan` can emit `claude --resume <id>`. Where no id was captured it
  falls back to `--continue` and labels that line APPROXIMATE.

Design rationale lives outside this repo (it's the first step of a planned
`scoot-rim-agentd` service); this layer deliberately needs no daemon.

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
