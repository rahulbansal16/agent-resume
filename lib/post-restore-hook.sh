#!/bin/sh
# agent-resume post-restore hook for tmux-resurrect.
#
# Wired via:  set -g @resurrect-hook-post-restore-all '.../post-restore-hook.sh'
#
# Why this exists: tmux-resurrect restores each pane's directory and a shell,
# but it does NOT relaunch Claude Code. Claude renames its own process to its
# version number (e.g. "2.1.210"), so resurrect's name-based program matching
# never fires for it. So we relaunch the agent ourselves: for every saved pane
# that was running an agent session, type the resume command into the matching
# restored pane (which resurrect left sitting at a shell, in the right dir).
#
# The saved command was already rewritten by the pre-restore hook from
# `--session-id <uuid>` to `--resume <uuid>` for sessions that still exist, so
# this resumes the exact conversation instead of opening a picker.

LAST=""
for f in "$HOME/.local/share/tmux/resurrect/last" "$HOME/.tmux/resurrect/last"; do
  [ -e "$f" ] && { LAST="$f"; break; }
done
[ -n "$LAST" ] || exit 0
target="$(readlink "$LAST" 2>/dev/null || printf '%s' "$LAST")"
case "$target" in /*) : ;; *) target="$(dirname "$LAST")/$target" ;; esac
[ -f "$target" ] || exit 0

# Let resurrect's per-pane `cat contents; exec shell` reach the shell prompt
# before we type into it.
sleep 1

tab="$(printf '\t')"
# Pane line fields: 1=pane 2=session 3=window_index ... 6=pane_index ...
# last field = ":<full_command>". Emit only agent resume/session panes.
awk -F"$tab" '
  $1=="pane" {
    cmd=$NF; sub(/^:/,"",cmd)
    if (cmd ~ /\/?claude[ ].*(--resume|--session-id)/ || cmd ~ /\/?codex[ ](resume|--session-id)/)
      print $2 "\t" $3 "\t" $6 "\t" cmd
  }
' "$target" | while IFS="$tab" read -r sess win pane cmd; do
  [ -n "$cmd" ] || continue
  tmux has-session -t "$sess" 2>/dev/null || continue
  tmux send-keys -t "$sess:$win.$pane" "$cmd" Enter 2>/dev/null || true
done
exit 0
