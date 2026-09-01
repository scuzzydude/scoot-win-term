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
session-backend abstraction, milestones, verification steps).

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

## Windows side

PowerShell, run from `cmd.exe` or PowerShell. See `src/` — still under
construction; scripts and usage will be documented here as they land.
