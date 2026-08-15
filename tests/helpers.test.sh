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
"$ROOT/scripts/open-channels.sh" "$ROOT"
mapfile -t editor_call <"$MOCK_EDITOR_LOG"
[[ ${editor_call[0]} == omarchy-launch-editor ]]
[[ ${editor_call[1]} =~ ^\+[0-9]+$ ]]
[[ ${editor_call[2]} == '+normal! zz' ]]
[[ ${editor_call[3]} == "$XDG_CONFIG_HOME/omarchy/plugin-control/channels.yaml" ]]
printf 'ok - channel helper uses fixed editor argv and the validated line\n'

bindings="$TEMP_ROOT/bindings.lua"
printf '%s\n' '-- bindings' 'o.bind(' '  "CTRL + P",' \
  '  "Plugin Control",' ')' >"$bindings"
printf 'code\n' >"$XDG_STATE_HOME/omarchy/defaults/editor"
"$ROOT/scripts/open-keybindings.sh" "$bindings"
mapfile -t editor_call <"$MOCK_EDITOR_LOG"
[[ ${editor_call[0]} == omarchy-launch-editor ]]
[[ ${editor_call[1]} == --goto ]]
[[ ${editor_call[2]} == "$bindings:4:1" ]]
printf 'ok - binding helper uses fixed editor argv and matched location\n'

marker="$TEMP_ROOT/must-not-run"
printf 'touch %s\n' "$marker" >"$XDG_STATE_HOME/omarchy/defaults/editor"
"$ROOT/scripts/open-keybindings.sh" "$bindings"
[[ ! -e $marker ]]
mapfile -t editor_call <"$MOCK_EDITOR_LOG"
[[ ${editor_call[0]} == omarchy-launch-config-editor ]]
printf 'ok - editor preference cannot become a command\n'
