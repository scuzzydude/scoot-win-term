#!/usr/bin/env bash
# Generates ../src/Set-ClaudeEnv.local.ps1 from this server's own
# ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN (read from ~/.bashrc), so a
# Windows box can point Claude Code at the same endpoint. The output file
# contains a real credential and is gitignored -- re-run this any time the
# token rotates, never hand-edit or commit the generated file.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$here/src/Set-ClaudeEnv.local.ps1"

base_url="$(grep -oP "(?<=export ANTHROPIC_BASE_URL=).*" ~/.bashrc | head -1 | sed -E "s/^['\"]//; s/['\"]\$//")"
auth_token="$(grep -oP "(?<=export ANTHROPIC_AUTH_TOKEN=).*" ~/.bashrc | head -1 | sed -E "s/^['\"]//; s/['\"]\$//")"

if [ -z "$base_url" ] || [ -z "$auth_token" ]; then
  echo "gen-windows-claude-env: couldn't find ANTHROPIC_BASE_URL/ANTHROPIC_AUTH_TOKEN in ~/.bashrc" >&2
  exit 1
fi

cat > "$out" <<PS1
# LOCAL ONLY -- contains a real API credential for $(hostname -s)'s Claude
# Code endpoint. Generated $(date -Is) by gen-windows-claude-env.sh.
# Never commit this file, never paste its contents anywhere. Re-run the
# generator on steve any time the token rotates.
[Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', '${base_url}', 'User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', '${auth_token}', 'User')
Write-Host "Set ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN for this Windows user. Open a new terminal for 'claude' to pick them up." -ForegroundColor Green
PS1

chmod 600 "$out"
echo "Wrote $out (contents not printed -- open it directly if you need to check it)."
