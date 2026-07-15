#!/bin/sh
# agent-resume bootstrap installer.
#
#   curl -fsSL https://raw.githubusercontent.com/rahulbansal16/agent-resume/main/install.sh | sh
#
# or, from a checkout:  sh install.sh [install flags...]
#
# Set AGENT_RESUME_REPO to override the source repo.
set -eu

REPO="${AGENT_RESUME_REPO:-https://github.com/rahulbansal16/agent-resume}"
SRC="${AGENT_RESUME_SRC:-$HOME/.local/share/agent-resume-src}"

# Running from inside a checkout? Use it directly.
here="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$here/bin/agent-resume" ]; then
  exec sh "$here/bin/agent-resume" install "$@"
fi

# Otherwise fetch the source.
if command -v git >/dev/null 2>&1; then
  if [ -d "$SRC/.git" ]; then
    git -C "$SRC" pull --ff-only --quiet || true
  else
    mkdir -p "$(dirname "$SRC")"
    git clone --depth 1 "$REPO" "$SRC"
  fi
else
  echo "agent-resume: git required to bootstrap from $REPO" >&2
  exit 1
fi

exec sh "$SRC/bin/agent-resume" install "$@"
