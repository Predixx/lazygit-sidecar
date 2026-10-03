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
# Options:
#   --width N   lazygit pane width in percent (1-99, default 30). Combine
#               with any install mode, e.g. ./install.sh --all --width 20.
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

DEFAULT_WIDTH=30
SIDECAR_WIDTH=$DEFAULT_WIDTH

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

ask_width() {
  local answer
  while true; do
    read -r -p "lazygit pane width in percent [$SIDECAR_WIDTH]: " answer
    [ -z "$answer" ] && return 0
    set_width "$answer" && return 0
  done
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

# Matched lexically: a numeric test would let integers too large for the
# shell fall through as valid.
set_width() {
  local w="${1:-}"
  if ! [[ "$w" =~ ^([1-9]|[1-9][0-9])$ ]]; then
    echo "error: width must be an integer between 1 and 99 (got '$w')." >&2
    return 1
  fi
  SIDECAR_WIDTH="$w"
}

has_block() { grep -qF "$MARKER_BEGIN" "$1" 2>/dev/null; }

# Echo "BEGIN_LINE END_LINE" for the first complete marker block. Refuses if
# either marker is missing or the order is reversed.
block_range() {
  local file="$1" begin_line end_line
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
  echo "$begin_line $end_line"
}

# Replace $1's content with the file at $2, which must already be complete.
# Never pipe a generator straight into this: a producer that dies mid-stream
# looks exactly like a short file, and the dotfile would be truncated.
#
# A symlinked dotfile is written through so it keeps pointing into its
# dotfiles repo; a rename would replace the link with a regular file. Regular
# files get an atomic same-directory rename instead.
#
# On failure the caller keeps $2, so never delete it here.
commit_file() {
  local file="$1" src="$2" tmp perms
  if [ -L "$file" ]; then
    cat "$src" > "$file" && return 0
    return 1
  fi
  tmp=$(mktemp "$(dirname "$file")/.lazygit-sidecar.XXXXXX") || return 1
  if ! cat "$src" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if [ -e "$file" ]; then
    # Fail closed: silently handing the user a 0600 dotfile from mktemp is
    # worse than refusing. BSD stat first, GNU second.
    perms=$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)
    if [ -z "$perms" ] || ! chmod "$perms" "$tmp"; then
      rm -f "$tmp"
      echo "error: could not preserve the permissions of $file." >&2
      return 1
    fi
  fi
  mv -f "$tmp" "$file" && return 0
  rm -f "$tmp"
  return 1
}

# Commit the generated file, keeping it around for recovery if the write
# fails part-way (the copy-through path can truncate a symlink target).
commit_or_keep() {
  local file="$1" src="$2"
  if ! commit_file "$file" "$src"; then
    echo "error: failed to update $file; it may be partially written." >&2
    echo "       The complete new content is kept at:" >&2
    echo "       $src" >&2
    return 1
  fi
  rm -f "$src"
}

# Install or update the block. An existing block is replaced where it sits,
# so re-running with a different --width neither moves it (later user
# settings keep overriding it) nor stacks up blank separators.
write_block() {
  local file="$1" content="$2" range begin_line end_line tmp
  if [ ! -f "$file" ] || ! has_block "$file"; then
    printf '\n%s\n%s\n%s\n' "$MARKER_BEGIN" "$content" "$MARKER_END" >> "$file" \
      || return 1
    return 0
  fi

  range=$(block_range "$file") || return 1
  begin_line=${range% *}
  end_line=${range#* }

  tmp=$(mktemp) || return 1
  # Subshell so a failing producer aborts generation instead of the installer,
  # and so nothing is committed unless the whole file was generated.
  if ! (
    if [ "$begin_line" -gt 1 ]; then
      sed -n "1,$((begin_line - 1))p" "$file" || exit 1
    fi
    printf '%s\n%s\n%s\n' "$MARKER_BEGIN" "$content" "$MARKER_END" || exit 1
    sed -n "$((end_line + 1)),\$p" "$file" || exit 1
  ) > "$tmp"; then
    rm -f "$tmp"
    echo "error: could not generate the new $file; file unchanged." >&2
    return 1
  fi

  commit_or_keep "$file" "$tmp"
}

# Remove first complete MARKER_BEGIN..MARKER_END block.
remove_block() {
  local file="$1" range begin_line end_line tmp
  [ -f "$file" ] || return 0
  has_block "$file" || return 0
  range=$(block_range "$file") || return 1
  begin_line=${range% *}
  end_line=${range#* }

  tmp=$(mktemp) || return 1
  if ! sed "${begin_line},${end_line}d" "$file" > "$tmp"; then
    rm -f "$tmp"
    echo "error: could not generate the new $file; file unchanged." >&2
    return 1
  fi

  commit_or_keep "$file" "$tmp"
}

# Copy the standalone script with SIDECAR_WIDTH baked in as its default, so
# --width configures the command itself and not just the agent-deck hook.
# LAZYGIT_SIDECAR_WIDTH still overrides it per run.
install_binary() {
  local tmp
  mkdir -p "$BIN_DEST_DIR" || return 1
  tmp=$(mktemp) || return 1
  if ! sed "s/^DEFAULT_WIDTH=.*/DEFAULT_WIDTH=$SIDECAR_WIDTH/" "$BIN_SRC" > "$tmp" ||
     ! grep -q "^DEFAULT_WIDTH=$SIDECAR_WIDTH\$" "$tmp"; then
    rm -f "$tmp"
    echo "error: could not set the default width in $BIN_SRC." >&2
    return 1
  fi
  install -m 0755 "$tmp" "$BIN_DEST" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  echo "installed: $BIN_DEST (lazygit pane: ${SIDECAR_WIDTH}%)"
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

  install_binary || return 1

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

  mkdir -p "$BIN_DEST_DIR"
  install -m 0755 "$REPO_DIR/bin/lazygit-sidecar-hook" "$BIN_DEST_DIR/lazygit-sidecar-hook" || {
    echo "error: failed to install hook script." >&2
    return 1
  }
  echo "installed: $BIN_DEST_DIR/lazygit-sidecar-hook"

  # A run-shell hook does not inherit your interactive shell environment, so
  # the width travels as a tmux option the hook reads back. That also keeps
  # the hook line free of a second layer of shell quoting.
  #
  # The path is left as an escaped \$HOME for /bin/sh to expand: run-shell
  # applies tmux format expansion first, which would eat a '#' in the path
  # (turning '#h' into the hostname), and an unquoted literal path would also
  # split on spaces.
  local tmux_block existed=0
  tmux_block="set-option -g @lazygit-sidecar-width $SIDECAR_WIDTH
set-hook -g 'client-attached[99]' 'run-shell \"exec \\\"\\\$HOME/.local/bin/lazygit-sidecar-hook\\\"\"'"

  # Rewrite an existing block instead of skipping it, so re-running with a
  # different --width actually changes the installed hook.
  has_block "$TMUX_CONF" && existed=1
  write_block "$TMUX_CONF" "$tmux_block" || {
    echo "error: failed to write to $TMUX_CONF" >&2
    return 1
  }
  if [ "$existed" -eq 1 ]; then
    echo "updated tmux hook in $TMUX_CONF (lazygit pane: ${SIDECAR_WIDTH}%)"
  else
    echo "appended tmux hook to $TMUX_CONF (lazygit pane: ${SIDECAR_WIDTH}%)"
  fi
  if tmux info >/dev/null 2>&1; then
    if tmux source-file "$TMUX_CONF"; then
      echo "reloaded running tmux server."
    else
      echo "warn: '$TMUX_CONF' failed to reload; the running tmux server may be" >&2
      echo "      only partially updated. Fix the error above, then run:" >&2
      echo "          tmux source-file $TMUX_CONF" >&2
    fi
  fi

  local zsh_block='ad() {
  command agent-deck launch -c claude "$@"
}'
  if has_block "$ZSHRC"; then
    echo "$ZSHRC already contains the integration block; skipping zsh part."
  else
    write_block "$ZSHRC" "$zsh_block" && echo "appended ad() alias to $ZSHRC"
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
  if [ -f "$BIN_DEST_DIR/lazygit-sidecar-hook" ]; then
    rm -f "$BIN_DEST_DIR/lazygit-sidecar-hook" && echo "removed $BIN_DEST_DIR/lazygit-sidecar-hook"
    did=1
  fi
  if has_block "$TMUX_CONF"; then
    if remove_block "$TMUX_CONF"; then
      echo "removed block from $TMUX_CONF"
      did=1
      if tmux info >/dev/null 2>&1; then
        tmux set-hook -gu 'client-attached[99]' 2>/dev/null
        tmux set-option -gu @lazygit-sidecar-width 2>/dev/null
      fi
    fi
  fi
  if has_block "$ZSHRC"; then
    if remove_block "$ZSHRC"; then
      echo "removed block from $ZSHRC"
      did=1
    fi
  fi
  if [ $did -eq 0 ]; then
    echo "no integration blocks found; nothing to remove."
  fi
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

The git view opens as a vertical split on the right. Choose how wide it
should be, or press Enter for the default.
EOF
  ask_width
  if confirm "Install?"; then
    install_binary || { echo "copy failed."; exit 1; }
  else
    echo "Skipped."
  fi

  if ! path_contains "$BIN_DEST_DIR"; then
    cat <<EOF

note: $BIN_DEST_DIR is not on your PATH.
      Add this line to ~/.zshrc (or ~/.bashrc):

          export PATH="\$HOME/.local/bin:\$PATH"
EOF
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

Change the width later with: $0 --all --width N
Override it for a single run: LAZYGIT_SIDECAR_WIDTH=50 lazygit-sidecar zsh
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
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------- dispatch ----------

ACTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --width)   shift; set_width "${1:-}" || exit 2 ;;
    --width=*) set_width "${1#*=}" || exit 2 ;;
    --core|--agent-deck|--all|--uninstall|--uninstall-core|--uninstall-agent-deck)
      if [ -n "$ACTION" ]; then
        echo "error: $ACTION and $1 cannot be combined." >&2
        exit 2
      fi
      ACTION="$1"
      ;;
    --help|-h) usage; exit 0 ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$ACTION" in
  "")                     interactive_install ;;
  --core)                 install_core ;;
  --agent-deck)           install_agent_deck ;;
  --all)                  install_core && install_agent_deck ;;
  --uninstall)            interactive_uninstall ;;
  --uninstall-core)       uninstall_core ;;
  --uninstall-agent-deck) uninstall_agent_deck ;;
esac
