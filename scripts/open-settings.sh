#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SOURCE_ROOT="${1:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly SETTINGS_FILE="$CONFIG_HOME/omarchy/plugin-control/channels.yaml"
readonly EDITOR_STATE="$STATE_HOME/omarchy/defaults/editor"
readonly HELPER="$SOURCE_ROOT/bin/plugin-control"

status="$("$HELPER" ensure-config "$SOURCE_ROOT" 2>/dev/null || true)"
[[ -n $status ]] || status='{}'
line="$(jq -r '.line // 1' <<<"$status" 2>/dev/null || printf 1)"
[[ $line =~ ^[0-9]+$ && $line -ge 1 ]] || line=1

editor=nvim
if [[ -s $EDITOR_STATE ]]; then
  read -r editor <"$EDITOR_STATE" || true
fi
editor="${editor:-nvim}"
editor_name="${editor##*/}"

if command -v omarchy-notification-send >/dev/null 2>&1; then
  if jq -e '.ok == false' <<<"$status" >/dev/null 2>&1; then
    message="$(jq -r '.error // "Invalid Plugin Control settings"' \
      <<<"$status")"
    omarchy-notification-send -u normal \
      "Plugin Control settings error" "$message" >/dev/null 2>&1 || true
  else
    omarchy-notification-send -u low \
      "Editing Plugin Control settings" "$SETTINGS_FILE:$line" \
      >/dev/null 2>&1 || true
  fi
fi

case "$editor_name" in
  nvim|vim)
    exec omarchy-launch-editor "+$line" "+normal! zz" "$SETTINGS_FILE"
    ;;
  nano)
    exec omarchy-launch-editor "+$line,1" "$SETTINGS_FILE"
    ;;
  micro)
    exec omarchy-launch-editor "+$line:1" "$SETTINGS_FILE"
    ;;
  hx|helix|subl|zed)
    exec omarchy-launch-editor "$SETTINGS_FILE:$line:1"
    ;;
  code|codium)
    exec omarchy-launch-editor --goto "$SETTINGS_FILE:$line:1"
    ;;
  *)
    exec omarchy-launch-config-editor "$SETTINGS_FILE"
    ;;
esac
