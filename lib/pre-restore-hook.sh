#!/bin/sh
# agent-resume pre-restore hook for tmux-resurrect.
#
# Wired via:  set -g @resurrect-hook-pre-restore-all '.../pre-restore-hook.sh'
#
# tmux-resurrect saves each pane's launch command verbatim. For agents we baked
# with `--session-id <uuid>`, replaying that command would error ("already in
# use"). This hook rewrites the SAVED state before restore: for every
# `--session-id <uuid>` whose session actually exists, flip it to
# `--resume <uuid>`, so resurrect brings the exact conversation back regardless
# of how it spawns the program (PATH shim, absolute path, or node wrapper).
#
# Adapter-driven: reads every $AGENT_RESUME_HOME/adapters/*.conf so it works
# for claude and any agent you add.

HOME_DIR="${AGENT_RESUME_HOME:-$HOME/.config/agent-resume}"

# Locate resurrect's "last" pointer and resolve it to the real file.
LAST=""
for f in "$HOME/.local/share/tmux/resurrect/last" "$HOME/.tmux/resurrect/last"; do
  [ -e "$f" ] && { LAST="$f"; break; }
done
[ -n "$LAST" ] || exit 0

target="$(readlink "$LAST" 2>/dev/null || printf '%s' "$LAST")"
case "$target" in
  /*) : ;;
  *)  target="$(dirname "$LAST")/$target" ;;
esac
[ -f "$target" ] || exit 0

tmp="$target.aaff.$$"
cp "$target" "$tmp" || exit 0
changed=0

for adapter in "$HOME_DIR"/adapters/*.conf; do
  [ -f "$adapter" ] || continue
  # subshell so adapters don't leak vars into each other
  ( # shellcheck disable=SC1090
    . "$adapter"
    [ "${AGENT_SUPPORTS_NEWID:-0}" = "1" ] || exit 0
    [ -n "$AGENT_NEWID_FLAG" ] || exit 0
    ids="$(grep -oE -- "$AGENT_NEWID_FLAG $AGENT_ID_REGEX" "$tmp" 2>/dev/null \
            | awk '{print $2}' | sort -u)"
    for id in $ids; do
      session_name="${AGENT_SESSION_FILE_PREFIX:-}$id.$AGENT_SESSION_EXT"
      if [ -d "$AGENT_SESSION_DIR" ] && \
         find "$AGENT_SESSION_DIR" -name "$session_name" -print 2>/dev/null | head -n1 | grep -q .; then
        sed "s/$AGENT_NEWID_FLAG $id/$AGENT_RESUME_FLAG $id/g" "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
        echo "flip"  # signal change to parent via stdout
      fi
    done
  ) | grep -q flip && changed=1
done

if [ "$changed" = "1" ]; then
  mv "$tmp" "$target"
else
  rm -f "$tmp"
fi
exit 0
