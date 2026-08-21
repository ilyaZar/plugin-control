#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT
TEMP_ROOT="$(mktemp -d /tmp/plugin-control-backend-test.XXXXXX)"
readonly TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/config"
export XDG_CACHE_HOME="$TEMP_ROOT/cache"
export XDG_STATE_HOME="$TEMP_ROOT/state"
export XDG_RUNTIME_DIR="$TEMP_ROOT/runtime"
export MOCK_BIN="$TEMP_ROOT/bin"
export MOCK_LOG="$TEMP_ROOT/omarchy.log"
export MOCK_SHELL_LOG="$TEMP_ROOT/omarchy-shell.log"
export MOCK_TERMINAL_LOG="$TEMP_ROOT/terminal-omarchy.log"
export MOCK_RUNTIME="$TEMP_ROOT/runtime-plugins.json"
export PATH="$MOCK_BIN:/usr/bin:/bin"
mkdir -p "$MOCK_BIN" "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
printf '[]\n' >"$MOCK_RUNTIME"
: >"$MOCK_LOG"
: >"$MOCK_SHELL_LOG"
: >"$MOCK_TERMINAL_LOG"

cat >"$MOCK_BIN/omarchy" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_LOG"
if [[ ${MOCK_TERMINAL_CAPTURE:-0} == 1 ]]; then
  printf '%s\n' "$*" >>"$MOCK_TERMINAL_LOG"
fi
if [[ $* == "plugin list --json" ]]; then
  if [[ ${MOCK_LIST_SLEEP:-0} != 0 ]]; then
    sleep "$MOCK_LIST_SLEEP"
  fi
  cat "$MOCK_RUNTIME"
  exit 0
fi
if [[ ${MOCK_OMARCHY_SLEEP:-0} != 0 ]]; then
  sleep "$MOCK_OMARCHY_SLEEP"
fi
if [[ $* == "plugin remove io.github.ilyazar.plugin-control --yes" \
    && -n ${MOCK_REMOVE_PATH:-} ]]; then
  mv -T -- "$MOCK_REMOVE_PATH" "$MOCK_REMOVE_PATH.removed"
fi
output_bytes="${MOCK_OUTPUT_BYTES:-0}"
if [[ $output_bytes =~ ^[0-9]+$ ]] && (( output_bytes > 0 )); then
  printf '\033[31m'
  head -c "$output_bytes" /dev/zero | tr '\0' x
  printf '\033[0m\001\n'
fi
exit "${MOCK_EXIT:-0}"
MOCK
chmod 0755 "$MOCK_BIN/omarchy"

cat >"$MOCK_BIN/omarchy-shell" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_SHELL_LOG"
MOCK
chmod 0755 "$MOCK_BIN/omarchy-shell"

cat >"$MOCK_BIN/omarchy-launch-terminal" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf 'launch-terminal %s\n' "$*" >>"$MOCK_LOG"
export MOCK_TERMINAL_CAPTURE=1
"$@" <<<''
MOCK
chmod 0755 "$MOCK_BIN/omarchy-launch-terminal"

helper() {
  "$ROOT/bin/plugin-control" "$@"
}

rebuild_snapshot() {
  rm -f -- "$XDG_STATE_HOME/omarchy/ilyazar.plugin-control/snapshot.json"
  helper cached "$ROOT"
}

wait_action() {
  local deadline=$((SECONDS + 10)) status
  while (( SECONDS < deadline )); do
    status="$(helper status)"
    if ! jq -e '.running == true' <<<"$status" >/dev/null; then
      printf '%s\n' "$status"
      return
    fi
    sleep 0.05
  done
  printf 'action did not finish\n' >&2
  return 1
}

wait_worker_release() {
  flock -w 5 "$XDG_RUNTIME_DIR/omarchy-ilyazar.plugin-control/action.lock" true
}

helper help | grep -Fq \
  'plugin-control start [--tray-hidden | --tray-visible]'
jq -cn '
  {
    id: "io.github.ilyazar.plugin-control",
    name: "Plugin Control",
    kinds: ["service", "overlay", "bar-widget"],
    enabled: false
  } | [.]
' >"$MOCK_RUNTIME"

helper start --tray-hidden | grep -Fq 'tray icon hidden'
grep -Fqx 'shell rescanPlugins' "$MOCK_SHELL_LOG"
grep -Fqx 'plugin enable io.github.ilyazar.plugin-control' "$MOCK_LOG"
grep -Fqx 'bar set io.github.ilyazar.plugin-control trayIconHidden true --json' \
  "$MOCK_LOG"

helper start | grep -Fq 'tray icon visible'
grep -Fqx 'bar set io.github.ilyazar.plugin-control trayIconHidden false --json' \
  "$MOCK_LOG"

sed -i 's/tray-icon-hidden: false/tray-icon-hidden: true/' \
  "$XDG_CONFIG_HOME/omarchy/ilyazar.plugin-control/channels.yaml"
helper start | grep -Fq 'tray icon hidden'
helper start --tray-visible | grep -Fq 'tray icon visible'

before_invalid_start="$(wc -l <"$MOCK_LOG")"
if helper start --tray-hidden --tray-visible >/dev/null 2>&1; then
  printf 'not ok - conflicting tray flags were accepted\n' >&2
  exit 1
fi
[[ $(wc -l <"$MOCK_LOG") == "$before_invalid_start" ]]

helper stop | grep -Fq 'Plugin Control stopped'
grep -Fqx 'plugin disable io.github.ilyazar.plugin-control' "$MOCK_LOG"
if helper stop --tray-hidden >/dev/null 2>&1; then
  printf 'not ok - stop accepted a tray flag\n' >&2
  exit 1
fi
printf 'ok - public lifecycle CLI follows native flags and tray defaults\n'

printf '[]\n' >"$MOCK_RUNTIME"

cache_dir="$XDG_CACHE_HOME/omarchy/ilyazar.plugin-control/channels"
mkdir -p "$cache_dir"
cp "$TEST_DIR/fixtures/catalog-action.json" "$cache_dir/marketplace.json"

snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
jq -e '.ok == true and (.records | length) >= 1' <<<"$snapshot" >/dev/null
printf 'ok - cache-backed snapshot\n'

cached_list_calls="$(grep -c '^plugin list --json$' "$MOCK_LOG" || true)"
cached_again="$(helper cached "$ROOT")"
[[ $(jq -r '.snapshotId' <<<"$cached_again") == "$snapshot_id" ]]
[[ $(grep -c '^plugin list --json$' "$MOCK_LOG" || true) \
  == "$cached_list_calls" ]]
printf 'ok - warm cache read skips native and Git refresh work\n'

export MOCK_LIST_SLEEP=0.3
rm -f -- "$XDG_STATE_HOME/omarchy/ilyazar.plugin-control/snapshot.json"
snapshot_started="$(date +%s%3N)"
helper cached "$ROOT" >"$TEMP_ROOT/snapshot-one.json" &
snapshot_pid_one=$!
helper cached "$ROOT" >"$TEMP_ROOT/snapshot-two.json" &
snapshot_pid_two=$!
wait "$snapshot_pid_one" "$snapshot_pid_two"
snapshot_elapsed=$(( $(date +%s%3N) - snapshot_started ))
(( snapshot_elapsed >= 500 ))
jq -e '.ok == true' "$TEMP_ROOT/snapshot-one.json" >/dev/null
jq -e '.ok == true' "$TEMP_ROOT/snapshot-two.json" >/dev/null
unset MOCK_LIST_SLEEP
printf 'ok - concurrent snapshot builds are serialized\n'

jq -cn '{ok:true,records:[range(0;400) as $number
  | {id:("io.example.large-" + ($number | tostring)),
      name:("Large plugin " + ($number | tostring)),
      description:("x" * 600),source:"marketplace",sourceRank:20,
      marketplaceListed:true,repository:"https://github.com/example/large"}]}' \
  >"$cache_dir/marketplace.json"
rm -f -- "$XDG_STATE_HOME/omarchy/ilyazar.plugin-control/snapshot.json"
large_snapshot="$(helper cached "$ROOT")"
jq -e '(.records | length) >= 400
  and any(.records[]; .id == "io.example.large-399")' \
  <<<"$large_snapshot" >/dev/null
printf 'ok - large snapshots avoid argument-size limits\n'

cp "$TEST_DIR/fixtures/catalog-action.json" "$cache_dir/marketplace.json"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"

snapshot_state="$XDG_STATE_HOME/omarchy/ilyazar.plugin-control/snapshot.json"
cp "$snapshot_state" "$TEMP_ROOT/current-snapshot.json"
jq '.config.version = 1' "$snapshot_state" >"$snapshot_state.tmp"
mv "$snapshot_state.tmp" "$snapshot_state"
if helper action "$ROOT" add io.example.weather "$snapshot_id" background \
  >"$TEMP_ROOT/legacy-action.json" 2>/dev/null; then
  printf 'not ok - legacy snapshot reached an action\n' >&2
  exit 1
fi
jq -e '.ok == false and (.error | contains("changed"))' \
  "$TEMP_ROOT/legacy-action.json" >/dev/null
mv "$TEMP_ROOT/current-snapshot.json" "$snapshot_state"
printf 'ok - legacy snapshots cannot authorize actions\n'

if helper action "$ROOT" install io.example.weather "$snapshot_id" background \
  >"$TEMP_ROOT/old-operation.json" 2>/dev/null; then
  printf 'not ok - superseded install operation was accepted\n' >&2
  exit 1
fi
jq -e '.ok == false and (.error | contains("unsupported"))' \
  "$TEMP_ROOT/old-operation.json" >/dev/null
printf 'ok - backend accepts only the canonical add operation\n'

before_list_calls="$(grep -c '^plugin list --json$' "$MOCK_LOG" || true)"
helper action "$ROOT" add io.example.weather "$snapshot_id" background \
  | jq -e '.started == true' >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "add"' <<<"$status" >/dev/null
grep -Fqx 'plugin add https://github.com/example/weather --enable --yes' \
  "$MOCK_LOG"
[[ ! -e /tmp/plugin-control-must-not-run ]]
printf 'ok - native add argv ignores remote command strings\n'
wait_worker_release
after_list_calls="$(grep -c '^plugin list --json$' "$MOCK_LOG" || true)"
(( after_list_calls > before_list_calls ))
printf 'ok - successful action refreshes installed state\n'

helper action "$ROOT" add io.example.weather "$snapshot_id" terminal \
  | jq -e '.started == true' >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "add"
  and .executionMode == "terminal"' <<<"$status" >/dev/null
grep -Fqx 'plugin add https://github.com/example/weather --enable' \
  "$MOCK_TERMINAL_LOG"
if grep -F 'plugin add ' "$MOCK_TERMINAL_LOG" | grep -Fq -- '--yes'; then
  printf 'not ok - terminal add bypassed native prompts\n' >&2
  exit 1
fi
wait_worker_release
printf 'ok - terminal add streams the native interactive command\n'

if helper action "$ROOT" remove io.example.weather "$snapshot_id" terminal \
  >"$TEMP_ROOT/terminal-remove.json" 2>/dev/null; then
  printf 'not ok - terminal mode accepted a non-add action\n' >&2
  exit 1
fi
jq -e '.ok == false and (.error | contains("only when adding"))' \
  "$TEMP_ROOT/terminal-remove.json" >/dev/null
printf 'ok - terminal mode is add-only\n'

if helper action "$ROOT" add io.example.weather "$snapshot_id" \
  >"$TEMP_ROOT/missing-mode.json" 2>/dev/null; then
  printf 'not ok - action without an execution mode was accepted\n' >&2
  exit 1
fi
printf 'ok - action execution mode is explicit\n'

durable="$(helper status)"
[[ $durable == "$status" ]]
printf 'ok - completed action survives a service-style status reload\n'

if helper action "$ROOT" add io.example.weather stale-snapshot background \
  >"$TEMP_ROOT/stale.json" 2>/dev/null; then
  printf 'not ok - stale confirmation was accepted\n' >&2
  exit 1
fi
jq -e '.ok == false and (.error | contains("changed"))' \
  "$TEMP_ROOT/stale.json" >/dev/null
printf 'ok - confirmation snapshot mismatch is rejected\n'

if helper action "$ROOT" remove ../outside "$snapshot_id" background \
  >"$TEMP_ROOT/path.json" 2>/dev/null; then
  printf 'not ok - unsafe plugin ID was accepted\n' >&2
  exit 1
fi
jq -e '.ok == false and (.error | contains("valid plugin ID"))' \
  "$TEMP_ROOT/path.json" >/dev/null
printf 'ok - unsafe plugin IDs cannot escape the plugin directory\n'

sleep 0.1
export MOCK_OMARCHY_SLEEP=1
helper action "$ROOT" add io.example.weather "$snapshot_id" background \
  >"$TEMP_ROOT/first-action.json"
sleep 0.05
if helper action "$ROOT" add io.example.weather "$snapshot_id" background \
  >"$TEMP_ROOT/duplicate.json" 2>/dev/null; then
  printf 'not ok - duplicate action was accepted\n' >&2
  exit 1
fi
jq -e '.busy == true' "$TEMP_ROOT/duplicate.json" >/dev/null
wait_action >/dev/null
unset MOCK_OMARCHY_SLEEP
printf 'ok - action locking rejects simultaneous mutations\n'

printf '[{"id":"omarchy.weather","name":"Weather",
  "kinds":["bar-widget"],"enabled":false,"canDisable":true,
  "firstParty":true}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
jq -e '.records[] | select(.id == "omarchy.weather")
  | .builtIn == true and .canDisable == true and .enabled == false' \
  <<<"$snapshot" >/dev/null
helper action "$ROOT" enable omarchy.weather "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "enable"' <<<"$status" >/dev/null
grep -Fqx 'plugin enable omarchy.weather' "$MOCK_LOG"
if grep -Fqx 'bar put omarchy.weather' "$MOCK_LOG"; then
  printf 'not ok - bar widget enable used the placement command\n' >&2
  exit 1
fi
wait_worker_release
printf 'ok - bar widgets use native plugin enable\n'

printf '[{"id":"omarchy.bar","name":"Bar","kinds":["bar"],
  "enabled":true,"canDisable":false,"firstParty":true}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
helper action "$ROOT" disable omarchy.bar "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == false and (.message | contains("does not support"))' \
  <<<"$status" >/dev/null
if grep -Fqx 'plugin disable omarchy.bar' "$MOCK_LOG"; then
  printf 'not ok - non-switchable plugin reached native disable\n' >&2
  exit 1
fi
wait_worker_release
printf 'ok - runtime switchability gates state actions\n'

printf '[{"id":"omarchy.bar","name":"Bar","kinds":["bar"],
  "enabled":false,"canDisable":false,"firstParty":true}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
helper action "$ROOT" enable omarchy.bar "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "enable"' <<<"$status" >/dev/null
grep -Fqx 'plugin enable omarchy.bar' "$MOCK_LOG"
wait_worker_release
printf 'ok - inactive full bars use native plugin enable\n'

plugins_root="$XDG_CONFIG_HOME/omarchy/plugins"
weather_local="$plugins_root/io.example.weather"
mkdir -p "$weather_local"
cat >"$weather_local/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "io.example.weather",
  "name": "Local Weather",
  "version": "2.0.0",
  "author": "Local",
  "description": "Local checkout",
  "kinds": ["overlay"],
  "entryPoints": {"overlay":"Plugin.qml"}
}
JSON
printf 'import QtQuick\nItem {}\n' >"$weather_local/Plugin.qml"
git -C "$weather_local" init -q
git -C "$weather_local" add .
git -C "$weather_local" -c user.name=Test -c user.email=test@example.invalid \
  commit -qm initial
git -C "$weather_local" remote add origin \
  https://github.com/local/weather
printf '[{"id":"io.example.weather","name":"Local Weather",
  "kinds":["overlay"],"enabled":true,"canDisable":true,
  "firstParty":false}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
jq -e '.records[] | select(.id == "io.example.weather")
  | .source == "local" and .installed == true and .installable == false
    and .marketplaceListed == true
    and .repository == "https://github.com/local/weather"' \
  <<<"$snapshot" >/dev/null
jq -e '.diagnostics[] | select(.type == "repository-collision"
  and .id == "io.example.weather")' <<<"$snapshot" >/dev/null
rm -rf -- "$weather_local"
printf 'ok - installed records override upstream action metadata\n'

local_plugin="$plugins_root/local.test"
mkdir -p "$local_plugin"
cat >"$local_plugin/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "local.test",
  "name": "Local Test",
  "version": "1.0.0",
  "author": "Test",
  "description": "Local test plugin",
  "kinds": ["overlay"],
  "entryPoints": {"overlay":"Plugin.qml"}
}
JSON
printf 'import QtQuick\nItem {}\n' >"$local_plugin/Plugin.qml"
git -C "$local_plugin" init -q
git -C "$local_plugin" add .
git -C "$local_plugin" -c user.name=Test -c user.email=test@example.invalid \
  commit -qm initial
printf '[{"id":"local.test","name":"Local Test","kinds":["overlay"],
  "enabled":true,"canDisable":true,"firstParty":false}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
jq -e '.records[] | select(.id == "local.test")
  | .installed == true and .removable == true and .dirty == false
    and .canDisable == true and .enabled == true' \
  <<<"$snapshot" >/dev/null

helper action "$ROOT" disable local.test "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "disable"
  and .message == "Plugin Local Test disabled."' \
  <<<"$status" >/dev/null
grep -Fqx 'plugin disable local.test' "$MOCK_LOG"
wait_worker_release

printf '[{"id":"local.test","name":"Local Test","kinds":["overlay"],
  "enabled":false,"canDisable":true,"firstParty":false}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
helper action "$ROOT" enable local.test "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "enable"
  and .message == "Plugin Local Test enabled."' \
  <<<"$status" >/dev/null
grep -Fqx 'plugin enable local.test' "$MOCK_LOG"
wait_worker_release
printf 'ok - third-party plugins use native enable and disable actions\n'

printf '[{"id":"local.test","name":"Local Test","kinds":["overlay"],
  "enabled":true,"canDisable":true,"firstParty":false}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"

printf 'dirty\n' >>"$local_plugin/Plugin.qml"
helper action "$ROOT" remove local.test "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == false and (.message | contains("local changes"))' \
  <<<"$status" >/dev/null
if grep -Fqx 'plugin remove local.test --yes' "$MOCK_LOG"; then
  printf 'not ok - dirty checkout reached native removal\n' >&2
  exit 1
fi
printf 'ok - dirty checkout removal is refused\n'

worktree_seed="$TEMP_ROOT/worktree-remove-seed"
worktree_plugin="$plugins_root/worktree.test"
mkdir -p "$worktree_seed"
cat >"$worktree_seed/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "worktree.test",
  "name": "Worktree Test",
  "version": "1.0.0",
  "author": "Test",
  "description": "Removal worktree fixture",
  "kinds": ["overlay"],
  "entryPoints": {"overlay":"Plugin.qml"}
}
JSON
printf 'import QtQuick\nItem {}\n' >"$worktree_seed/Plugin.qml"
git -C "$worktree_seed" init -q
git -C "$worktree_seed" add .
git -C "$worktree_seed" -c user.name=Test \
  -c user.email=test@example.invalid commit -qm initial
git -C "$worktree_seed" worktree add -q --detach "$worktree_plugin" HEAD
printf 'dirty\n' >>"$worktree_plugin/Plugin.qml"
printf '[{"id":"worktree.test","name":"Worktree Test","kinds":["overlay"],
  "enabled":true,"canDisable":true,"firstParty":false}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
helper action "$ROOT" remove worktree.test "$snapshot_id" background \
  >/dev/null
status="$(wait_action)"
jq -e '.ok == false and (.message | contains("local changes"))' \
  <<<"$status" >/dev/null
if grep -Fqx 'plugin remove worktree.test --yes' "$MOCK_LOG"; then
  printf 'not ok - dirty Git worktree reached native removal\n' >&2
  exit 1
fi
printf 'ok - dirty Git worktree removal is refused\n'

git -C "$local_plugin" checkout -q -- Plugin.qml
printf '[{"id":"local.test","name":"Local Test","kinds":["overlay"],
  "enabled":true,"canDisable":true,"firstParty":false}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
helper action "$ROOT" remove local.test "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "remove"' <<<"$status" >/dev/null
grep -Fqx 'plugin remove local.test --yes' "$MOCK_LOG"
wait_worker_release
printf 'ok - native remove argv uses the confirmed plugin ID\n'

snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
jq '.id="changed.identity"' "$local_plugin/manifest.json" \
  >"$local_plugin/manifest.json.tmp"
mv "$local_plugin/manifest.json.tmp" "$local_plugin/manifest.json"
helper action "$ROOT" remove local.test "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == false and (.message | contains("identity or path changed"))' \
  <<<"$status" >/dev/null
printf 'ok - changed manifest identity is refused\n'

self_plugin="$plugins_root/io.github.ilyazar.plugin-control"
mkdir -p "$self_plugin/lib" "$self_plugin/config" "$self_plugin/bootstrap"
cp "$ROOT/manifest.json" "$self_plugin/manifest.json"
cp "$ROOT/lib/catalog.jq" "$ROOT/lib/channel_config.rb" "$self_plugin/lib/"
cp "$ROOT/config/channels.yaml" "$self_plugin/config/channels.yaml"
cp "$ROOT/bootstrap/catalog.json" "$self_plugin/bootstrap/catalog.json"
printf '[{"id":"io.github.ilyazar.plugin-control","name":"Plugin Control",\n  "kinds":["service","overlay","bar-widget"],\n  "enabled":true,"firstParty":false}]\n' >"$MOCK_RUNTIME"
rm -f -- "$snapshot_state"
snapshot="$(helper cached "$self_plugin")"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
jq -e '.records[] | select(.id == "io.github.ilyazar.plugin-control")
  | .installed == true and .removable == true and .dirty == false' \
  <<<"$snapshot" >/dev/null
export MOCK_REMOVE_PATH="$self_plugin"
helper action "$self_plugin" remove io.github.ilyazar.plugin-control \
  "$snapshot_id" background >/dev/null
status="$(wait_action)"
wait_worker_release
jq -e '.ok == true and .operation == "remove"
  and .pluginId == "io.github.ilyazar.plugin-control"
  and .acknowledged == true' <<<"$status" >/dev/null
grep -Fqx \
  'plugin remove io.github.ilyazar.plugin-control --yes' "$MOCK_LOG"
[[ ! -e $self_plugin && -d $self_plugin.removed && ! -e $snapshot_state ]]
[[ -f $XDG_CONFIG_HOME/omarchy/ilyazar.plugin-control/channels.yaml
  && -f $XDG_STATE_HOME/omarchy/ilyazar.plugin-control/channels.json
  && -f $XDG_CACHE_HOME/omarchy/ilyazar.plugin-control/channels/marketplace.json
  && -f $XDG_STATE_HOME/omarchy/ilyazar.plugin-control/action.json
  && -f $XDG_STATE_HOME/omarchy/ilyazar.plugin-control/action.log ]]
if find "$XDG_STATE_HOME/omarchy/ilyazar.plugin-control/worker" \
  \( -name 'plugin-control-*' -o -name 'snapshot-*.json' \) | grep -q .; then
  printf 'not ok - self removal left worker staging files\n' >&2
  exit 1
fi
unset MOCK_REMOVE_PATH
printf 'ok - self removal survives checkout deletion and keeps user state\n'

mv -T -- "$self_plugin.removed" "$self_plugin"
rm -f -- "$snapshot_state"
snapshot="$(helper cached "$self_plugin")"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
export MOCK_REMOVE_PATH="$self_plugin"
export MOCK_EXIT=1
helper action "$self_plugin" remove io.github.ilyazar.plugin-control \
  "$snapshot_id" background >/dev/null
status="$(wait_action)"
wait_worker_release
jq -e '.ok == true and .acknowledged == true
  and (.message | contains("shell refresh error"))' <<<"$status" >/dev/null
[[ ! -e $self_plugin && -d $self_plugin.removed && ! -e $snapshot_state ]]
unset MOCK_REMOVE_PATH MOCK_EXIT
printf 'ok - deleted self checkout survives a final native rescan error\n'

mv -T -- "$self_plugin.removed" "$self_plugin"
rm -f -- "$snapshot_state"
snapshot="$(helper cached "$self_plugin")"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
export MOCK_EXIT=1
helper action "$self_plugin" remove io.github.ilyazar.plugin-control \
  "$snapshot_id" background >/dev/null
status="$(wait_action)"
wait_worker_release
jq -e '.ok == false and .acknowledged == false
  and (.message | contains("failed with exit code 1"))' <<<"$status" >/dev/null
[[ -d $self_plugin && -f $snapshot_state ]]
unset MOCK_EXIT
printf 'ok - failed self removal keeps its checkout and snapshot\n'

mkdir -p "$self_plugin/scripts" "$XDG_CONFIG_HOME/hypr"
cp "$ROOT/scripts/remove-keybinding.rb" "$self_plugin/scripts/"
touch "$XDG_CONFIG_HOME/omarchy/ilyazar.plugin-control/purge-config" \
  "$XDG_CACHE_HOME/omarchy/ilyazar.plugin-control/purge-cache" \
  "$XDG_STATE_HOME/omarchy/ilyazar.plugin-control/purge-state"
cat >"$XDG_CONFIG_HOME/hypr/bindings.lua" <<'LUA'
o.bind(
  "CTRL + P",
  "Plugin Control",
  "omarchy-shell shell toggle io.github.ilyazar.plugin-control '{}'"
)

o.bind("SUPER + T", "Terminal", "omarchy-launch-terminal")
LUA
rm -f -- "$snapshot_state"
snapshot="$(helper cached "$self_plugin")"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
export MOCK_REMOVE_PATH="$self_plugin"
started="$(helper action "$self_plugin" remove-purge \
  io.github.ilyazar.plugin-control "$snapshot_id" background)"
purge_pid="$(jq -r '.pid' <<<"$started")"
deadline=$((SECONDS + 10))
while [[ -e $self_plugin && $SECONDS -lt $deadline ]]; do
  sleep 0.05
done
while kill -0 "$purge_pid" 2>/dev/null && (( SECONDS < deadline )); do
  sleep 0.05
done
[[ ! -e $self_plugin && -d $self_plugin.removed ]]
[[ ! -e $XDG_CONFIG_HOME/omarchy/ilyazar.plugin-control
  && ! -e $XDG_CACHE_HOME/omarchy/ilyazar.plugin-control
  && ! -e $XDG_STATE_HOME/omarchy/ilyazar.plugin-control
  && ! -e $XDG_RUNTIME_DIR/omarchy-ilyazar.plugin-control ]]
grep -Fq 'omarchy-launch-terminal' "$XDG_CONFIG_HOME/hypr/bindings.lua"
if grep -Fq 'io.github.ilyazar.plugin-control' \
  "$XDG_CONFIG_HOME/hypr/bindings.lua"; then
  printf 'not ok - clean removal left the Plugin Control binding\n' >&2
  exit 1
fi
unset MOCK_REMOVE_PATH
printf 'ok - clean removal purges namespaced data and its keybinding\n'

printf '[]\n' >"$MOCK_RUNTIME"
mkdir -p "$cache_dir"
cp "$TEST_DIR/fixtures/catalog-action.json" "$cache_dir/marketplace.json"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
export MOCK_OUTPUT_BYTES=20000
helper action "$ROOT" add io.example.weather "$snapshot_id" background >/dev/null
status="$(wait_action)"
output_length="$(jq -r '.output | length' <<<"$status")"
(( output_length <= 12000 ))
if ! jq -e '.output | index("\u001b") == null and index("\u0001") == null' \
  <<<"$status" >/dev/null; then
  printf 'not ok - action output retained control characters\n' >&2
  exit 1
fi
unset MOCK_OUTPUT_BYTES
printf 'ok - action output is sanitized and bounded\n'

wait_worker_release
export MOCK_EXIT=1
helper action "$ROOT" add io.example.weather "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == false and (.message | contains("failed"))' \
  <<<"$status" >/dev/null
wait_worker_release
if find "$XDG_STATE_HOME/omarchy/ilyazar.plugin-control/worker" \
  -name 'plugin-control-*' -o -name 'snapshot-*.json' | grep -q .; then
  printf 'not ok - failed action left worker staging files\n' >&2
  exit 1
fi
unset MOCK_EXIT
printf 'ok - failed action worker staging is cleaned\n'

helper ack "$(jq -r '.actionId' <<<"$status")" \
  | jq -e '.acknowledged == true' >/dev/null
printf 'ok - completed action acknowledgement\n'
