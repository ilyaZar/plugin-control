#!/bin/bash

set -euo pipefail

readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly BINDINGS_FILE="${1:-$CONFIG_HOME/hypr/bindings.lua}"
readonly EDITOR_STATE="$STATE_HOME/omarchy/defaults/editor"

target_line=1
if [[ -r $BINDINGS_FILE ]]; then
  target_line="$(awk '
    {
      line = tolower($0)
      if (line ~ /plugin control/ ||
          line ~ /io\.github\.ilyazar\.plugin-control/) {
        print NR
        exit
      }
    }
  ' "$BINDINGS_FILE")"
  if [[ -z $target_line ]]; then
    target_line="$(awk 'END { print NR + 1 }' "$BINDINGS_FILE")"
  fi
fi

editor=nvim
if [[ -s $EDITOR_STATE ]]; then
  read -r editor <"$EDITOR_STATE" || true
fi
editor="${editor:-nvim}"
editor_name="${editor##*/}"

case "$editor_name" in
  nvim|vim)
    exec omarchy-launch-editor "+$target_line" "+normal! zz" \
      "$BINDINGS_FILE"
    ;;
  nano)
    exec omarchy-launch-editor "+$target_line,1" "$BINDINGS_FILE"
    ;;
  micro)
    exec omarchy-launch-editor "+$target_line:1" "$BINDINGS_FILE"
    ;;
  hx|helix|subl|zed)
    exec omarchy-launch-editor "$BINDINGS_FILE:$target_line:1"
    ;;
  code|codium)
    exec omarchy-launch-editor --goto "$BINDINGS_FILE:$target_line:1"
    ;;
  *)
    exec omarchy-launch-config-editor "$BINDINGS_FILE"
    ;;
esac
