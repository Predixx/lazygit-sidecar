#!/usr/bin/env bash
# lazygit-sidecar installer.
#
# Modes:
#   ./install.sh                        Interactive install wizard (default).
#   ./install.sh --core                 Install lazygit (brew) + copy binary.
#   ./install.sh --agent-deck           Install tmux hook + ad() zsh alias.
#   ./install.sh --all                  --core then --agent-deck.
#   ./install.sh --uninstall            Interactive uninstall wizard.
#   ./install.sh --uninstall-core       Remove the binary only.
#   ./install.sh --uninstall-agent-deck Remove tmux hook + ad() alias.
#   ./install.sh --help                 Show usage.
#
# Marker-scoped: nothing outside installer-added blocks gets touched.

set -uo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
BIN_SRC="$REPO_DIR/bin/lazygit-sidecar"
BIN_DEST_DIR="$HOME/.local/bin"
BIN_DEST="$BIN_DEST_DIR/lazygit-sidecar"

TMUX_CONF="$HOME/.tmux.conf"
ZSHRC="$HOME/.zshrc"

MARKER_BEGIN="# >>> lazygit-sidecar agent-deck integration BEGIN"
MARKER_END="# <<< lazygit-sidecar agent-deck integration END"

# ---------- tiny helpers ----------

step() {
  echo
  echo "=============================================================="
  echo " $1"
  echo "=============================================================="
}

confirm() {
  local answer
  read -r -p "$1 [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

path_contains() {
  case ":$PATH:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

tmux_version_ok() {
  local ver
  ver=$(tmux -V 2>/dev/null | awk '{print $2}')
  case "$ver" in
    3.0*|2.*|1.*|0.*) return 1 ;;
    *) return 0 ;;
  esac
}

has_block() { grep -qF "$MARKER_BEGIN" "$1" 2>/dev/null; }

append_block() {
  local file="$1" content="$2"
  printf '\n%s\n%s\n%s\n' "$MARKER_BEGIN" "$content" "$MARKER_END" >> "$file" \
    || return 1
}

# Remove first complete MARKER_BEGIN..MARKER_END block. Refuses if either
# marker is missing or the order is reversed. Uses cat-redirect so
# symlinked dotfiles keep their symlink target.
remove_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  has_block "$file" || return 0
  local begin_line end_line
  begin_line=$(grep -nF "$MARKER_BEGIN" "$file" | head -1 | cut -d: -f1)
  end_line=$(grep -nF "$MARKER_END" "$file" | head -1 | cut -d: -f1)
  if [ -z "$begin_line" ] || [ -z "$end_line" ]; then
    echo "warn: $file has BEGIN without END; file unchanged." >&2
    return 1
  fi
  if [ "$end_line" -le "$begin_line" ]; then
    echo "warn: markers in $file are out of order; file unchanged." >&2
    return 1
  fi
  local tmp
  tmp=$(mktemp) || return 1
  if ! sed "${begin_line},${end_line}d" "$file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp" > "$file" && rm -f "$tmp"
}

# ---------- non-interactive actions ----------

install_core() {
  if ! command -v tmux >/dev/null 2>&1; then
    echo "error: tmux is not installed. macOS: brew install tmux" >&2
    return 1
  fi
  if ! tmux_version_ok; then
    echo "error: tmux 3.1+ required (found $(tmux -V))." >&2
    return 1
  fi

  if command -v lazygit >/dev/null 2>&1; then
    echo "lazygit: $(command -v lazygit)"
  else
    if ! command -v brew >/dev/null 2>&1; then
      echo "error: lazygit missing and brew unavailable. Install lazygit manually." >&2
      return 1
    fi
    echo "Installing lazygit via Homebrew..."
    brew install lazygit || return 1
  fi

  mkdir -p "$BIN_DEST_DIR"
  install -m 0755 "$BIN_SRC" "$BIN_DEST" || return 1
  echo "installed: $BIN_DEST"

  if ! path_contains "$BIN_DEST_DIR"; then
    cat <<EOF

note: $BIN_DEST_DIR is not on your PATH.
      Add this line to ~/.zshrc (or ~/.bashrc):

          export PATH="\$HOME/.local/bin:\$PATH"
EOF
  fi
}

install_agent_deck() {
  if ! command -v lazygit >/dev/null 2>&1; then
    echo "error: lazygit not found; run --core first." >&2
    return 1
  fi
  local lazygit_path
  lazygit_path=$(command -v lazygit)

  local tmux_block
  tmux_block=$(cat <<EOF
%if "#{==:#{@lazygit_sidecar_installed},1}"
%else
set-hook -ga client-attached {
  if-shell -F '#{&&:#{m:agentdeck_*,#{session_name}},#{==:#{window_panes},1}}' {
    split-window -h -l 40% '$lazygit_path'
    select-pane -L
  }
}
set-option -g @lazygit_sidecar_installed 1
%endif
EOF
)

  if has_block "$TMUX_CONF"; then
    echo "$TMUX_CONF already contains the integration block; skipping tmux part."
  else
    append_block "$TMUX_CONF" "$tmux_block" || {
      echo "error: failed to append to $TMUX_CONF" >&2
      return 1
    }
    echo "appended tmux hook to $TMUX_CONF"
    if tmux info >/dev/null 2>&1; then
      tmux source-file "$TMUX_CONF" 2>/dev/null && echo "reloaded running tmux server."
    fi
  fi

  local zsh_block='ad() {
  command agent-deck launch -c claude "$@"
}'
  if has_block "$ZSHRC"; then
    echo "$ZSHRC already contains the integration block; skipping zsh part."
  else
    append_block "$ZSHRC" "$zsh_block" && echo "appended ad() alias to $ZSHRC"
  fi
}

uninstall_core() {
  if [ -f "$BIN_DEST" ]; then
    rm -f "$BIN_DEST" && echo "removed $BIN_DEST"
  else
    echo "$BIN_DEST not present; nothing to remove."
  fi
}

uninstall_agent_deck() {
  local did=0
  if has_block "$TMUX_CONF"; then
    if remove_block "$TMUX_CONF"; then
      echo "removed block from $TMUX_CONF"
      did=1
      if tmux info >/dev/null 2>&1; then
        local slot
        slot=$(tmux show-hooks -g 2>/dev/null \
          | awk -F'[][]' '/^client-attached\[[0-9]+\].*agentdeck_/ {print $2; exit}')
        [ -n "$slot" ] && tmux set-hook -gu "client-attached[$slot]" 2>/dev/null
        tmux set-option -gu @lazygit_sidecar_installed 2>/dev/null || true
      fi
    fi
  fi
  if has_block "$ZSHRC"; then
    if remove_block "$ZSHRC"; then
      echo "removed block from $ZSHRC"
      did=1
    fi
  fi
  [ $did -eq 0 ] && echo "no integration blocks found; nothing to remove."
}

# ---------- interactive flow ----------

interactive_install() {
  step "Step 1/4: Prerequisites"
  cat <<EOF
Checking (read-only):
  - tmux       (3.1+ required)
  - lazygit    (will be brew-installed if missing)
  - brew       (only needed if lazygit is missing)
EOF
  confirm "Continue?" || { echo "Aborted."; exit 0; }

  if command -v tmux >/dev/null 2>&1; then
    echo "  OK  tmux      $(command -v tmux) ($(tmux -V))"
    tmux_version_ok || { echo "tmux 3.1+ required. Abort."; exit 1; }
  else
    echo "  --  tmux      NOT FOUND"
    echo "Install tmux first (macOS: brew install tmux). Abort."
    exit 1
  fi
  if command -v lazygit >/dev/null 2>&1; then
    echo "  OK  lazygit   $(command -v lazygit)"
  else
    echo "  !!  lazygit   will be installed in step 2"
  fi
  if command -v brew >/dev/null 2>&1; then
    echo "  OK  brew      $(command -v brew)"
  else
    echo "  !!  brew      not found; required only if lazygit is missing"
  fi

  step "Step 2/4: Install lazygit"
  if command -v lazygit >/dev/null 2>&1; then
    echo "lazygit already installed; skip."
  else
    if ! command -v brew >/dev/null 2>&1; then
      echo "brew not found; install lazygit manually (https://github.com/jesseduffield/lazygit) then re-run."
      exit 1
    fi
    if confirm "Run: brew install lazygit?"; then
      brew install lazygit || { echo "brew install failed."; exit 1; }
    else
      echo "Cannot continue without lazygit. Abort."
      exit 1
    fi
  fi

  step "Step 3/4: Install lazygit-sidecar binary"
  cat <<EOF
I will copy:
  $BIN_SRC
to:
  $BIN_DEST
(with mode 0755). The parent directory will be created if missing.
EOF
  if confirm "Install?"; then
    mkdir -p "$BIN_DEST_DIR"
    install -m 0755 "$BIN_SRC" "$BIN_DEST" || { echo "copy failed."; exit 1; }
    echo "installed: $BIN_DEST"
  else
    echo "Skipped."
  fi

  if ! path_contains "$BIN_DEST_DIR"; then
    echo
    cat <<EOF
$BIN_DEST_DIR is NOT on your PATH. I can append this line to ~/.zshrc:

  export PATH="\$HOME/.local/bin:\$PATH"
EOF
    if confirm "Append?"; then
      printf '\n# lazygit-sidecar: ensure ~/.local/bin is on PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$ZSHRC"
      echo "Appended. Open a new terminal or: source ~/.zshrc"
    else
      echo "Skipped. Make sure $BIN_DEST_DIR is on PATH or the command will not be found."
    fi
  fi

  step "Step 4/4: agent-deck integration (optional)"
  cat <<EOF
Only for agent-deck users. Adds a tmux client-attached hook that
auto-splits every agent-deck session (name prefix 'agentdeck_') so
lazygit appears on the right. Also adds an 'ad' zsh alias.

Skip this step if you do not use agent-deck.
EOF
  if confirm "Install agent-deck integration?"; then
    install_agent_deck || exit 1
  else
    echo "Skipped."
  fi

  step "Done"
  cat <<EOF
Installation complete. Test:

  lazygit-sidecar zsh

(If PATH was updated, open a new terminal or run: source ~/.zshrc)

Uninstall later with: $0 --uninstall
EOF
}

interactive_uninstall() {
  step "Uninstall step 1/2: lazygit-sidecar binary"
  if [ -f "$BIN_DEST" ]; then
    echo "Will remove: $BIN_DEST"
    if confirm "Remove?"; then
      rm -f "$BIN_DEST" && echo "removed."
    else
      echo "Skipped."
    fi
  else
    echo "$BIN_DEST not present; skip."
  fi

  step "Uninstall step 2/2: agent-deck integration"
  if has_block "$TMUX_CONF" || has_block "$ZSHRC"; then
    if confirm "Remove integration blocks from ~/.tmux.conf and ~/.zshrc?"; then
      uninstall_agent_deck
    else
      echo "Skipped."
    fi
  else
    echo "No integration blocks found; skip."
  fi

  step "Done"
  cat <<EOF
lazygit stays installed (standalone tool). Remove with:
  brew uninstall lazygit
EOF
}

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------- dispatch ----------

case "${1:-}" in
  "")                     interactive_install ;;
  --core)                 install_core ;;
  --agent-deck)           install_agent_deck ;;
  --all)                  install_core && install_agent_deck ;;
  --uninstall)            interactive_uninstall ;;
  --uninstall-core)       uninstall_core ;;
  --uninstall-agent-deck) uninstall_agent_deck ;;
  --help|-h)              usage ;;
  *)
    echo "unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
esac
