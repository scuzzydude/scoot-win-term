#!/usr/bin/env bash
# scoot-win-term Linux agent: the real `sn` implementation.
# Sourced from .bashrc. Requires the existing claude() wrapper to already
# be defined (unchanged) elsewhere in .bashrc.

SCOOT_TERM_AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCOOT_TERM_AGENT_DIR/lib/backend.sh"
source "$SCOOT_TERM_AGENT_DIR/lib/manifest.sh"

sn() {
  local default_name
  default_name="$(basename "$PWD")"

  local name
  read -r -e -p "Session name [$default_name]: " -i "$default_name" name
  name="${name:-$default_name}"

  # Explicit clash handling instead of letting screen's own ambiguous
  # attach-on-clash behavior surprise the user.
  local existing_id
  existing_id="$(backend_list | awk -F'\t' -v n="$name" '$2==n && $3==1 {print $1; exit}')"
  if [ -n "$existing_id" ]; then
    echo "Session '$name' is already running (${existing_id}) — attaching instead."
    eval "$(backend_attach_cmd "$existing_id")"
    return
  fi

  local purpose
  read -r -p "Purpose (optional, Enter to skip): " purpose

  local backend_id
  backend_id="$(backend_start "$name")"
  if [ -z "$backend_id" ]; then
    echo "sn: failed to start backend session '$name'" >&2
    return 1
  fi

  local attach_cmd pid
  attach_cmd="$(backend_attach_cmd "$backend_id")"
  pid="${backend_id%%.*}"
  [[ "$pid" =~ ^[0-9]+$ ]] || pid=""

  manifest_append "$name" "$SCOOT_TERM_BACKEND" "$backend_id" "$attach_cmd" "$PWD" "$purpose" "$pid"
  manifest_prune

  eval "$attach_cmd"
}

# _relative_time <epoch> -> "Ns"/"Nm"/"Nh"/"Nd" ago, or "?" if unknown.
_relative_time() {
  local ts="$1"
  if [ -z "$ts" ] || [ "$ts" = "0" ]; then
    echo "?"
    return
  fi
  local now diff
  now=$(date +%s)
  diff=$(( now - ts ))
  if [ "$diff" -lt 60 ]; then echo "${diff}s"
  elif [ "$diff" -lt 3600 ]; then echo "$(( diff / 60 ))m"
  elif [ "$diff" -lt 86400 ]; then echo "$(( diff / 3600 ))h"
  else echo "$(( diff / 86400 ))d"
  fi
}

# _sls_recent_claude_dirs [limit]: prints "<mtime>\t<dir>" for the most
# recently touched Claude Code project directories, most recent first,
# deduped, capped at `limit` (default 10). Reads Claude Code's own
# session store directly (~/.claude/projects/<encoded-dir>/<id>.jsonl),
# not scoot-win-term's manifest -- each session file's first "cwd" field
# is its real, unencoded working directory.
_sls_recent_claude_dirs() {
  local limit="${1:-10}"
  local count=0
  local mtime path cwd
  while IFS=$'\t' read -r mtime path; do
    [ "$count" -ge "$limit" ] && break
    cwd=$(grep -m1 -o '"cwd":"[^"]*"' "$path" 2>/dev/null | cut -d'"' -f4)
    [ -z "$cwd" ] && continue
    case " ${_sls_seen_dirs:-} " in *" $cwd "*) continue ;; esac
    _sls_seen_dirs="${_sls_seen_dirs:-} $cwd"
    printf '%s\t%s\n' "$mtime" "$cwd"
    count=$((count + 1))
  done < <(find "$HOME/.claude/projects" -maxdepth 2 -name '*.jsonl' -printf '%T@\t%p\n' 2>/dev/null | sort -t $'\t' -k1,1nr)
  unset _sls_seen_dirs
}

# _sls_resume_from_history: numbered list of recent Claude Code project
# directories; picking one starts a fresh screen session there running
# `claude --continue`. Deliberately not written to manifest.jsonl -- this
# path exists precisely to work outside that system.
_sls_resume_from_history() {
  local -a dirs=() times=()
  local i=0
  while IFS=$'\t' read -r mtime dir; do
    dirs[$i]="$dir"
    times[$i]="$mtime"
    i=$((i + 1))
  done < <(_sls_recent_claude_dirs 10)

  if [ "$i" -eq 0 ]; then
    echo "No Claude Code session history found."
    return
  fi

  echo ""
  local j=0
  while [ "$j" -lt "$i" ]; do
    printf '[%d] %s (%s ago)\n' "$j" "${dirs[$j]}" "$(_relative_time "${times[$j]%.*}")"
    j=$((j + 1))
  done
  echo ""

  local choice
  read -r -p "Resume # with claude --continue (Enter to skip): " choice
  [ -z "$choice" ] && return
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -ge "$i" ]; then
    echo "sls: invalid choice" >&2
    return
  fi

  local dir="${dirs[$choice]}"
  if [ ! -d "$dir" ]; then
    echo "sls: directory no longer exists: $dir" >&2
    return 1
  fi

  local name
  name="$(basename "$dir")"

  # Same clash handling as sn: a live session with this name wins.
  local existing_id
  existing_id="$(backend_list | awk -F'\t' -v n="$name" '$2==n && $3==1 {print $1; exit}')"
  if [ -n "$existing_id" ]; then
    echo "Session '$name' is already running (${existing_id}) — attaching instead."
    eval "$(backend_attach_cmd "$existing_id")"
    return
  fi

  cd "$dir" || return 1

  local backend_id
  backend_id="$(backend_start "$name" "claude --continue")"
  if [ -z "$backend_id" ]; then
    echo "sls: failed to start backend session '$name'" >&2
    return 1
  fi

  eval "$(backend_attach_cmd "$backend_id")"
}

# sls: lists live screen sessions straight from `screen -ls` (no
# manifest involved), most recently listed first, and attaches on pick
# -- using `-d -r` instead of plain `-r` when the row is already
# Attached elsewhere, so taking it over never just errors out. An extra
# trailing entry always drops into the Claude Code session-history
# fallback (see _sls_resume_from_history), and that fallback runs
# automatically when there's nothing live to list.
sls() {
  local -a ids=() names=() attacheds=()
  local i=0
  while IFS=$'\t' read -r id name alive attached; do
    [ "$alive" = "1" ] || continue
    ids[$i]="$id"
    names[$i]="$name"
    attacheds[$i]="$attached"
    i=$((i + 1))
  done < <(backend_list)

  if [ "$i" -eq 0 ]; then
    _sls_resume_from_history
    return
  fi

  echo ""
  local j=0
  while [ "$j" -lt "$i" ]; do
    local label="Detached"
    [ "${attacheds[$j]}" = "1" ] && label="Attached"
    printf '[%d] %s (%s)\n' "$j" "${names[$j]}" "$label"
    j=$((j + 1))
  done
  printf '[%d] Claude Code session history...\n' "$i"
  echo ""

  local choice
  read -r -p "Attach to # (Enter to skip): " choice
  [ -z "$choice" ] && return
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -gt "$i" ]; then
    echo "sls: invalid choice" >&2
    return
  fi
  if [ "$choice" -eq "$i" ]; then
    _sls_resume_from_history
    return
  fi

  if [ "${attacheds[$choice]}" = "1" ]; then
    command screen -d -r "${ids[$choice]}"
  else
    eval "$(backend_attach_cmd "${ids[$choice]}")"
  fi
}

# st [message]: sets the current session's status (shown by the
# Windows-side aggregator). Must be run from inside a running session --
# uses $STY (screen's own session-id env var) to find it.
st() {
  if [ -z "$STY" ]; then
    echo "st: not running inside a scoot-term session" >&2
    return 1
  fi
  local msg="$*"
  if [ -z "$msg" ]; then
    read -r -p "Status: " msg
  fi
  manifest_set_status "$STY" "$msg"
}
