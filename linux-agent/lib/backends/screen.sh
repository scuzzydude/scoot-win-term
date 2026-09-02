#!/usr/bin/env bash
# GNU screen implementation of the session-backend contract.

screen_start() {
  local name="$1"
  command screen -dmS "$name"
  # Type "claude" into the fresh session as if the user had, so it goes
  # through the existing claude() wrapper in .bashrc exactly as today
  # (same --name, same --dangerously-skip-permissions).
  command screen -S "$name" -X stuff "claude$(printf '\r')"
  screen_id_for_name "$name"
}

# Prints the "pid.name" token screen uses to address a session.
screen_id_for_name() {
  local name="$1"
  command screen -ls 2>/dev/null | awk -v n="$name" '
    match($1, /^([0-9]+)\.(.*)$/, m) && m[2] == n { print $1 }
  '
}

screen_list() {
  command screen -ls 2>/dev/null | awk '
    match($1, /^([0-9]+)\.(.*)$/, m) {
      alive = ($0 ~ /\(Dead/) ? 0 : 1
      print $1 "\t" m[2] "\t" alive
    }
  '
}

screen_attach_cmd() {
  local id="$1"
  echo "screen -r ${id}"
}

screen_is_alive() {
  local id="$1"
  command screen -ls 2>/dev/null | awk -v id="$id" '$1 == id { found=1 } END { exit found ? 0 : 1 }'
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
