#!/usr/bin/env bash
# JSONL manifest of live agent sessions on this server.
# One append per sn invocation; staleness is filtered at read time by
# cross-checking each line's backend_id against backend_list(), never
# tracked as an "ended" event.

SCOOT_TERM_HOME="${SCOOT_TERM_HOME:-$HOME/.scoot-term}"
SCOOT_TERM_MANIFEST="${SCOOT_TERM_MANIFEST:-$SCOOT_TERM_HOME/manifest.jsonl}"
SCOOT_TERM_LOCK="${SCOOT_TERM_MANIFEST}.lock"

manifest_init() {
  mkdir -p "$SCOOT_TERM_HOME"
  touch "$SCOOT_TERM_MANIFEST"
}

# json_escape <string> -> string safe to embed in a JSON double-quoted value
_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# manifest_append <name> <backend> <backend_id> <attach_cmd> <cwd> <purpose> <pid>
manifest_append() {
  local name="$1" backend="$2" backend_id="$3" attach_cmd="$4" cwd="$5" purpose="$6" pid="$7"
  local host start_time line
  host="$(hostname -s 2>/dev/null || hostname)"
  start_time="$(date -Is)"

  line=$(printf '{"schema_version":1,"name":"%s","backend":"%s","backend_id":"%s","attach_cmd":"%s","host":"%s","cwd":"%s","purpose":"%s","color":null,"start_time":"%s","pid":%s}' \
    "$(_json_escape "$name")" \
    "$(_json_escape "$backend")" \
    "$(_json_escape "$backend_id")" \
    "$(_json_escape "$attach_cmd")" \
    "$(_json_escape "$host")" \
    "$(_json_escape "$cwd")" \
    "$(_json_escape "$purpose")" \
    "$start_time" \
    "${pid:-null}")

  manifest_init
  (
    flock -x 200
    printf '%s\n' "$line" >> "$SCOOT_TERM_MANIFEST"
  ) 200>"$SCOOT_TERM_LOCK"
}

# manifest_prune: rewrite the manifest keeping only entries whose
# backend_id is still alive per the current backend.
manifest_prune() {
  manifest_init
  local tmp
  tmp="$(mktemp)"
  (
    flock -x 200
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local id
      id=$(printf '%s' "$line" | grep -o '"backend_id":"[^"]*"' | head -1 | cut -d'"' -f4)
      if [ -n "$id" ] && backend_is_alive "$id"; then
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$SCOOT_TERM_MANIFEST"
    mv "$tmp" "$SCOOT_TERM_MANIFEST"
  ) 200>"$SCOOT_TERM_LOCK"
}
