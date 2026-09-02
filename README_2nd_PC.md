# Setting up scoot-win-term on a second Windows PC

Everything machine-specific lives outside the repo — SSH config, the
Windows Terminal fragment, and the Claude credential file are all
per-machine. So a second PC is a clone plus four bits of local setup,
not a code change.

Work through the sections in order; each ends with something you can
verify before moving on.

---

## 1. Prerequisites

```powershell
winget install --id Git.Git
winget install --id GitHub.cli
winget install --id Microsoft.WindowsTerminal
```

Windows' built-in OpenSSH client provides `ssh.exe`, which the generated
Terminal profiles call directly. Confirm it exists:

```powershell
ssh -V
```

If that fails: **Settings → System → Optional features → Add a feature
→ OpenSSH Client**.

---

## 2. GitHub auth

The `scoot` repos use **HTTPS remotes with `gh` as git's credential
helper** — no SSH keys for GitHub. Don't bother with
`gh auth login --web`: the device-code flow times out
(`context deadline exceeded`) before you can finish a passkey/Windows
Hello prompt. Use a token instead.

1. Create a classic PAT at <https://github.com/settings/tokens> →
   *Generate new token (classic)*.
2. Scopes: **`repo`** *and* **`read:org`**. `gh` validates `read:org` at
   login even though pushing only needs `repo` — omit it and login fails
   with `missing required scope 'read:org'`.
3. Log in and wire up git:

```powershell
gh auth login --hostname github.com --git-protocol https --with-token
# paste the token, press Enter, then Ctrl+Z and Enter

git config --global credential.helper "!'C:/Program Files/GitHub CLI/gh.exe' auth git-credential"
```

That helper path is absolute on purpose. A freshly installed `gh` isn't
on `PATH` in already-open shells, and if Git Credential Manager is left
in the helper chain it will pop a blocking dialog and hang your push.
Setting the value (rather than adding) replaces the chain.

**Verify:**

```powershell
gh auth status          # should show: Logged in to github.com account scuzzydude
```

---

## 3. Clone

```powershell
git clone https://github.com/scuzzydude/scoot-win-term.git C:\source\scoot-win-term
cd C:\source\scoot-win-term
```

**Verify:** `git push --dry-run` completes without prompting for
credentials.

---

## 4. SSH config — the one genuinely different part

`src/modules/SshConfigResolver.psm1` prefers a matching `Host` alias in
`~/.ssh/config` over a literal `user@host`, so connection differences
between machines belong here, not in the repo.

Create or edit `C:\Users\<you>\.ssh\config`:

```sshconfig
# steve — reached the same way as on the first PC
Host steve
    HostName <steve's hostname or IP>
    User <your steve username>
    IdentityFile ~/.ssh/id_ed25519

# bigmo — direct, NOT through the tunnel/jump host on this PC
Host bigmo
    HostName <bigmo's hostname or IP>
    User <your bigmo username>
    IdentityFile ~/.ssh/id_ed25519
```

On the first PC, `bigmo` is reached *through* `steve` as a jump host
(that's what `ProxyMethod 6` handling in `Convert-PuttyToTerminal.ps1`
is for). On this PC it isn't, hence the plain entry above. If `bigmo`
turns out to still need the hop from here, add `ProxyJump steve` to its
block.

These must be **key-based and non-interactive** — the manifest scripts
run `ssh -o BatchMode=yes` and will simply report the host as
unreachable if anything prompts for a password.

**Verify both, and insist on the `BatchMode` form:**

```powershell
ssh -o BatchMode=yes steve echo ok
ssh -o BatchMode=yes bigmo echo ok
```

Both must print `ok`. If you need to generate and install a key:

```powershell
ssh-keygen -t ed25519
ssh-copy-id steve      # or append the .pub to ~/.ssh/authorized_keys manually
```

---

## 5. Claude Code credentials (not in the repo)

`src/Set-ClaudeEnv.local.ps1` points Claude Code at the internal
gateway. It holds a **real API token**, so it's gitignored and never
committed — it will *not* appear after cloning. Regenerate it from
steve:

```bash
# on steve
cd ~/scoot-win-term && git pull
./linux-agent/gen-windows-claude-env.sh
```

That writes `src/Set-ClaudeEnv.local.ps1` on **steve**, reading the
values from steve's own `~/.bashrc`. Copy that one file to this PC
(`scp`, or paste it into an editor — it's three lines), drop it in
`src\`, then run it once:

```powershell
.\src\Set-ClaudeEnv.local.ps1
```

It sets `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` as **User**
environment variables, so open a *new* terminal afterward for `claude`
to see them. Re-run the generator whenever the token rotates.

**Verify:** in a new terminal, `$env:ANTHROPIC_BASE_URL` is non-empty.

---

## 6. Import PuTTY sessions (optional)

Only if this PC has saved PuTTY sessions worth converting. The output is
a machine-local generated fragment, so run it per PC.

```powershell
powershell -File src\Convert-PuttyToTerminal.ps1 -WhatIf   # inspect first
powershell -File src\Convert-PuttyToTerminal.ps1
```

Writes to
`%LocalAppData%\Microsoft\Windows Terminal\Fragments\scoot-win-term\` —
it never touches your real `settings.json`. Deterministic GUIDs mean
re-running updates profiles in place instead of duplicating them.

Two things to expect:

- Custom logo icons key off the **PuTTY session names** `bigmo` and
  `steve_user` (see `$iconOverrides` in the script). If this PC's
  sessions are named differently they get the default icon — either
  rename the sessions or add your names to that hashtable.
- MTPuTTY grouping/colors still aren't imported (M1b, format
  unconfirmed). Raw PuTTY registry sessions only.

**Verify:** open Windows Terminal's profile dropdown — the profiles
should appear without restarting it.

---

## 7. Register the servers

`src/servers.conf` is pipe-delimited `hostname|label|color`. It ships
with `steve` only, so add `bigmo`:

```
steve|Steve AI Server|#3A96DD
bigmo|Big Mo AI Server|#CA5010
```

The hostname must match the `Host` alias from step 4. Pick any hex color
you like — it becomes the Windows Terminal tab color.

---

## 8. End-to-end check

Make sure the Linux side is current first — the `sl`/`st` commands and
the activity reporting the Windows side reads are recent additions:

```bash
# on steve, and on bigmo
cd ~/scoot-win-term && git pull
```

Then start a throwaway session on steve (`sn`, accept the default name,
give it any purpose), and from this PC:

```powershell
powershell -File src\Get-AgentManifest.ps1     # raw objects
powershell -File src\Start-AgentSession.ps1    # interactive picker
```

You should see the session listed with its purpose, a relative
last-activity time, and — if you ran `st "testing"` inside it — its
status. Picking it opens a new Terminal tab already attached, titled
`<name> @ <host>` in the server's color.

Anything missing, in order of likelihood:

| Symptom | Cause |
|---|---|
| `No response from '<host>'` | `ssh -o BatchMode=yes <host> echo ok` fails — step 4 |
| Host missing from the list entirely | not in `servers.conf` — step 7 |
| Sessions listed but last-activity shows `-` | that server hasn't pulled the `sl`/`st` commit, or the clone isn't at `~/scoot-win-term` (the path the Windows side sources `backend.sh` from) |
| Session missing but you know it's running | it was started before that server pulled, so its manifest line predates the change — start a fresh one with `sn` |

---

## What is *not* shared between PCs

Worth knowing so you don't go looking for it in git:

- `~/.ssh/config` — per machine, by design (step 4)
- `src/Set-ClaudeEnv.local.ps1` — gitignored, holds a live credential (step 5)
- The Windows Terminal fragment under `%LocalAppData%` — generated (step 6)
- `manifest.jsonl` on each server — gitignored runtime data

`src/servers.conf` *is* committed, so once you add `bigmo` and push, the
other PC picks it up on its next pull.
