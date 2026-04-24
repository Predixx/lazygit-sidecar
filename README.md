# agent-deck-lazygit

Interactive macOS installer that adds a lazygit split-pane to every
[agent-deck](https://github.com/asheshgoplani/agent-deck) session you
attach to. Left pane runs your coding agent (Claude Code, Codex,
Gemini, ...), right pane runs [lazygit](https://github.com/jesseduffield/lazygit).

## What it does

Adds a `client-attached` tmux hook that fires whenever you attach to a
tmux session whose name starts with `agentdeck_`. If that session's
window has exactly one pane, the hook splits it horizontally, puts
lazygit on the right (40%), and selects the left pane.

Idempotent on every level:
- already-split sessions are skipped, so re-attaching does not stack panes.
- the tmux config is wrapped in a `%if` guard so re-sourcing does not
  duplicate the hook.
- the hook uses `set-hook -ga` (append), which coexists with any
  existing `client-attached` hooks you already have.

Scoped: only sessions whose name starts with `agentdeck_` get the
lazygit pane. Other tmux sessions are not touched.

## Prerequisites

- macOS (tested on Apple Silicon, should work on Intel too)
- Homebrew
- tmux 3.1+
- agent-deck already installed
- zsh (default on modern macOS) for the optional `ad` shortcut

## Install

```sh
./install.sh
```

Every step explains what it will do and asks for confirmation. Nothing
happens without a `y`. Run the script again any time: it detects what
is already installed and skips those steps.

## Uninstall

```sh
./install.sh uninstall
```

Removes only the blocks the installer added (delimited by markers).
Hand-written tmux/zsh config is preserved.

## What gets changed

- `~/.tmux.conf` — a small `set-hook` block, appended between markers.
- `~/.zshrc` — an `ad()` shell function, appended between markers (optional).
- Homebrew installs `lazygit` if missing.

Nothing inside agent-deck itself is modified, so this survives
agent-deck updates.

## How to rebuild this by hand

See `install.sh` — the two code blocks it appends are self-contained.
You can copy them out and paste them into your configs manually.
