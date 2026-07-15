# agent-resume

[![ci](https://github.com/rahulbansal16/agent-resume/actions/workflows/ci.yml/badge.svg)](https://github.com/rahulbansal16/agent-resume/actions/workflows/ci.yml)
[![npm](https://img.shields.io/npm/v/agent-resume.svg)](https://www.npmjs.com/package/agent-resume)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Your terminal comes back to the **same directory** and resumes the **same agent
conversation** after a reboot.

Agent CLIs (`claude`, `codex`, …) resolve "continue the last session" by *global*
recency, so with several terminals open, `claude --continue` can grab the wrong
conversation. And after a reboot you lose both your working directory and your
session. `agent-resume` fixes both by standing on `tmux` instead of reinventing it.

## Resume the last session, any agent

Just run the command — it resumes the last agent session you started in the
current directory, whichever agent it was:

```sh
agent-resume            # resume the last session here (claude, codex, hermes, …)
agent-resume claude     # resume the last claude session here
agent-resume codex      # resume the last codex session
```

The shim records each session you start, so `agent-resume` picks the right one
for your directory and runs `<agent> --resume <that-session-id>` — no picker, no
remembering ids. (It also powers the automatic tmux restore below.)

```
tmux              keeps live sessions alive on detach/reattach   (the 95% case, free)
tmux-resurrect    restores window layout + each pane's directory  (free)
tmux-continuum    auto-saves + auto-restores when tmux starts     (free)
agent shim        makes a restored pane resume the EXACT session  (the only custom part)
```

## Why the shim exists

tmux-resurrect brings a pane back to the right directory but restarts `claude`
**fresh**, not `claude --resume <that session>`. You can't just replay the launch
command either — verified behavior:

```
claude --session-id <existing-uuid>   ->  Error: Session ID is already in use
claude --resume     <existing-uuid>   ->  resumes correctly
```

So agent-resume:

1. On a **fresh interactive run**, launches `claude --session-id <new-uuid>`, so the
   id is baked into the command tmux-resurrect saves.
2. On **restore**, a pre-restore hook rewrites the saved `--session-id <uuid>` to
   `--resume <uuid>` (only for sessions that still exist). The pane relaunches into
   the exact conversation, in the exact directory.

Everything non-interactive (`-p/--print`, pipes, explicit `--resume`/`--continue`)
passes straight through. It never changes what the real CLI does in those cases.

## Install

Requirements: `tmux` and `git` (used once to fetch the tmux plugins). **tpm is
not required** — `install` fetches tmux-resurrect and tmux-continuum itself.

```sh
# via npm
npx agent-resume install

# or from a checkout
sh install.sh

# or curl-pipe
curl -fsSL https://raw.githubusercontent.com/rahulbansal16/agent-resume/main/install.sh | sh
```

Then:

```sh
exec $SHELL -l          # pick up the PATH change (shims)
tmux kill-server        # restart tmux so it loads the restore plugins
agent-resume doctor     # verify every link is green
```

Flags: `--agents claude,codex` (default), `--no-tmux`, `--no-shell`.

## Verify it works

```sh
# in a tmux pane:
cd ~/some/project && claude          # start a conversation
tmux kill-server                     # simulate a reboot
tmux                                 # continuum auto-restores
# -> pane returns to ~/some/project and resumes the same conversation
```

## Commands

| Command | Does |
|---|---|
| `agent-resume install` | install shims, PATH entry, and the tmux block |
| `agent-resume uninstall` | remove shims and the managed blocks |
| `agent-resume doctor` | check tmux, plugins, shims, PATH, and the hook |
| `agent-resume status` | list the newest claude session per project directory |

## Add another agent (`hermes`, …)

Drop one file in `~/.config/agent-resume/adapters/<agent>.conf` and re-run
`agent-resume install --agents <agent>`. No code changes.

```sh
AGENT_BIN="hermes"
AGENT_SUPPORTS_NEWID=1          # 1 if it can set the session id at launch
AGENT_NEWID_FLAG="--session-id"
AGENT_RESUME_FLAG="--resume"
AGENT_CONTINUE_FLAGS="-c --continue -r --resume"
AGENT_PRINT_FLAGS="-p --print"
AGENT_SESSION_DIR="$HOME/.hermes/sessions"
AGENT_SESSION_EXT="jsonl"
AGENT_ID_REGEX="[0-9a-f-]{36}"
```

Agents that can't set a session id at launch (`codex` today) still get directory
restore from tmux and a best-effort `resume`; exact conversation restore turns on
automatically once the CLI gains a launch-time id flag.

## How much survives what

| Event | Directory | Live agent process | Conversation |
|---|---|---|---|
| Detach / reattach (same machine) | ✅ tmux | ✅ still running | ✅ (never stopped) |
| Reboot / `tmux kill-server` | ✅ resurrect | relaunched | ✅ `--resume`d into the same session |
| Plain terminal, no tmux | — | — | per-launch ids only |

### Why the relaunch needs a post-restore hook

tmux-resurrect restores each pane's directory + shell, but it will **not**
relaunch Claude on its own: Claude renames its process to its version number
(e.g. `2.1.210`), so resurrect's name-based program matching never fires for it.
So agent-resume does the relaunch itself:

1. **pre-restore hook** rewrites the saved `--session-id <uuid>` to
   `--resume <uuid>` (for sessions that still exist).
2. **post-restore hook** types `claude --resume <uuid>` into each restored agent
   pane — the exact session, not a picker. resurrect keeps pane coordinates
   stable across restore, so each pane gets its own session back.

## Uninstall

```sh
agent-resume uninstall
rm -rf ~/.config/agent-resume     # also remove adapters/hooks
```

## License

MIT. Tests: `sh test/test.sh` (no tmux or real agent needed).
