# lazygit-sidecar

Persistent [lazygit](https://github.com/jesseduffield/lazygit) sidecar for any coding agent in tmux.

Run `lazygit-sidecar <command>` and get your command on the left and lazygit on the right, side by side, in a single tmux session. Works with Claude Code CLI, Codex CLI, Gemini CLI, plain zsh, or anything else you want to pair with a live git view.

If the working directory is not inside a git repository, lazygit is skipped and your command runs full-width.

## Demo

![lazygit-sidecar running Codex with lazygit on the right](demo.png)

```sh
lazygit-sidecar claude
lazygit-sidecar codex --dangerously-bypass-approvals-and-sandbox
lazygit-sidecar zsh
```

## Requirements

- tmux 3.1+ (needs the `-l 40%` split syntax)
- lazygit
- bash 4+

macOS is the primary target. Linux works fine if you install tmux and lazygit yourself; the `install.sh` convenience paths assume Homebrew.

## Install

### Homebrew (recommended)

```sh
brew tap Predixx/tap
brew install lazygit-sidecar
```

### Quick (macOS)

```sh
git clone https://github.com/Predixx/lazygit-sidecar.git
cd lazygit-sidecar
./install.sh --core
```

Installs lazygit (via Homebrew if missing) and copies `bin/lazygit-sidecar` to `~/.local/bin/`. The installer warns you if `~/.local/bin` is not on your PATH.

### Interactive

```sh
./install.sh
```

Walks through every step with a confirmation prompt before anything changes.

### Manual

```sh
install -m 0755 bin/lazygit-sidecar ~/.local/bin/lazygit-sidecar
# ensure ~/.local/bin is on PATH
```

## Usage

Pass any command. It runs in the left pane; lazygit runs in the right pane (40%).

```sh
lazygit-sidecar claude
lazygit-sidecar codex --some-flag
lazygit-sidecar gemini
lazygit-sidecar npm run dev
lazygit-sidecar zsh
```

The lazygit pane only appears when the working directory is inside a git repository. In non-git directories, your command runs in tmux at full width.

When the left command exits, its pane closes. Quit lazygit with `q`. When both panes are gone the tmux session ends and you return to your shell.

`lazygit-sidecar` refuses to run inside an existing tmux session (it does not nest). Detach the outer tmux first (`Ctrl-b d`) and try again.

## agent-deck integration (optional)

If you use [agent-deck](https://github.com/asheshgoplani/agent-deck), you can install a tmux `client-attached` hook so that every agent-deck session automatically gets a lazygit pane on attach:

```sh
./install.sh --agent-deck
```

This installs:
- A hook script at `~/.local/bin/lazygit-sidecar-hook` that checks session name (`agentdeck_*`), pane count (exactly 1), and git status before splitting.
- A one-line tmux hook in `~/.tmux.conf` at index [99] that calls the script on every attach. Re-sourcing the config overwrites the same slot (idempotent).
- An optional `ad()` zsh alias in `~/.zshrc` for quick session launches.

All config changes are wrapped in markers and can be cleanly removed.

## Uninstall

```sh
./install.sh --uninstall              # interactive
./install.sh --uninstall-core         # remove binaries only
./install.sh --uninstall-agent-deck   # remove hook + alias only
```

Only the marker-wrapped blocks get removed. Your hand-written tmux and zsh config stays intact.

lazygit itself stays installed (it is a standalone tool). Remove it with `brew uninstall lazygit` if you want.

## Troubleshooting

**`lazygit-sidecar: command not found`**
`~/.local/bin` is likely not on your PATH. Add to `~/.zshrc`:
```sh
export PATH="$HOME/.local/bin:$PATH"
```

**`already inside a tmux session`**
Detach the outer tmux first with `Ctrl-b d`, then run `lazygit-sidecar` from a plain terminal.

**`tmux 3.1+ required`**
Upgrade with `brew upgrade tmux`.

**No lazygit pane appeared**
You are probably not inside a git repository. `cd` into a git repo and try again.

## How it works

**Standalone** (`bin/lazygit-sidecar`, ~45 lines):

1. Sanity checks: not inside tmux, tmux and lazygit on PATH, tmux 3.1+.
2. `tmux new-session -d` with your command in pane 0.
3. If cwd is a git repo: `tmux split-window -h -l 40%` adds lazygit on the right.
4. `tmux attach` hands you the session.

No daemons, no background processes, no config files.

**agent-deck hook** (`bin/lazygit-sidecar-hook`):

Called by tmux on every client-attach. Checks three conditions (agent-deck session, single pane, git repo) and splits only when all three are met. Lives as a standalone script to avoid tmux quoting complexity.

## License

[MIT](LICENSE).
