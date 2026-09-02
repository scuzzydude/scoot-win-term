# scoot-win-term — Windows Terminal + Cross-Server Agent Manifest

## Context

Brandon manages many Claude Code agent sessions across multiple Linux AI
servers using MTPuTTY on Windows to hold the terminal tabs. He wants to
replace MTPuTTY with Windows Terminal, driven from a new tool in the
`scoot` family (`scoot`, `scoot-chat`, `scoot-pmp` are precedent — each its
own git repo under `github.com/scuzzydude`). Two needs converged into one
project:

1. Stop hand-maintaining PuTTY/MTPuTTY sessions — convert them into
   Windows Terminal profiles/color schemes automatically.
2. Get a live, cross-server "manifest" of running agent sessions, so a
   central Windows Terminal can list and jump into any agent on any AI
   server — without hardcoding GNU `screen` into that logic, since
   Brandon wants the background-terminal mechanism swappable later.

Today, `sn` (a `.bashrc` function on the `steve` server) is a one-line
`screen -S <name>` wrapper with no prompting, no Claude launch, and no
manifest. This plan extends it into the write side of the manifest, and
builds the Windows-side reader/launcher as `scoot-win-term`.

## Repo

New repo: `scoot-win-term` (under `scuzzydude`, matching the family
convention), single repo, two trees:
- `src/` — PowerShell, runs on Windows
- `linux-agent/` — the `sn` implementation + manifest writer, deployed to
  each AI server

One repo because the manifest JSONL schema is a contract shared by both
sides — keeping them in one repo means a schema change is one commit, one
version, not two repos drifting out of sync.

## Architecture

```
Linux AI server (steve, v1 only)              Windows client
┌───────────────────────────────┐             ┌───────────────────────────┐
│ .bashrc: sn()  ──calls──►      │             │ scoot-win-term/src/       │
│  ~/.scoot-term/                │   SSH:      │  Convert-PuttyToTerminal  │
│    lib/backend.sh               │   cat        │  Get-AgentManifest.ps1   │
│    lib/backends/screen.sh       │   manifest + │  Start-AgentSession.ps1  │
│    manifest.jsonl  ◄─writes──   │   screen -ls │  servers.conf            │
│  .screenrc (+termcapinfo)       │             └───────────────────────────┘
└───────────────────────────────┘
```

The manifest file is the only coupling point. Each manifest line carries
its own `attach_cmd`, so the Windows side never hardcodes `screen -r` —
it just runs whatever command string the Linux side wrote.

## Session-backend abstraction (`linux-agent/lib/`)

Four functions, dispatched via `$SCOOT_TERM_BACKEND` (default `screen`),
so a future `backends/tmux.sh` can be dropped in without touching
manifest or tab-naming code:

```
backend_start <name>      -> prints backend_id, creates detached session
backend_list              -> "<id>\t<name>\t<alive:0|1>" per line
backend_attach_cmd <id>   -> prints the reattach command string
backend_is_alive <id>     -> exit 0/1
```

`lib/backends/screen.sh`:
- `screen_start`: `screen -dmS "$name"`, then
  `screen -S "$name" -X stuff "claude$(printf '\r')"` to type `claude`
  into the fresh session — reuses the existing `claude()` wrapper exactly
  as the user gets it today (same `--name`, same
  `--dangerously-skip-permissions`; **this plan keeps that flag exactly
  as-is per Brandon's explicit choice** — `sn` just makes it easier to
  spin up more sessions that already ran this way).
- `screen_list`: parses `screen -ls` (`\t12345.name\t(Detached)`) into
  the TSV contract.
- `screen_attach_cmd`: `screen -r <id>`.
- `screen_is_alive`: checks `<id>` appears in current `screen -ls`.

## Manifest (`linux-agent/lib/manifest.sh`, `~/.scoot-term/manifest.jsonl`)

JSONL, one object per line (chosen over a single JSON array so concurrent
`sn` calls only need a `flock`-guarded append, not read-modify-write):

```json
{"schema_version":1,"name":"scoot-chat","backend":"screen","backend_id":"12345.scoot-chat","attach_cmd":"screen -r 12345.scoot-chat","host":"steve","cwd":"/home/steve/scoot-chat","purpose":"fix SSE reconnect bug","status":"waiting on CI","color":null,"start_time":"2026-09-01T14:32:07-04:00","pid":12345}
```

`status` is set once at `sn` time as `null`, then updated in place by
`st` (see below) — unlike `purpose`, it's meant to be pushed again as
work progresses.

`color` is reserved (`null` in v1) for the `{key,label,color}` legend
convention already used in Postgres (`series_legend`/`project_legend`) if
per-project color-tagging is added later.

**Staleness**: filtered at read time, not tracked at write time. Every
read (local prune, and the Windows-side aggregator) cross-checks each
line's `backend_id` against a fresh `backend_list`/`screen -ls` call.
`sn` also prunes-and-rewrites `manifest.jsonl` on every invocation, so no
cron job is needed to keep it clean.

## `sn` (new implementation, `linux-agent/shell-integration.bash`)

`.bashrc` is reduced to sourcing this file. Behavior:
1. Prompt for session name, default = cwd basename, Enter-to-accept
   (matches today's speed for the common case).
2. Prompt for an optional one-line purpose (Enter to skip).
3. If the name matches a currently-alive session, offer to attach to it
   instead of creating a duplicate (screen's own behavior would try to
   attach anyway on a raw name clash — this makes that explicit instead
   of surprising).
4. `backend_start`, write+prune the manifest line, attach.

**`sl` / `st` (management interface)** — `sl` lists every live session
(name, purpose, `status`, and real terminal-output activity via
`backend_last_activity`, not just attach time), most recently active
first, with a numbered shortcut to attach. `st [message]` sets the
*current* session's `status` (found via `$STY`, screen's own
session-id env var) so `sl` — and the Windows-side aggregator — show
fresher progress than the one-line `purpose` captured at `sn` time.

`.screenrc` gets one addition alongside the existing `hardstatus` line:
```
termcapinfo xterm*|screen*|tmux* 'hs:ts=\E]0;:fs=\007:ds=\E]0;\007'
```
This is the standard fix for screen to re-emit an OSC title sequence to
the *outer* terminal (needed for "clearly identify the new tab" to work
once viewed through Windows Terminal over SSH) — verify empirically (see
Verification); if it doesn't work, M2b's `wt.exe --title` at launch time
still identifies the tab, just not dynamically after the fact.

## Windows side (`scoot-win-term/src/`)

**M1 — PuTTY/MTPuTTY → Windows Terminal converter**
- `modules/PuttyRegistry.psm1` — reads `HKCU:\Software\SimonTatham\PuTTY\Sessions\*`
  (`HostName`, `PortNumber`, `Colour0`..`Colour21`).
- `modules/ColorScheme.psm1` — maps PuTTY's colour slots to a Terminal
  `schemes` entry; deterministic v5-UUID per profile/scheme so re-runs
  are idempotent (no duplicate GUIDs).
- `modules/MtPuttyStore.psm1` — MTPuTTY's own grouping/color store.
  **Format unconfirmed** — write this defensively: try known candidate
  paths, warn and fall back to flat PuTTY-only import if not found. Do
  not block M1a on this.
- `modules/FragmentWriter.psm1` — writes
  `%LocalAppData%\Microsoft\Windows Terminal\Fragments\scoot-win-term\*.json`
  using the `"updates":"{guid}"` patch mechanism, UTF-8 (not PowerShell's
  UTF-16LE default) — never touches the user's real `settings.json`.
- `Convert-PuttyToTerminal.ps1` — entry point, supports `-WhatIf`.

Ship as **M1a** (flat PuTTY sessions only) first; extend to **M1b**
(MTPuTTY grouping/colors) once the real format is confirmed against
Brandon's actual Windows machine.

**M2b — cross-server manifest reader + launcher**
- `servers.conf` — pipe-delimited `hostname|label|color`, reusing the
  `sync_registry.conf` convention. v1: `steve|Steve AI Server|#3A96DD`
  only — **other AI servers still need to be named before they can be
  added**; the format supports it trivially once Brandon provides
  hostnames.
- `Get-AgentManifest.ps1` — one SSH round-trip per server
  (`cat ~/.scoot-term/manifest.jsonl; echo ---LIVE---; screen -ls`),
  parses JSONL, drops stale entries against the live block.
- `Start-AgentSession.ps1` — presents the aggregated list (sorted by
  last activity, showing `status` alongside `purpose`), on selection:
  `wt.exe new-tab --title "<name> @ <host>" --tabColor "<color>" -- ssh <host> -t "<attach_cmd>"`.

## Verification

1. **M1**: `-WhatIf` run, eyeball against real PuTTY/MTPuTTY; real run,
   `ConvertFrom-Json` round-trip; run twice, diff fragment file (must be
   identical — proves idempotency); open Terminal's profile dropdown
   *without restarting* to test hot-reload; launch a converted profile;
   diff `settings.json` hash before/after (must be untouched).
2. **Backend contract**: source `lib/backends/screen.sh` standalone,
   call all four functions against a throwaway session, clean up with
   `screen -X -S test1 quit`.
3. **`sn` + manifest**: run `sn` twice with different names while
   tailing `manifest.jsonl`; confirm well-formed lines and correct
   `--name`/skip-permissions inheritance via `screen -ls` + attach; kill
   one session and re-run `sn` to confirm pruning.
4. **Title passthrough**: from a real SSH session with an
   xterm-256color-class client, switch screen windows and watch whether
   the *outer* terminal's tab title changes (not just screen's hardstatus
   line) — record pass/fail either way.
5. **M2b**: confirm SSH is non-interactive (key-based, no password
   prompt hang); kill a session mid-test and confirm stale filtering
   works over SSH; run `Start-AgentSession.ps1`, confirm the new tab
   opens attached to the right session with correct title/color.
6. **`sl`/`st`**: run `sl`, `st "testing"` from inside a session, `sl`
   again from another shell — confirm status shows and last-touch is
   recent; leave it idle and re-run `sl` — confirm last-touch grows
   (proves real activity, not attach time, is being tracked).

## Known gaps carried forward (not blocking, not guessed)

- MTPuTTY's exact storage format — confirm against the real machine
  during M1b.
- Additional AI servers beyond `steve` — need hostnames from Brandon
  before `servers.conf` can list them; architecture already supports it.
- `purpose` itself still can't be edited after `sn` time — `st`'s
  `status` field is the fast-follow for that, not a rename of `purpose`.
- No automated rollout of `.bashrc`/`.screenrc`/`linux-agent/` to future
  servers yet — a small installer script is a natural fast-follow once a
  second server is targeted.
