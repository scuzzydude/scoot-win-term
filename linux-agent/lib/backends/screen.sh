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
