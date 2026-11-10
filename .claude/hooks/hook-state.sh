# shellcheck shell=bash
# Sourced by pr-state.sh, which writes a session's note file, and check-agent-spawn.sh, which reads it.
hook_state_dir() { printf '%s\n' "${MITOS_HOOK_STATE:-${TMPDIR:-/tmp}/mitos-hook-state}"; }
session_id_ok() { [[ $1 =~ ^[A-Za-z0-9_-]{1,100}$ ]]; }
session_note_path() { printf '%s/%s.note\n' "$(hook_state_dir)" "$1"; }
