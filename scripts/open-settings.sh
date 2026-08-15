#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly TARGET="${1:-}"
readonly SOURCE_ROOT="${2:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly SETTINGS_FILE="$CONFIG_HOME/omarchy/plugin-control/channels.yaml"
readonly BINDINGS_FILE="$CONFIG_HOME/hypr/bindings.lua"
readonly EDITOR_STATE="$STATE_HOME/omarchy/defaults/editor"
readonly HELPER="$SOURCE_ROOT/bin/plugin-control"

line=1
status='{}'
case "$TARGET" in
  plugin)
    target="$SETTINGS_FILE"
    status="$("$HELPER" ensure-config "$SOURCE_ROOT" 2>/dev/null || true)"
    [[ -n $status ]] || status='{}'
    line="$(jq -r '.line // 1' <<<"$status" 2>/dev/null || printf 1)"
    title="Plugin Control settings"
    ;;
  keybindings)
    target="$BINDINGS_FILE"
    if [[ -r $target ]]; then
      line="$(awk '
        {
          current = tolower($0)
          if (current ~ /^[[:space:]]*(o|hl)\.bind[[:space:]]*\(/)
            bind_start = NR
          if (current ~ /plugin control|io\.github\.ilyazar\.plugin-control/) {
            print (bind_start > 0 ? bind_start : NR)
            exit
          }
        }
      ' "$target")"
      [[ -n $line ]] || line="$(awk 'END { print NR + 1 }' "$target")"
    fi
    title="Omarchy keybindings"
    ;;
  *)
    printf 'Usage: open-settings.sh <plugin|keybindings> [source-root]\n' >&2
    exit 2
    ;;
esac
[[ $line =~ ^[0-9]+$ && $line -ge 1 ]] || line=1

editor=nvim
if [[ -s $EDITOR_STATE ]]; then
  read -r editor <"$EDITOR_STATE" || true
fi
editor="${editor:-nvim}"
editor_name="${editor##*/}"

if command -v omarchy-notification-send >/dev/null 2>&1; then
  if [[ $TARGET == plugin ]] \
    && jq -e '.ok == false' <<<"$status" >/dev/null 2>&1; then
    message="$(jq -r '.error // "Invalid Plugin Control settings"' \
      <<<"$status")"
    omarchy-notification-send -u normal \
      "Plugin Control settings error" "$message" >/dev/null 2>&1 || true
  else
    omarchy-notification-send -u low \
      "Editing $title" "$target:$line" \
      >/dev/null 2>&1 || true
  fi
fi

case "$editor_name" in
  nvim|vim)
    exec omarchy-launch-editor "+$line" "+normal! zz" "$target"
    ;;
  nano)
    exec omarchy-launch-editor "+$line,1" "$target"
    ;;
  micro)
    exec omarchy-launch-editor "+$line:1" "$target"
    ;;
  hx|helix|subl|zed)
    exec omarchy-launch-editor "$target:$line:1"
    ;;
  code|codium)
    exec omarchy-launch-editor --goto "$target:$line:1"
    ;;
  *)
    exec omarchy-launch-config-editor "$target"
    ;;
esac
