#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT
TEMP_ROOT="$(mktemp -d /tmp/plugin-control-helper-test.XXXXXX)"
readonly TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/config"
export XDG_CACHE_HOME="$TEMP_ROOT/cache"
export XDG_STATE_HOME="$TEMP_ROOT/state"
export XDG_RUNTIME_DIR="$TEMP_ROOT/runtime"
export MOCK_EDITOR_LOG="$TEMP_ROOT/editor.log"
export PATH="$TEMP_ROOT/bin:/usr/bin:/bin"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME/omarchy/defaults" "$XDG_RUNTIME_DIR" "$TEMP_ROOT/bin"

cat >"$TEMP_ROOT/bin/editor-mock" <<'MOCK'
#!/bin/bash
set -euo pipefail
{
  printf '%s\n' "${0##*/}"
  printf '%s\n' "$@"
} >"$MOCK_EDITOR_LOG"
MOCK
chmod 0755 "$TEMP_ROOT/bin/editor-mock"
ln -s editor-mock "$TEMP_ROOT/bin/omarchy-launch-editor"
ln -s editor-mock "$TEMP_ROOT/bin/omarchy-launch-config-editor"
ln -s /usr/bin/true "$TEMP_ROOT/bin/omarchy"

printf 'nvim\n' >"$XDG_STATE_HOME/omarchy/defaults/editor"
"$ROOT/scripts/open-settings.sh" "$ROOT"
mapfile -t editor_call <"$MOCK_EDITOR_LOG"
[[ ${editor_call[0]} == omarchy-launch-editor ]]
[[ ${editor_call[1]} =~ ^\+[0-9]+$ ]]
[[ ${editor_call[2]} == '+normal! zz' ]]
[[ ${editor_call[3]} == "$XDG_CONFIG_HOME/omarchy/plugin-control/channels.yaml" ]]
[[ $(head -n 1 "${editor_call[3]}") == \
  '# COMMAND PALETTE KEYBINDING: CTRL+P' ]]
printf 'ok - settings helper uses fixed editor argv and the validated line\n'

marker="$TEMP_ROOT/must-not-run"
printf 'touch %s\n' "$marker" >"$XDG_STATE_HOME/omarchy/defaults/editor"
"$ROOT/scripts/open-settings.sh" "$ROOT"
[[ ! -e $marker ]]
mapfile -t editor_call <"$MOCK_EDITOR_LOG"
[[ ${editor_call[0]} == omarchy-launch-config-editor ]]
printf 'ok - editor preference cannot become a command\n'
