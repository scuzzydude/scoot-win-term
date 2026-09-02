#!/usr/bin/env bash
# Session-backend dispatcher. Every backend under lib/backends/*.sh must
# define: <name>_start, <name>_list, <name>_attach_cmd, <name>_is_alive,
# <name>_last_activity. Selected via $SCOOT_TERM_BACKEND (default: screen).

SCOOT_TERM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCOOT_TERM_BACKEND="${SCOOT_TERM_BACKEND:-screen}"

# shellcheck source=./backends/screen.sh
source "$SCOOT_TERM_LIB_DIR/backends/${SCOOT_TERM_BACKEND}.sh"

backend_start() { "${SCOOT_TERM_BACKEND}_start" "$@"; }
backend_list() { "${SCOOT_TERM_BACKEND}_list" "$@"; }
backend_attach_cmd() { "${SCOOT_TERM_BACKEND}_attach_cmd" "$@"; }
backend_is_alive() { "${SCOOT_TERM_BACKEND}_is_alive" "$@"; }
backend_last_activity() { "${SCOOT_TERM_BACKEND}_last_activity" "$@"; }
