#!/usr/bin/env bash
# Interactive installer for the agent-deck + lazygit split-pane integration.
# Every step explains what it will do and asks for confirmation.
#
# Usage:
#   ./install.sh              # install
#   ./install.sh uninstall    # remove everything it added

set -uo pipefail

MARKER_BEGIN="# >>> agent-deck lazygit split BEGIN"
MARKER_END="# <<< agent-deck lazygit split END"

TMUX_CONF="$HOME/.tmux.conf"
ZSHRC="$HOME/.zshrc"

# ---------- helpers ----------

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

has_block() {
  grep -qF "$MARKER_BEGIN" "$1" 2>/dev/null
}

append_block() {
  local file="$1" content="$2"
  printf '\n%s\n%s\n%s\n' "$MARKER_BEGIN" "$content" "$MARKER_END" >> "$file" \
    || return 1
}

# Remove exactly the first complete MARKER_BEGIN..MARKER_END block.
# Refuses to touch the file if either marker is missing or order is broken.
# Uses cat-redirect so that symlinked dotfiles keep their symlink.
remove_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  has_block "$file" || return 0
  local begin_line end_line
  begin_line=$(grep -nF "$MARKER_BEGIN" "$file" | head -1 | cut -d: -f1)
  end_line=$(grep -nF "$MARKER_END" "$file" | head -1 | cut -d: -f1)
  if [ -z "$begin_line" ] || [ -z "$end_line" ]; then
    echo "Warnung: $file enthaelt BEGIN- aber keinen END-Marker. Datei unveraendert." >&2
    return 1
  fi
  if [ "$end_line" -le "$begin_line" ]; then
    echo "Warnung: Marker in $file sind in falscher Reihenfolge. Datei unveraendert." >&2
    return 1
  fi
  local tmp
  tmp=$(mktemp) || return 1
  if ! sed "${begin_line},${end_line}d" "$file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  # cat-redirect preserves symlinks and file ownership/mode.
  cat "$tmp" > "$file" && rm -f "$tmp"
}

require() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  OK  %-12s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '  ??  %-12s NOT FOUND\n' "$cmd"
    return 1
  fi
}

# ---------- install steps ----------

install_flow() {
  step "Schritt 1 von 5: Prerequisites pruefen"
  cat <<EOF
Ich pruefe nur (lesend), ob diese Tools vorhanden sind:
  - tmux       (Terminal-Multiplexer, 3.1+ erforderlich)
  - agent-deck (das ist was wir erweitern)
  - brew       (damit ich lazygit installieren kann falls es fehlt)

Es wird NICHTS geaendert oder installiert in diesem Schritt.
EOF
  if confirm "Weiter?"; then
    local ok=1
    require tmux       || ok=0
    require agent-deck || ok=0
    require brew       || ok=0
    if [ "$ok" -ne 1 ]; then
      echo "Fehlende Tools bitte zuerst installieren, dann erneut starten."
      exit 1
    fi
    local tmux_ver
    tmux_ver=$(tmux -V | awk '{print $2}')
    echo "  tmux version: $tmux_ver"
    case "$tmux_ver" in
      3.0*|2.*|1.*|0.*)
        echo "tmux 3.1 oder neuer wird benoetigt (wegen '-l 40%' Syntax)."
        exit 1
        ;;
    esac
  else
    echo "Abgebrochen."
    exit 0
  fi

  step "Schritt 2 von 5: lazygit installieren"
  local lazygit_path
  if command -v lazygit >/dev/null 2>&1; then
    lazygit_path=$(command -v lazygit)
    echo "lazygit ist bereits da: $lazygit_path"
    echo "Schritt uebersprungen."
  else
    cat <<EOF
lazygit ist nicht installiert. Ich wuerde folgenden Befehl ausfuehren:

  brew install lazygit

Das laedt und installiert lazygit 0.x (MIT-lizenziert, Open Source,
https://github.com/jesseduffield/lazygit).
EOF
    if confirm "Installieren?"; then
      brew install lazygit || { echo "brew install fehlgeschlagen."; exit 1; }
      lazygit_path=$(command -v lazygit)
    else
      echo "Ohne lazygit macht der Rest keinen Sinn. Abbruch."
      exit 1
    fi
  fi

  step "Schritt 3 von 5: tmux-Hook in ~/.tmux.conf"
  # -ga appends a new hook slot instead of overwriting the existing slot 0.
  # The %if guard prevents duplicate registration when tmux.conf is sourced
  # multiple times (e.g. on server restart after this file is already loaded).
  local tmux_block
  tmux_block=$(cat <<EOF
%if "#{==:#{@agent_deck_lazygit_installed},1}"
%else
set-hook -ga client-attached {
  if-shell -F '#{&&:#{m:agentdeck_*,#{session_name}},#{==:#{window_panes},1}}' {
    split-window -h -l 40% '$lazygit_path'
    select-pane -L
  }
}
set-option -g @agent_deck_lazygit_installed 1
%endif
EOF
)
  if has_block "$TMUX_CONF"; then
    echo "In $TMUX_CONF ist der Block bereits eingetragen. Schritt uebersprungen."
  else
    cat <<EOF
Ich haenge folgenden Block ans Ende von $TMUX_CONF an (wird neu angelegt
falls die Datei nicht existiert). Bestehende Zeilen werden NICHT veraendert.

-------- Block --------
$MARKER_BEGIN
$tmux_block
$MARKER_END
-----------------------

Wirkung: Wenn du dich an eine tmux-Session anhaengst deren Name mit
'agentdeck_' beginnt und die genau 1 Pane hat, wird rechts zu 40% lazygit
gestartet. Andere tmux-Sessions bleiben unveraendert.
EOF
    if confirm "Anhaengen?"; then
      if append_block "$TMUX_CONF" "$tmux_block"; then
        echo "Angehaengt."
      else
        echo "Fehler beim Anhaengen an $TMUX_CONF." >&2
        exit 1
      fi
    else
      echo "Uebersprungen."
    fi
  fi

  step "Schritt 4 von 5: tmux-Server neu laden"
  if ! tmux info >/dev/null 2>&1; then
    echo "Es laeuft aktuell kein tmux-Server. Die Config greift automatisch"
    echo "beim naechsten tmux-Start. Schritt uebersprungen."
  else
    cat <<EOF
Damit der Hook sofort aktiv wird, muss der laufende tmux-Server die neue
Config laden:

  tmux source-file $TMUX_CONF

Achtung: source-file fuehrt die KOMPLETTE tmux-Config neu aus, nicht nur
unseren Block. Das ist normal (so funktioniert tmux), aber wenn deine
tmux.conf Seiteneffekte hat (z.B. Key-Bindings, die bei jedem Reload
zurueckgesetzt werden), solltest du das wissen. Bestehende Sessions
bleiben erhalten.
EOF
    if confirm "Jetzt reloaden?"; then
      tmux source-file "$TMUX_CONF" && echo "Geladen."
    else
      echo "Uebersprungen (wird beim naechsten tmux-Start aktiv)."
    fi
  fi

  step "Schritt 5 von 5: Shortcut 'ad' in ~/.zshrc (optional)"
  local zsh_block='ad() {
  command agent-deck launch -c claude "$@"
}'
  if has_block "$ZSHRC"; then
    echo "In $ZSHRC ist der Block bereits eingetragen. Schritt uebersprungen."
  else
    cat <<EOF
Optionaler Shortcut. Erlaubt dir Sessions direkt aus dem Terminal zu
starten statt ueber die agent-deck TUI:

-------- Block --------
$MARKER_BEGIN
$zsh_block
$MARKER_END
-----------------------

Wirkung: 'ad .' startet eine neue Claude-Session im current dir. Der Split
selber kommt vom tmux-Hook oben, nicht von dieser Function. Wenn du die
TUI ohnehin bevorzugst, kannst du diesen Schritt ueberspringen.
EOF
    if confirm "Anhaengen?"; then
      if append_block "$ZSHRC" "$zsh_block"; then
        echo "Angehaengt. Neues Terminal oeffnen oder: source $ZSHRC"
      else
        echo "Fehler beim Anhaengen an $ZSHRC." >&2
        exit 1
      fi
    else
      echo "Uebersprungen."
    fi
  fi

  step "Fertig"
  cat <<EOF
Installation abgeschlossen.

Naechste Schritte:
  1. Neues Terminal oeffnen (oder 'source ~/.zshrc' falls Schritt 5 gemacht)
  2. agent-deck starten
  3. Eine Session attachen (neu oder bestehend)
  4. Rechts erscheint lazygit, links laeuft Claude / Codex / etc.

Zum Entfernen: $0 uninstall
EOF
}

# ---------- uninstall steps ----------

uninstall_flow() {
  step "Uninstall Schritt 1 von 3: ad() aus ~/.zshrc"
  if has_block "$ZSHRC"; then
    echo "Der markierte Block wird aus $ZSHRC entfernt (nur zwischen den Markern)."
    if confirm "Entfernen?"; then
      if remove_block "$ZSHRC"; then
        echo "Entfernt."
      else
        echo "Fehler beim Entfernen. Datei wurde nicht geaendert." >&2
        return 1
      fi
    else
      echo "Uebersprungen."
    fi
  else
    echo "Kein Block in $ZSHRC gefunden. Schritt uebersprungen."
  fi

  step "Uninstall Schritt 2 von 3: tmux-Hook aus ~/.tmux.conf"
  if has_block "$TMUX_CONF"; then
    echo "Der markierte Block wird aus $TMUX_CONF entfernt."
    if confirm "Entfernen?"; then
      if ! remove_block "$TMUX_CONF"; then
        echo "Fehler beim Entfernen. Datei wurde nicht geaendert." >&2
        return 1
      fi
      echo "Entfernt."
      if tmux info >/dev/null 2>&1; then
        if confirm "Hook sofort aus laufendem tmux-Server deregistrieren?"; then
          # Our hook might be at any index because install uses -ga append.
          # Find the slot whose body references our pattern and remove only that one.
          local slot
          slot=$(tmux show-hooks -g 2>/dev/null \
            | awk -F'[][]' '/^client-attached\[[0-9]+\].*agentdeck_/ {print $2; exit}')
          if [ -n "$slot" ]; then
            tmux set-hook -gu "client-attached[$slot]" 2>/dev/null
          fi
          tmux set-option -gu @agent_deck_lazygit_installed 2>/dev/null || true
          echo "Deregistriert${slot:+ (slot [$slot])}."
        fi
      fi
    else
      echo "Uebersprungen."
    fi
  else
    echo "Kein Block in $TMUX_CONF gefunden. Schritt uebersprungen."
  fi

  step "Uninstall Schritt 3 von 3: lazygit deinstallieren (optional)"
  if command -v lazygit >/dev/null 2>&1; then
    cat <<EOF
lazygit ist noch installiert. Es ist ein nuetzliches Standalone-Tool,
also belasse ich es by default. Wenn du es trotzdem entfernen willst:

  brew uninstall lazygit
EOF
    if confirm "brew uninstall lazygit ausfuehren?"; then
      brew uninstall lazygit
    else
      echo "lazygit bleibt installiert."
    fi
  else
    echo "lazygit nicht gefunden. Schritt uebersprungen."
  fi

  step "Uninstall fertig"
  echo "Die Integration ist entfernt. Neues Terminal oeffnen damit 'ad' weg ist."
}

# ---------- dispatch ----------

case "${1:-install}" in
  install)   install_flow ;;
  uninstall) uninstall_flow ;;
  *)
    echo "Usage: $0 [install|uninstall]"
    exit 2
    ;;
esac
