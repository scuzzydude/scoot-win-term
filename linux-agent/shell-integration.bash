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

# sl: lists live sessions (name, purpose, status, last real output
# activity), most recently active first, with a shortcut to attach.
sl() {
  manifest_prune

  local -a rows=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local id
    id=$(_json_field "$line" backend_id)
    [ -z "$id" ] && continue
    backend_is_alive "$id" || continue

    local name purpose status ts
    name=$(_json_field "$line" name)
    purpose=$(_json_field "$line" purpose)
    status=$(_json_field "$line" status)
    ts=$(backend_last_activity "$id")
    [ -z "$ts" ] && ts=0

    rows+=("$ts"$'\t'"$id"$'\t'"$name"$'\t'"$purpose"$'\t'"$status")
  done < "$SCOOT_TERM_MANIFEST"

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "No live sessions."
    return
  fi

  local sorted
  sorted=$(printf '%s\n' "${rows[@]}" | sort -t $'\t' -k1,1nr)

  local -a ids=()
  local i=0
  echo ""
  while IFS=$'\t' read -r ts id name purpose status; do
    local ago suffix=""
    ago=$(_relative_time "$ts")
    [ -n "$purpose" ] && suffix="$suffix - $purpose"
    [ -n "$status" ] && suffix="$suffix [$status]"
    printf '[%d] %s (%s ago)%s\n' "$i" "$name" "$ago" "$suffix"
    ids[$i]="$id"
    i=$((i + 1))
  done <<< "$sorted"
  echo ""

  local choice
  read -r -p "Attach to # (Enter to skip): " choice
  [ -z "$choice" ] && return
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -lt "${#ids[@]}" ]; then
    eval "$(backend_attach_cmd "${ids[$choice]}")"
  else
    echo "sl: invalid choice" >&2
  fi
}

# st [message]: sets the current session's status (shown by `sl` and by
# the Windows-side aggregator). Must be run from inside a running
# session -- uses $STY (screen's own session-id env var) to find it.
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
