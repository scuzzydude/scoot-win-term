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
