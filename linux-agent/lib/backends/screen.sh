#!/usr/bin/env bash
# GNU screen implementation of the session-backend contract.

screen_start() {
  local name="$1"
  local cmd="${2:-claude}"
  command screen -dmS "$name"
  # Type the command into the fresh session as if the user had, so it
  # goes through the claude alias in .bashrc (--dangerously-skip-permissions).
  # Defaults to "claude"; callers resuming a prior conversation pass
  # "claude --continue" instead. --name is appended here so the terminal
  # tab title is the session name rather than Claude Code's auto-generated
  # conversation summary.
  case "$cmd" in
    claude|claude\ *) cmd="$cmd --name $(printf '%q' "$name")" ;;
  esac
  command screen -S "$name" -X stuff "$cmd$(printf '\r')"
  screen_id_for_name "$name"
}

# Prints the "pid.name" token screen uses to address a session.
# screen -ls separates fields with tabs (line starts with a leading tab,
# so $1 is empty and the "pid.name" token is $2) — using the default
# whitespace field splitter here would truncate any session name that
# contains a space at the first space.
screen_id_for_name() {
  local name="$1"
  command screen -ls 2>/dev/null | awk -F'\t' -v n="$name" '
    match($2, /^([0-9]+)\.(.*)$/, m) && m[2] == n { print $2 }
  '
}

screen_list() {
  command screen -ls 2>/dev/null | awk -F'\t' '
    match($2, /^([0-9]+)\.(.*)$/, m) {
      alive = ($0 ~ /\(Dead/) ? 0 : 1
      attached = ($0 ~ /\(Attached/) ? 1 : 0
      print $2 "\t" m[2] "\t" alive "\t" attached
    }
  '
}

screen_attach_cmd() {
  local id="$1"
  echo "screen -r ${id}"
}

# screen_cwd <id> -> real working directory of the foreground `claude`
# process in that window. The pid in "pid.name" is the window's shell, not
# claude itself (screen -> shell -> claude), so walk down the process tree
# looking for the `claude` binary rather than assuming a fixed depth. Empty
# if the process is gone or the tree doesn't look like that.
#
# Forks `ps` per hop, which is fine for a single lookup but far too slow
# across a whole session listing (~150ms x N hops x N sessions) -- use
# screen_cwd_bulk for that instead.
screen_cwd() {
  local id="$1"
  local pid="${id%%.*}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  local hops=0
  while [ "$hops" -lt 4 ] && [ "$(command ps -o comm= -p "$pid" 2>/dev/null)" != "claude" ]; do
    local next
    next=$(command ps --ppid "$pid" -o pid= 2>/dev/null | awk 'NR==1{print $1}')
    [ -z "$next" ] && return 0
    pid="$next"
    hops=$((hops + 1))
  done
  local cwd
  cwd=$(command readlink -f "/proc/$pid/cwd" 2>/dev/null) || return 0
  # A directory that was deleted/replaced after the process started still
  # resolves here, just with this suffix appended by the kernel.
  printf '%s\n' "${cwd% (deleted)}"
}

# screen_cwd_bulk: reads "pid.name" ids on stdin, one per line; prints
# "<id>\t<cwd>" for each, in input order. Same descend-to-claude logic as
# screen_cwd, but against a single `ps -eo pid,ppid,comm` snapshot instead
# of forking ps per hop per session -- the whole point of this variant.
screen_cwd_bulk() {
  local -A ppid_of=() comm_of=() first_child=()
  local pid ppid comm
  while read -r pid ppid comm; do
    ppid_of["$pid"]="$ppid"
    comm_of["$pid"]="$comm"
    [ -n "${first_child[$ppid]:-}" ] || first_child["$ppid"]="$pid"
  done < <(command ps -eo pid=,ppid=,comm= 2>/dev/null)

  local id
  while IFS= read -r id; do
    pid="${id%%.*}"
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
      printf '%s\t\n' "$id"
      continue
    fi
    local hops=0
    while [ "$hops" -lt 4 ] && [ "${comm_of[$pid]:-}" != "claude" ]; do
      local next="${first_child[$pid]:-}"
      [ -z "$next" ] && { pid=""; break; }
      pid="$next"
      hops=$((hops + 1))
    done
    local cwd=""
    [ -n "$pid" ] && cwd=$(command readlink -f "/proc/$pid/cwd" 2>/dev/null)
    printf '%s\t%s\n' "$id" "${cwd% (deleted)}"
  done
}

# Same tab-splitting requirement as screen_id_for_name/screen_list above: with
# the default whitespace splitter, $1 is the leading-tab-trimmed "pid.name"
# truncated at its first space, so any session whose name contains a space
# ("1032932.Bridge SIM") was reported dead while alive. That made
# manifest_prune drop it and sls treat it as gone.
screen_is_alive() {
  local id="$1"
  command screen -ls 2>/dev/null | awk -F'\t' -v id="$id" '$2 == id { found=1 } END { exit found ? 0 : 1 }'
}

# screen_last_activity <id> -> epoch seconds of last output on that
# window's pty, empty if it can't be determined. The pty's mtime updates
# whenever data is written to it, so this reflects real activity, not
# just when it was last attached.
screen_last_activity() {
  local id="$1"
  local pid="${id%%.*}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  local tty
  tty=$(command ps -o tty= --ppid "$pid" 2>/dev/null | awk '$1 != "?" { print $1; exit }')
  [ -z "$tty" ] && return 0
  command stat -c %Y "/dev/$tty" 2>/dev/null
}
