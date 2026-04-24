# lazygit-sidecar

Persistent [lazygit](https://github.com/jesseduffield/lazygit) sidecar for any coding agent in tmux.

Run `lazygit-sidecar <command>` and get your command on the left and lazygit on the right, side by side, in a single tmux session. Works with Claude Code CLI, Codex CLI, Gemini CLI, plain zsh, or anything else you want to pair with a live git view.

## Demo

```sh
lazygit-sidecar claude
lazygit-sidecar codex --dangerously-bypass-approvals-and-sandbox
lazygit-sidecar zsh
```

## Requirements

- tmux 3.1+ (needs the `-l 40%` split syntax)
- lazygit
- bash 4+ (the installer uses `printf -v`)

macOS is the primary target. Linux works fine if you install tmux and lazygit yourself; the `install.sh` convenience paths assume Homebrew.

## Install

### Quick (macOS)

```sh
git clone https://github.com/Predixx/lazygit-sidecar.git
cd lazygit-sidecar
./install.sh --core
```

Installs lazygit (via Homebrew if missing) and copies `bin/lazygit-sidecar` to `~/.local/bin/`. The installer warns you if `~/.local/bin` is not on your PATH and offers to add one line to your `~/.zshrc`.

### Interactive

```sh
./install.sh
```

Walks through every step with a confirmation prompt. Same end state as `--core`, but you see exactly what is happening.

### Manual

```sh
install -m 0755 bin/lazygit-sidecar ~/.local/bin/lazygit-sidecar
# ensure ~/.local/bin is on PATH
```

## Usage

Pass any command. It runs in the left pane; lazygit runs in the right pane.

```sh
lazygit-sidecar claude
lazygit-sidecar codex --some-flag
lazygit-sidecar gemini
lazygit-sidecar npm run dev
lazygit-sidecar zsh
```

When the left command exits, its pane closes. Quit lazygit with `q`. When both panes are gone the tmux session ends and you return to your shell.

`lazygit-sidecar` refuses to run inside an existing tmux session (it does not nest). Detach the outer tmux first (`Ctrl-b d`) and try again.

## agent-deck integration (optional)

If you use [agent-deck](https://github.com/asheshgoplani/agent-deck), you can install a tmux `client-attached` hook so that every agent-deck session automatically gets a lazygit pane on attach, no `lazygit-sidecar` command needed:

```sh
./install.sh --agent-deck
```

Appends a marker-scoped block to `~/.tmux.conf` (guarded by `%if`, uses `set-hook -ga`, coexists with existing hooks) and adds an optional `ad()` zsh alias to `~/.zshrc`.

The hook is idempotent: sessions that already have two or more panes are skipped, so re-attaching never stacks extra panes.

## Uninstall

```sh
./install.sh --uninstall              # interactive
./install.sh --uninstall-core         # remove the binary only
./install.sh --uninstall-agent-deck   # remove hook + alias only
```

Uninstall is marker-scoped. Only the blocks the installer added get removed. Hand-written tmux/zsh config is preserved.

lazygit itself stays installed (it is a useful standalone tool). Remove it yourself with `brew uninstall lazygit` if you want.

## Troubleshooting

**`lazygit-sidecar: command not found`** — `~/.local/bin` is likely not on your PATH. Add to `~/.zshrc`:
```sh
export PATH="$HOME/.local/bin:$PATH"
```
Then `source ~/.zshrc`.

**`already inside a tmux session`** — `lazygit-sidecar` does not nest. Detach the outer tmux first with `Ctrl-b d`.

**`tmux 3.1+ required`** — the `-l 40%` split syntax needs tmux 3.1 or newer. Upgrade with `brew upgrade tmux`.

**Split is fine but lazygit shows "not a git repository"** — you launched `lazygit-sidecar` from a non-git directory. Change into a git repo first, or use it in a git worktree.

## How it works

One script, ~40 lines:

1. Sanity checks (`$TMUX` empty, tmux and lazygit on PATH, tmux version).
2. `tmux new-session -d` creates a detached session with your command in pane 0.
3. `tmux split-window -h -l 40%` adds lazygit on the right.
4. `tmux attach` hands you the session.

Nothing else. No daemons, no background processes, no config files. When the session ends you are back in your plain terminal.

The agent-deck integration is a separate tmux hook that triggers the same layout on session attach. See `install.sh` for the exact block it appends.

## License

[MIT](LICENSE).
