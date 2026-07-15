#!/bin/sh
# Self-contained tests for the shim + pre-restore hook. No real claude, no tmux.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
export AGENT_RESUME_HOME="$WORK/home/.config/agent-resume"
mkdir -p "$AGENT_RESUME_HOME/shims" "$AGENT_RESUME_HOME/adapters" \
         "$HOME/.claude/projects/proj" "$WORK/realbin"

cp "$ROOT/adapters/claude.conf" "$AGENT_RESUME_HOME/adapters/"
cp "$ROOT/lib/shim.sh" "$AGENT_RESUME_HOME/shims/claude"
cp "$ROOT/lib/pre-restore-hook.sh" "$AGENT_RESUME_HOME/pre-restore-hook.sh"
cp "$ROOT/lib/post-restore-hook.sh" "$AGENT_RESUME_HOME/post-restore-hook.sh"
chmod +x "$AGENT_RESUME_HOME/shims/claude" "$AGENT_RESUME_HOME/pre-restore-hook.sh" \
         "$AGENT_RESUME_HOME/post-restore-hook.sh"

# fake real claude: echoes the args it was called with
cat > "$WORK/realbin/claude" <<'EOF'
#!/bin/sh
echo "REAL:$*"
EOF
chmod +x "$WORK/realbin/claude"

export PATH="$AGENT_RESUME_HOME/shims:$WORK/realbin:/usr/bin:/bin"

pass=0; fail=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %s\n     expected: [%s]\n     actual:   [%s]\n' "$1" "$2" "$3"; fi
}

EXIST="11111111-1111-1111-1111-111111111111"
MISS="22222222-2222-2222-2222-222222222222"
: > "$HOME/.claude/projects/proj/$EXIST.jsonl"

echo "shim:"
# 1. existing --session-id -> flipped to --resume
out="$(claude --session-id "$EXIST" 2>&1)"
check "existing session-id flips to resume" "REAL:--resume $EXIST" "$out"

# 2. missing --session-id -> passthrough unchanged
out="$(claude --session-id "$MISS" 2>&1)"
check "missing session-id passes through" "REAL:--session-id $MISS" "$out"

# 3. explicit --resume passes through
out="$(claude --resume abc 2>&1)"
check "explicit resume passes through" "REAL:--resume abc" "$out"

# 4. non-interactive fresh run (stdout piped) -> no id baked
out="$(claude 2>&1)"
check "non-interactive fresh passes through" "REAL:" "$out"

# 5. print mode passes through
out="$(claude -p hi 2>&1)"
check "print mode passes through" "REAL:-p hi" "$out"

echo "pre-restore hook:"
mkdir -p "$HOME/.local/share/tmux/resurrect"
LAST="$HOME/.local/share/tmux/resurrect/session-1.txt"
{
  printf 'pane\tmain\t1\tzsh\t1\t\t0\t\t:%s/proj\t1\tclaude\t999\t:claude --session-id %s\n' "$HOME" "$EXIST"
  printf 'pane\tmain\t2\tzsh\t0\t\t1\t\t:%s/proj\t0\tclaude\t998\t:claude --session-id %s\n' "$HOME" "$MISS"
} > "$LAST"
ln -sf "$LAST" "$HOME/.local/share/tmux/resurrect/last"

sh "$AGENT_RESUME_HOME/pre-restore-hook.sh"

if grep -q -- "--resume $EXIST" "$LAST"; then pass=$((pass+1)); echo "  ok   existing id rewritten to --resume"
else fail=$((fail+1)); echo "  FAIL existing id not rewritten"; fi
if grep -q -- "--session-id $MISS" "$LAST"; then pass=$((pass+1)); echo "  ok   missing id left as --session-id"
else fail=$((fail+1)); echo "  FAIL missing id was wrongly rewritten"; fi

echo "post-restore hook:"
# realistic resurrect pane format: session=$2 window=$3 pane_index=$6 cmd=$NF
PL="$HOME/.local/share/tmux/resurrect/postrestore.txt"
{
  printf 'pane\twork\t0\t1\t:*\t0\tClaude\t:%s/proj\t1\t2.1.210\t:/bin/claude --resume %s\n' "$HOME" "$EXIST"
  printf 'pane\twork\t0\t1\t:*\t1\tzsh\t:%s/proj\t0\tzsh\t:/bin/zsh\n' "$HOME"
} > "$PL"
ln -sf "$PL" "$HOME/.local/share/tmux/resurrect/last"

# fake tmux: answer has-session, log send-keys
TMUXLOG="$WORK/tmux.log"; : > "$TMUXLOG"
mkdir -p "$WORK/faketmux"
cat > "$WORK/faketmux/tmux" <<EOF
#!/bin/sh
case "\$1" in
  has-session) exit 0 ;;
  send-keys) shift; echo "\$*" >> "$TMUXLOG" ;;
esac
EOF
chmod +x "$WORK/faketmux/tmux"

PATH="$WORK/faketmux:$PATH" sh "$AGENT_RESUME_HOME/post-restore-hook.sh"

if grep -q -- "-t work:0.0 /bin/claude --resume $EXIST Enter" "$TMUXLOG"; then
  pass=$((pass+1)); echo "  ok   relaunches claude --resume in the exact pane"
else
  fail=$((fail+1)); echo "  FAIL wrong/no send-keys:"; cat "$TMUXLOG"
fi
if [ "$(grep -c . "$TMUXLOG" 2>/dev/null || echo 0)" = "1" ]; then
  pass=$((pass+1)); echo "  ok   ignored the non-agent pane"
else
  fail=$((fail+1)); echo "  FAIL should have sent exactly one command"
fi

echo "resume command:"
mkdir -p "$HOME/proj" "$HOME/proj2"
LED="$AGENT_RESUME_HOME/sessions.tsv"
{
  printf '100\tclaude\t%s/proj\told-0000-0000-0000-000000000000\n' "$HOME"
  printf '200\tclaude\t%s/proj\t%s\n' "$HOME" "$EXIST"          # newest, file exists
  printf '150\tclaude\t%s/proj2\t%s\n' "$HOME" "$MISS"          # only entry, file missing
} > "$LED"

# 1. bare resume picks the newest recorded session whose file exists
out="$(cd "$HOME/proj" && sh "$ROOT/bin/agent-resume" 2>&1)"
case "$out" in
  *"REAL:--resume $EXIST"*) pass=$((pass+1)); echo "  ok   bare resume picks newest recorded session" ;;
  *) fail=$((fail+1)); echo "  FAIL bare resume: $out" ;;
esac

# 2. when the recorded session file is gone, fall back to --continue
out="$(cd "$HOME/proj2" && sh "$ROOT/bin/agent-resume" 2>&1)"
case "$out" in
  *"REAL:--continue"*) pass=$((pass+1)); echo "  ok   missing session falls back to --continue" ;;
  *) fail=$((fail+1)); echo "  FAIL resume fallback: $out" ;;
esac

# 3. a directory with NO recorded session + agent name -> native --continue,
#    NOT another directory's session
mkdir -p "$HOME/nowhere"
out="$(cd "$HOME/nowhere" && sh "$ROOT/bin/agent-resume" claude 2>&1)"
case "$out" in
  *"REAL:--continue"*) pass=$((pass+1)); echo "  ok   unknown dir uses native --continue (not another dir)" ;;
  *"$EXIST"*) fail=$((fail+1)); echo "  FAIL leaked another directory's session: $out" ;;
  *) fail=$((fail+1)); echo "  FAIL unknown dir: $out" ;;
esac

# 4. bare resume in a dir with nothing recorded -> error, resumes nothing
if (cd "$HOME/nowhere" && sh "$ROOT/bin/agent-resume" >/dev/null 2>&1); then
  fail=$((fail+1)); echo "  FAIL bare resume should error when nothing is recorded"
else
  pass=$((pass+1)); echo "  ok   bare resume errors when nothing recorded here"
fi

echo ""
echo "passed=$pass failed=$fail"
[ "$fail" = "0" ]
