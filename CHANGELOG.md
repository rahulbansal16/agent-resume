# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

## [0.2.0] - 2026-07-16

- **New: `agent-resume` resumes the last session on demand.** Run `agent-resume`
  (bare) to resume the most recent agent session in the current directory, or
  `agent-resume <agent>` (e.g. `claude`, `codex`) to target one. The shim now
  records each launched session to a ledger (`~/.config/agent-resume/sessions.tsv`),
  and the command runs `<agent> --resume <that-id>` — no picker, no remembering
  ids. Falls back to the agent's own "resume last" (`claude --continue`,
  `codex resume --last`) when there's no recorded session. Adapters gain an
  optional `AGENT_RESUME_LAST` field.

## [0.1.3] - 2026-07-16

- **Fix: Claude sessions now actually resume after a reboot.** tmux-resurrect
  could not relaunch Claude because Claude renames its process to its version
  number (e.g. `2.1.210`), so restored panes came back as a bare shell in the
  right directory but with no conversation. Added a **post-restore hook** that
  types `claude --resume <session-id>` into each restored agent pane, and
  stopped listing the agents in `@resurrect-processes` (resurrect handles
  directory + shell; agent-resume handles the agent relaunch). Verified end to
  end with a real Claude session.

## [0.1.2] - 2026-07-16

- Fix: the CLI now reads its version from `package.json` (single source of
  truth) instead of a hardcoded constant that drifted (0.1.1 self-reported as
  0.1.0).

## [0.1.1] - 2026-07-16

- Fix: resolve the CLI's own path through symlinks so `install` works when the
  binary is an npm global bin (previously failed with `cp: .../lib/shim.sh: No
  such file or directory`).
- Self-contained tmux setup: `install` now fetches tmux-resurrect and
  tmux-continuum into `~/.config/agent-resume/tmux-plugins` and loads them
  directly, so **tpm is no longer required**. `doctor` checks for them there.
- Release automation moved to npm Trusted Publishing (OIDC) — no stored tokens,
  no secrets, no OTP.

## [0.1.0] - 2026-07-16

Initial release.

- Per-agent shim that bakes a `--session-id` on fresh interactive runs and flips
  an existing `--session-id` to `--resume` (so restored panes resume the exact
  conversation, and the "Session ID already in use" error is eliminated).
- tmux-resurrect pre-restore hook that rewrites saved `--session-id <uuid>` to
  `--resume <uuid>` for sessions that still exist.
- `install` / `uninstall` / `doctor` / `status` CLI.
- Adapters for `claude` (full) and `codex` (best-effort); new agents are one
  TOML-style file, no code changes.
- Zero runtime dependencies (POSIX sh); tests run without tmux or a real agent.

[Unreleased]: https://github.com/rahulbansal16/agent-resume/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/rahulbansal16/agent-resume/releases/tag/v0.1.0
