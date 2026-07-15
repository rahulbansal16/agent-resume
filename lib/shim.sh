#!/bin/sh
# agent-resume shim.
#
# One copy of this file is installed per agent under
# $AGENT_RESUME_HOME/shims/<agent> (e.g. .../shims/claude). It discovers which
# agent it is from its own name, loads that adapter, then decides:
#
#   fresh interactive run   -> launch with a baked --session-id <uuid> so
#                              tmux-resurrect can restore the exact conversation.
#   existing --session-id   -> flip to --resume <uuid> (covers restore replays
#                              AND kills the "Session ID already in use" error).
#   everything else         -> exec the real binary unchanged.
#
# It is a strict pass-through on any doubt: it must never break the real CLI.

self="$(basename "$0")"
HOME_DIR="${AGENT_RESUME_HOME:-$HOME/.config/agent-resume}"
adapter="$HOME_DIR/adapters/$self.conf"

# Resolve the REAL binary: first match on PATH that is NOT our shim dir.
resolve_real() {
  _shimdir="$HOME_DIR/shims"
  _OIFS=$IFS; IFS=:
  for _d in $PATH; do
    case "$_d" in "$_shimdir"|"") continue ;; esac
    if [ -x "$_d/$self" ]; then IFS=$_OIFS; printf '%s\n' "$_d/$self"; return 0; fi
  done
  IFS=$_OIFS; return 1
}
REAL="$(resolve_real)" || { echo "agent-resume: cannot find real '$self' on PATH" >&2; exit 127; }

# No adapter -> behave like the real binary.
[ -f "$adapter" ] || exec "$REAL" "$@"
# shellcheck disable=SC1090
. "$adapter"

contains() { _n="$1"; shift; for _a in "$@"; do [ "$_a" = "$_n" ] && return 0; done; return 1; }
has_any()  { _list="$1"; shift; for _f in $_list; do contains "$_f" "$@" && return 0; done; return 1; }

session_exists() {
  [ -n "$AGENT_SESSION_DIR" ] || return 1
  [ -d "$AGENT_SESSION_DIR" ] || return 1
  find "$AGENT_SESSION_DIR" -name "$1.$AGENT_SESSION_EXT" -print 2>/dev/null | head -n1 | grep -q .
}

# Extract the value following AGENT_NEWID_FLAG, if present.
newid_value() {
  [ -n "$AGENT_NEWID_FLAG" ] || return 1
  _prev=""
  for _a in "$@"; do
    [ "$_prev" = "$AGENT_NEWID_FLAG" ] && { printf '%s\n' "$_a"; return 0; }
    _prev="$_a"
  done
  return 1
}

# --- decision ---------------------------------------------------------------

# 1) A launch-time id was supplied (e.g. resurrect replaying our saved command).
#    If that session already exists, flip to a resume so it doesn't error.
if sid="$(newid_value "$@")"; then
  if session_exists "$sid"; then
    # Rebuild argv, flipping the newid flag that immediately precedes $sid to
    # the resume flag. Rotates each arg front-to-back to preserve order and
    # any embedded spaces (no word-splitting, no sed on the whole line).
    n=$#; i=0; flipped=0
    while [ "$i" -lt "$n" ]; do
      cur="$1"; shift; i=$((i + 1))
      if [ "$flipped" = "0" ] && [ "$cur" = "$AGENT_NEWID_FLAG" ] && [ "${1:-}" = "$sid" ]; then
        cur="$AGENT_RESUME_FLAG"; flipped=1
      fi
      set -- "$@" "$cur"
    done
  fi
  exec "$REAL" "$@"
fi

# 2) User already asked to resume/continue, or it's non-interactive -> pass through.
if has_any "$AGENT_CONTINUE_FLAGS" "$@" || has_any "$AGENT_PRINT_FLAGS" "$@" || [ ! -t 1 ]; then
  exec "$REAL" "$@"
fi

# 3) Fresh interactive run: bake an id if this agent supports it.
if [ "${AGENT_SUPPORTS_NEWID:-0}" = "1" ] && [ -n "$AGENT_NEWID_FLAG" ]; then
  if command -v uuidgen >/dev/null 2>&1; then
    newid="$(uuidgen | tr 'A-Z' 'a-z')"
  else
    newid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null)"
  fi
  if [ -n "$newid" ]; then
    # record this launch so `agent-resume` can resume it later:
    # epoch <tab> agent <tab> cwd <tab> session-id
    { printf '%s\t%s\t%s\t%s\n' "$(date +%s 2>/dev/null || echo 0)" "$self" "$PWD" "$newid" \
        >> "$HOME_DIR/sessions.tsv"; } 2>/dev/null || true
    exec "$REAL" "$AGENT_NEWID_FLAG" "$newid" "$@"
  fi
fi

exec "$REAL" "$@"
