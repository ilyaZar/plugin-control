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
export MOCK_TERMINAL_LOG="$TEMP_ROOT/terminal-omarchy.log"
export MOCK_RUNTIME="$TEMP_ROOT/runtime-plugins.json"
export PATH="$MOCK_BIN:/usr/bin:/bin"
mkdir -p "$MOCK_BIN" "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
printf '[]\n' >"$MOCK_RUNTIME"
: >"$MOCK_LOG"
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
output_bytes="${MOCK_OUTPUT_BYTES:-0}"
if [[ $output_bytes =~ ^[0-9]+$ ]] && (( output_bytes > 0 )); then
  printf '\033[31m'
  head -c "$output_bytes" /dev/zero | tr '\0' x
  printf '\033[0m\001\n'
fi
exit "${MOCK_EXIT:-0}"
MOCK
chmod 0755 "$MOCK_BIN/omarchy"

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
  rm -f -- "$XDG_STATE_HOME/omarchy/plugin-control/snapshot.json"
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
  flock -w 5 "$XDG_RUNTIME_DIR/omarchy-plugin-control/action.lock" true
}

cache_dir="$XDG_CACHE_HOME/omarchy/plugin-control/channels"
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
rm -f -- "$XDG_STATE_HOME/omarchy/plugin-control/snapshot.json"
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

before_list_calls="$(grep -c '^plugin list --json$' "$MOCK_LOG" || true)"
helper action "$ROOT" install io.example.weather "$snapshot_id" background \
  | jq -e '.started == true' >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "install"' <<<"$status" >/dev/null
grep -Fqx 'plugin add https://github.com/example/weather --enable --yes' \
  "$MOCK_LOG"
[[ ! -e /tmp/plugin-control-must-not-run ]]
printf 'ok - native install argv ignores remote command strings\n'
wait_worker_release
after_list_calls="$(grep -c '^plugin list --json$' "$MOCK_LOG" || true)"
(( after_list_calls > before_list_calls ))
printf 'ok - successful action refreshes installed state\n'

helper action "$ROOT" install io.example.weather "$snapshot_id" terminal \
  | jq -e '.started == true' >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "install"
  and .executionMode == "terminal"' <<<"$status" >/dev/null
grep -Fqx 'plugin add https://github.com/example/weather --enable' \
  "$MOCK_TERMINAL_LOG"
if grep -F 'plugin add ' "$MOCK_TERMINAL_LOG" | grep -Fq -- '--yes'; then
  printf 'not ok - terminal install bypassed native prompts\n' >&2
  exit 1
fi
wait_worker_release
printf 'ok - terminal install streams the native interactive command\n'

if helper action "$ROOT" remove io.example.weather "$snapshot_id" terminal \
  >"$TEMP_ROOT/terminal-remove.json" 2>/dev/null; then
  printf 'not ok - terminal mode accepted a non-install action\n' >&2
  exit 1
fi
jq -e '.ok == false and (.error | contains("only for installation"))' \
  "$TEMP_ROOT/terminal-remove.json" >/dev/null
printf 'ok - terminal mode is install-only\n'

if helper action "$ROOT" install io.example.weather "$snapshot_id" \
  >"$TEMP_ROOT/missing-mode.json" 2>/dev/null; then
  printf 'not ok - action without an execution mode was accepted\n' >&2
  exit 1
fi
printf 'ok - action execution mode is explicit\n'

durable="$(helper status)"
[[ $durable == "$status" ]]
printf 'ok - completed action survives a service-style status reload\n'

if helper action "$ROOT" install io.example.weather stale-snapshot background \
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
helper action "$ROOT" install io.example.weather "$snapshot_id" background \
  >"$TEMP_ROOT/first-action.json"
sleep 0.05
if helper action "$ROOT" install io.example.weather "$snapshot_id" background \
  >"$TEMP_ROOT/duplicate.json" 2>/dev/null; then
  printf 'not ok - duplicate action was accepted\n' >&2
  exit 1
fi
jq -e '.busy == true' "$TEMP_ROOT/duplicate.json" >/dev/null
wait_action >/dev/null
unset MOCK_OMARCHY_SLEEP
printf 'ok - action locking rejects simultaneous mutations\n'

printf '[{"id":"omarchy.weather","name":"Weather",
  "kinds":["bar-widget"],"enabled":false,"firstParty":true}]\n' \
  >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
helper action "$ROOT" add-bar omarchy.weather "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "add-bar"' <<<"$status" >/dev/null
grep -Fqx 'bar put omarchy.weather' "$MOCK_LOG"
wait_worker_release
printf 'ok - native hyphenated bar widgets use the bar placement command\n'

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
  "kinds":["overlay"],"enabled":true,"firstParty":false}]\n' \
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
  "enabled":true,"firstParty":false}]\n' >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
jq -e '.records[] | select(.id == "local.test")
  | .installed == true and .removable == true and .dirty == false' \
  <<<"$snapshot" >/dev/null

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

git -C "$local_plugin" checkout -q -- Plugin.qml
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

if helper action "$ROOT" remove io.github.ilyazar.plugin-control \
  "$snapshot_id" background >"$TEMP_ROOT/self.json" 2>/dev/null; then
  printf 'not ok - self removal was accepted\n' >&2
  exit 1
fi
jq -e '.ok == false and (.error | contains("cannot remove itself"))' \
  "$TEMP_ROOT/self.json" >/dev/null
printf 'ok - self removal is refused\n'

printf '[]\n' >"$MOCK_RUNTIME"
snapshot="$(rebuild_snapshot)"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
export MOCK_OUTPUT_BYTES=20000
helper action "$ROOT" install io.example.weather "$snapshot_id" background >/dev/null
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
helper action "$ROOT" install io.example.weather "$snapshot_id" background >/dev/null
status="$(wait_action)"
jq -e '.ok == false and (.message | contains("failed"))' \
  <<<"$status" >/dev/null
wait_worker_release
if find "$XDG_STATE_HOME/omarchy/plugin-control/worker" \
  -name 'plugin-control-*' -o -name 'snapshot-*.json' | grep -q .; then
  printf 'not ok - failed action left worker staging files\n' >&2
  exit 1
fi
unset MOCK_EXIT
printf 'ok - failed action worker staging is cleaned\n'

helper ack "$(jq -r '.actionId' <<<"$status")" \
  | jq -e '.acknowledged == true' >/dev/null
printf 'ok - completed action acknowledgement\n'
