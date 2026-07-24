# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-07-25

### Added

- The width of the lazygit pane is configurable. Pick it at install time with `./install.sh --width N`, combinable with any install mode and re-runnable to change it later. The interactive installer asks for it too.
- `LAZYGIT_SIDECAR_WIDTH` (1-99) overrides the installed width for a single run.
- agent-deck users can change the width of the next split without reinstalling: `tmux set -g @lazygit-sidecar-width N`.

### Changed

- **The default width is now 30%, previously 40%.** Reinstalling without an explicit `--width` applies the new default.
- `--width` writes to the two places actually read at runtime: the copy of `lazygit-sidecar` in `~/.local/bin` gets the value as its built-in default, and the agent-deck hook reads it from the `@lazygit-sidecar-width` tmux option, since a `run-shell` hook does not inherit the attaching shell's environment.
- The installer rewrites its marker block in place instead of skipping an existing one, so re-running with a different width takes effect while the block keeps its position in your config.
- Regular config files are now replaced atomically with their mode preserved; symlinked dotfiles are written through so a dotfiles-repo link stays intact.
- A failed `tmux source-file` after an install is reported instead of silently swallowed.
- Uninstalling the agent-deck integration also clears the `@lazygit-sidecar-width` tmux option.

### Fixed

- The tmux hook broke for any `HOME` containing a space or a `#`. `run-shell` format expansion turned `#h` in the embedded path into the hostname, and an unquoted path split on spaces, so the hook failed with exit 126. The generated hook line now defers expansion to `/bin/sh`, which also makes it portable across machines.
- Generating a config block could truncate `~/.zshrc` or `~/.tmux.conf`: the content was piped straight into the writer, so a producer dying mid-stream was indistinguishable from a short file. The complete file is now generated before anything is committed, and it is retained for recovery if the write fails.
- Width validation is matched lexically. The previous numeric test let integers too large for the shell fall through as valid.

### Documentation

- The README claimed bash 4+ was required. All scripts run under bash 3.2, so macOS's built-in bash is enough.

## [1.0.0] - 2026-04-26

### Fixed

- Installer: uninstall contract, dead code, missing `mkdir`, and unsafe PATH append (#1)

### Changed

- Homebrew install option removed; `install.sh` is the only supported path (#8)
- The interactive installer is presented as the default (#9)
- README rewritten for beginner-friendly progressive disclosure (#5)
- Images moved into `images/` (#7)

### Documentation

- Windows/WSL install note added (#6)
- Clarified that the git view only appears inside git repositories (#10, #11)
- Logo (#3, #4) and demo screenshot (#2) added

## [0.1.0] - 2026-04-25

Initial release.

### Added

- `lazygit-sidecar <command>` opens any CLI in tmux with lazygit as a right-side pane
- Optional agent-deck integration: a tmux hook that auto-splits every agent-deck session on attach
- Git-aware: the lazygit pane only appears inside a git repository
- Idempotent: re-attaching or re-sourcing never stacks extra panes
- Interactive installer, plus `--core` / `--agent-deck` / `--all` flags

[1.1.0]: https://github.com/Predixx/lazygit-sidecar/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Predixx/lazygit-sidecar/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/Predixx/lazygit-sidecar/releases/tag/v0.1.0
