# Changelog

All notable changes to this project are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

## [0.1.1] - 2026-07-16

- Release automation moved to npm Trusted Publishing (OIDC) — no stored tokens,
  no secrets, no OTP. No functional changes to the package itself.

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
