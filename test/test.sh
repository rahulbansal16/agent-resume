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
chmod +x "$AGENT_RESUME_HOME/shims/claude" "$AGENT_RESUME_HOME/pre-restore-hook.sh"

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

echo ""
echo "passed=$pass failed=$fail"
[ "$fail" = "0" ]
