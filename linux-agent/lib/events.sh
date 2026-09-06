#!/usr/bin/env bash
# Append-only event log of agent-session state transitions.
#
# Why this exists alongside manifest.jsonl rather than replacing it:
# manifest.jsonl is a snapshot of *live* sessions -- staleness is filtered at
# read time by cross-checking backend_id against backend_list(), and an ended
# session is simply dropped (see lib/manifest.sh header). That is the right
# shape for "what can I attach to right now", and the wrong shape for "what
# was running before the host rebooted, and what was left unfinished".
#
# This log records transitions instead of state. Current state is a fold over
# the log (events_replay), so restart recovery needs no separate mechanism:
# anything with a session_start and no session_exit was live at shutdown.
#
# Design: ri/steve/arch/RIM_agentd_design_v0.1.md (in the steveai repo).
# Extracted into scoot-rim-agentd once the shape is proven; kept here for now
# because sn/sls are the only writers and nothing needs a daemon yet.
#
# Dependency-free (no jq) to match lib/manifest.sh.

SCOOT_RIM_HOME="${SCOOT_RIM_HOME:-$HOME/.scoot-rim}"
SCOOT_RIM_EVENTS="${SCOOT_RIM_EVENTS:-$SCOOT_RIM_HOME/events.jsonl}"
SCOOT_RIM_LOCK="${SCOOT_RIM_EVENTS}.lock"
SCOOT_RIM_SCHEMA=1

# Where the agent runtime keeps per-project conversation logs. Overridable
# so the log layer can be tested without touching the real one.
SCOOT_RIM_AGENT_PROJECTS="${SCOOT_RIM_AGENT_PROJECTS:-$HOME/.claude/projects}"

events_init() {
  mkdir -p "$SCOOT_RIM_HOME"
  touch "$SCOOT_RIM_EVENTS"
}

# _rim_json_escape <string> -> safe inside a JSON double-quoted value.
# Same implementation as manifest.sh's _json_escape, duplicated rather than
# cross-sourced so this file stays independently sourceable.
_rim_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# _rim_json_field <json_line> <field> -> unquoted value, empty for null/missing.
_rim_json_field() {
  local json="$1" field="$2" val
  val=$(printf '%s' "$json" | grep -o "\"$field\":\"[^\"]*\"" | head -1 | cut -d'"' -f4)
  if [ -n "$val" ]; then printf '%s' "$val"; return; fi
  val=$(printf '%s' "$json" | grep -o "\"$field\":[^,}]*" | head -1 | cut -d: -f2-)
  [ "$val" = "null" ] && val=""
  printf '%s' "$val"
}

# event_append <event_type> [key value]...
# Values are always emitted as JSON strings; pass "" to omit a key.
event_append() {
  local event="$1"; shift
  local ts host line
  ts="$(date -Is)"
  host="$(hostname -s 2>/dev/null || hostname)"

  line=$(printf '{"schema_version":%s,"ts":"%s","event":"%s","host":"%s"' \
    "$SCOOT_RIM_SCHEMA" "$ts" "$(_rim_json_escape "$event")" "$(_rim_json_escape "$host")")

  while [ "$#" -ge 2 ]; do
    local k="$1" v="$2"; shift 2
    [ -z "$v" ] && continue
    line="$line$(printf ',"%s":"%s"' "$(_rim_json_escape "$k")" "$(_rim_json_escape "$v")")"
  done
  line="$line}"

  events_init
  (
    flock -x 200
    printf '%s\n' "$line" >> "$SCOOT_RIM_EVENTS"
  ) 200>"$SCOOT_RIM_LOCK"
}

# ---------------------------------------------------------------------------
# agent_session_id resolution
#
# The agent's own session id is what makes restart resume the work rather than
# reopen an empty shell in the right directory. It cannot be known before
# launch -- the agent mints it -- and sn blocks on attach immediately after
# launching, so it cannot be polled inline either. Hence: snapshot the project
# dir before launch, then a detached watcher emits agent_bound when a new
# conversation file appears.
#
# Resolving by "newest file in the cwd's project dir" alone is wrong when a
# directory has hosted several sessions over time (several here have): it would
# bind to a previous conversation. The pre-launch snapshot is what makes it the
# *new* one.
# ---------------------------------------------------------------------------

# _rim_project_dir <cwd> -> the agent's project dir for that cwd.
# Encoding verified against real directories: both '/' and '_' become '-'.
_rim_project_dir() {
  local cwd="$1" enc
  enc="$(printf '%s' "$cwd" | sed 's/[/_]/-/g')"
  printf '%s/%s' "$SCOOT_RIM_AGENT_PROJECTS" "$enc"
}

# _rim_session_ids <cwd> -> conversation ids currently on disk for that cwd.
_rim_session_ids() {
  local dir; dir="$(_rim_project_dir "$1")"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name '*.jsonl' -printf '%f\n' 2>/dev/null | sed 's/\.jsonl$//'
}

# events_snapshot_sessions <cwd> -> space-separated ids, for passing to the binder.
events_snapshot_sessions() {
  _rim_session_ids "$1" | tr '\n' ' '
}

# events_bind_agent_session <backend_id> <cwd> <pre_snapshot> [timeout_s]
# Detached watcher: emits agent_bound as soon as an id appears that was not in
# pre_snapshot. Emits agent_bind_failed on timeout so the gap is visible in the
# log rather than silently absent.
events_bind_agent_session() {
  local backend_id="$1" cwd="$2" pre="$3" timeout="${4:-90}"
  (
    local waited=0 id
    while [ "$waited" -lt "$timeout" ]; do
      while IFS= read -r id; do
        [ -z "$id" ] && continue
        case " $pre " in
          *" $id "*) continue ;;
        esac
        event_append agent_bound \
          backend_id "$backend_id" \
          agent_session_id "$id" \
          cwd "$cwd"
        return 0
      done < <(_rim_session_ids "$cwd")
      sleep 2
      waited=$((waited + 2))
    done
    event_append agent_bind_failed \
      backend_id "$backend_id" \
      cwd "$cwd" \
      reason "no new agent session file within ${timeout}s"
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Completeness: registration and adoption
#
# The log is only complete if every live session appears in it. Sessions
# launched by sn do; anything started another way (plain `claude` in a hand-made
# screen, a session predating this log) does not -- and a registry that misses
# sessions cannot be gated on, because the gate fails OPEN for exactly the
# sessions it does not know about.
#
# Two ways in, and they differ in what they can know:
#
#   register  -- run from INSIDE a session. Exact: $STY is the screen id and
#                $CLAUDE_CODE_SESSION_ID is the agent's own session id.
#   adopt     -- run from OUTSIDE. Best effort: the screen id and (via
#                /proc/<pid>/cwd) the launch directory, but NOT the agent
#                session id.
#
# Why adopt cannot get the agent id, having tried: the agent does not keep its
# conversation file open (so /proc/<pid>/fd is empty of it), does not carry
# CLAUDE_CODE_SESSION_ID in its own environ (it exports it to children), and
# encoding cwd -> project dir breaks whenever a directory was renamed after the
# session started -- which has happened here. So adopted sessions are recorded
# honestly as unbound, and `doctor` reports them as such.
# ---------------------------------------------------------------------------

# events_is_live <backend_id> -> 0 if the log currently considers it live.
events_is_live() {
  local want="$1" bid rest
  while IFS=$'\t' read -r bid rest; do
    [ "$bid" = "$want" ] && return 0
  done < <(events_replay)
  return 1
}

# events_has_agent_binding <backend_id> -> 0 if an agent id is known for it.
events_has_agent_binding() {
  local want="$1" bid name cwd agent
  while IFS=$'\t' read -r bid name cwd agent; do
    if [ "$bid" = "$want" ] && [ -n "$agent" ] && [ "$agent" != "-" ]; then
      return 0
    fi
  done < <(events_replay)
  return 1
}

# _rim_pid_cwd <pid> -> launch directory of that process, empty if unreadable.
# Strips the " (deleted)" suffix the kernel appends when the directory has since
# been removed or replaced. Keeping it would produce a path that cannot be cd'd
# to; stripping it lets restore-plan's own existence check SKIP the session
# properly instead of emitting a broken command. Two live sessions here are in
# that state, so this is not hypothetical.
_rim_pid_cwd() {
  local pid="$1" cwd
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)" || return 0
  printf '%s' "${cwd% (deleted)}"
}

# events_register_self: called from inside a session. Idempotent -- adds only
# what is missing, so it is safe to run on every shell startup.
# Returns 0 if it wrote anything, 1 if there was nothing to do.
events_register_self() {
  local bid="${STY:-}" agent="${CLAUDE_CODE_SESSION_ID:-}" name cwd wrote=1

  if [ -z "$bid" ]; then
    echo "register: no \$STY -- not inside a session backend" >&2
    return 2
  fi
  name="${bid#*.}"

  # The screen process's cwd is the launch directory, which is more canonical
  # than the caller's $PWD (a shell inside the session may have cd'd away).
  cwd="$(_rim_pid_cwd "${bid%%.*}")"
  [ -z "$cwd" ] && cwd="$PWD"

  if ! events_is_live "$bid"; then
    event_append session_start \
      name "$name" \
      backend "${SCOOT_TERM_BACKEND:-screen}" \
      backend_id "$bid" \
      cwd "$cwd" \
      pid "${bid%%.*}" \
      origin "self-registered"
    wrote=0
  fi

  if [ -n "$agent" ] && ! events_has_agent_binding "$bid"; then
    event_append agent_bound \
      backend_id "$bid" \
      agent_session_id "$agent" \
      cwd "$cwd" \
      origin "self-registered"
    wrote=0
  fi

  return "$wrote"
}

# events_adopt: record live backend sessions the log doesn't know about.
# Prints one line per adoption. Cannot supply an agent id (see header).
events_adopt() {
  local adopted=0 bid name alive attached cwd
  while IFS=$'\t' read -r bid name alive attached; do
    [ "$alive" = "1" ] || continue
    events_is_live "$bid" && continue
    cwd="$(_rim_pid_cwd "${bid%%.*}")"
    event_append session_start \
      name "$name" \
      backend "${SCOOT_TERM_BACKEND:-screen}" \
      backend_id "$bid" \
      cwd "$cwd" \
      pid "${bid%%.*}" \
      origin "adopted" \
      note "discovered live; agent_session_id unknown -- run 'scoot-rim register' inside it"
    printf 'adopted\t%s\t%s\t%s\n' "$bid" "$name" "${cwd:-<cwd unknown>}"
    adopted=$((adopted + 1))
  done < <(backend_list)
  return 0
}

# events_doctor: is this registry trustworthy enough to gate on?
# Reports three classes and exits non-zero if any are outstanding.
events_doctor() {
  local missing=0 stale=0 unbound=0
  local bid name alive attached cwd agent

  while IFS=$'\t' read -r bid name alive attached; do
    [ "$alive" = "1" ] || continue
    if ! events_is_live "$bid"; then
      printf 'MISSING   %s (%s) -- live but not in log; run: scoot-rim adopt\n' "$bid" "$name"
      missing=$((missing + 1))
    fi
  done < <(backend_list)

  while IFS=$'\t' read -r bid name cwd agent; do
    [ -z "$bid" ] && continue
    if ! backend_is_alive "$bid" 2>/dev/null; then
      printf 'STALE     %s (%s) -- in log but backend gone; run: scoot-rim reconcile\n' "$bid" "$name"
      stale=$((stale + 1))
    elif [ "$agent" = "-" ] || [ -z "$agent" ]; then
      printf 'UNBOUND   %s (%s) -- no agent_session_id; restore would be approximate.\n' "$bid" "$name"
      printf '                    fix: run "scoot-rim register" inside that session\n'
      unbound=$((unbound + 1))
    fi
  done < <(events_replay)

  printf '\n%d missing, %d stale, %d unbound\n' "$missing" "$stale" "$unbound"
  if [ "$missing" -eq 0 ] && [ "$stale" -eq 0 ] && [ "$unbound" -eq 0 ]; then
    echo "registry complete — safe to gate on"
    return 0
  fi
  echo "registry INCOMPLETE — a gate consulting it would fail open for the above"
  return 1
}

# ---------------------------------------------------------------------------
# Fold and reconcile
# ---------------------------------------------------------------------------

# events_replay: one line per session that started and has not exited.
# Output: <backend_id>\t<name>\t<cwd>\t<agent_session_id or "-">
# This is the recovery set -- what was live, not everything ever started.
events_replay() {
  events_init
  awk -F'"' '
    # crude field pull: keys are unique per line and values are strings
    function field(line, key,   n, parts) {
      n = split(line, parts, "\"")
      for (i = 1; i <= n; i++) if (parts[i] == key) return parts[i + 2]
      return ""
    }
    {
      ev  = field($0, "event")
      bid = field($0, "backend_id")
      if (bid == "") next
      if (ev == "session_start") {
        started[bid] = 1
        name[bid] = field($0, "name")
        cwd[bid]  = field($0, "cwd")
      } else if (ev == "session_exit") {
        delete started[bid]
      } else if (ev == "agent_bound") {
        agent[bid] = field($0, "agent_session_id")
      }
    }
    END {
      for (b in started)
        printf "%s\t%s\t%s\t%s\n", b, name[b], cwd[b], (agent[b] ? agent[b] : "-")
    }
  ' "$SCOOT_RIM_EVENTS" | sort -t"$(printf '\t')" -k2,2
}

# events_reconcile: emit session_exit for anything the fold thinks is live but
# the backend says is gone. Required, not optional: sn returns when the user
# DETACHES, not when the session ends, and a session killed outright never gets
# to log its own exit. Without this pass, dead sessions look live forever.
events_reconcile() {
  local closed=0 bid name cwd agent
  while IFS=$'\t' read -r bid name cwd agent; do
    [ -z "$bid" ] && continue
    if ! backend_is_alive "$bid" 2>/dev/null; then
      event_append session_exit \
        backend_id "$bid" \
        name "$name" \
        reason "reconciled: backend reports not alive"
      closed=$((closed + 1))
    fi
  done < <(events_replay)
  [ "$closed" -gt 0 ] && event_append reconcile closed "$closed"
  printf '%s\n' "$closed"
}
