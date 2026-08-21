#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT
TEMP_ROOT="$(mktemp -d /tmp/plugin-control-updates-test.XXXXXX)"
readonly TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/config"
export XDG_CACHE_HOME="$TEMP_ROOT/cache"
export XDG_STATE_HOME="$TEMP_ROOT/state"
export XDG_RUNTIME_DIR="$TEMP_ROOT/runtime"
export MOCK_BIN="$TEMP_ROOT/bin"
export MOCK_LOG="$TEMP_ROOT/omarchy.log"
export MOCK_RUNTIME="$TEMP_ROOT/runtime-plugins.json"
export PATH="$MOCK_BIN:/usr/bin:/bin"
mkdir -p "$MOCK_BIN" "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
  "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
: >"$MOCK_LOG"
printf '[]\n' >"$MOCK_RUNTIME"

cat >"$MOCK_BIN/omarchy" <<'MOCK'
#!/bin/bash
set -euo pipefail
if [[ $* == "plugin list --json" ]]; then
  cat "$MOCK_RUNTIME"
  exit 0
fi
printf '%s\n' "$*" >>"$MOCK_LOG"
exit "${MOCK_EXIT:-0}"
MOCK
chmod 0755 "$MOCK_BIN/omarchy"

# Backend functions use the isolated environment above.
# shellcheck disable=SC1090
source "$ROOT/bin/plugin-control"
init_paths

helper() {
  "$ROOT/bin/plugin-control" "$@"
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

write_plugin() {
  local path="$1"
  local id="$2"
  mkdir -p "$path"
  jq -n --arg id "$id" '{schemaVersion:1,id:$id,name:$id,
    version:"1.0.0",author:"Test",description:"Update fixture",
    kinds:["overlay"],entryPoints:{overlay:"Plugin.qml"}}' \
    >"$path/manifest.json"
  printf 'import QtQuick\nItem {}\n' >"$path/Plugin.qml"
}

make_checkout() {
  local id="$1"
  local origin="$TEMP_ROOT/remotes/$id.git"
  local seed="$TEMP_ROOT/seeds/$id"
  local checkout="$PLUGINS_ROOT/$id"
  mkdir -p "$TEMP_ROOT/remotes" "$TEMP_ROOT/seeds" "$PLUGINS_ROOT"
  git init -q --bare "$origin"
  git init -q "$seed"
  write_plugin "$seed" "$id"
  git -C "$seed" add .
  git -C "$seed" -c user.name=Test -c user.email=test@example.invalid \
    commit -qm initial
  git -C "$seed" remote add origin "$origin"
  git -C "$seed" push -q -u origin HEAD:main
  git --git-dir="$origin" symbolic-ref HEAD refs/heads/main
  git clone -q "$origin" "$checkout"
}

advance_remote() {
  local id="$1"
  local text="$2"
  local seed="$TEMP_ROOT/seeds/$id"
  printf '%s\n' "$text" >>"$seed/Plugin.qml"
  git -C "$seed" add Plugin.qml
  git -C "$seed" -c user.name=Test -c user.email=test@example.invalid \
    commit -qm "$text"
  git -C "$seed" push -q origin HEAD:main
}

commit_local() {
  local id="$1"
  local text="$2"
  local checkout="$PLUGINS_ROOT/$id"
  printf '%s\n' "$text" >>"$checkout/Plugin.qml"
  git -C "$checkout" add Plugin.qml
  git -C "$checkout" -c user.name=Test -c user.email=test@example.invalid \
    commit -qm "$text"
}

ids=(test.current test.available test.ahead test.diverged test.dirty \
  test.fetchfail)
for id in "${ids[@]}"; do
  make_checkout "$id"
done
write_plugin "$PLUGINS_ROOT/test.manual" test.manual
mkdir -p "$PLUGINS_ROOT/test.parent-repo"
git init -q "$PLUGINS_ROOT/test.parent-repo"
write_plugin "$PLUGINS_ROOT/test.parent-repo/test.nested-manual" \
  test.nested-manual
git -C "$TEMP_ROOT/seeds/test.current" worktree add -q --detach \
  "$PLUGINS_ROOT/test.worktree" HEAD

advance_remote test.available remote-ahead
commit_local test.ahead local-ahead
commit_local test.diverged local-diverged
advance_remote test.diverged remote-diverged
printf 'dirty\n' >>"$PLUGINS_ROOT/test.dirty/Plugin.qml"
git -C "$PLUGINS_ROOT/test.fetchfail" remote set-url origin \
  "$TEMP_ROOT/missing.git"

jq -n --args '$ARGS.positional | map({id:.,name:.,kinds:["overlay"],
  enabled:true,canDisable:true,firstParty:false})' \
  "${ids[@]}" test.manual >"$MOCK_RUNTIME"

jq -e '.status == "current" and .updateAvailable == false' \
  <<<"$(classify_plugin_update test.current \
    "$PLUGINS_ROOT/test.current")" >/dev/null
jq -e '.status == "available" and .updateAvailable == true' \
  <<<"$(classify_plugin_update test.available \
    "$PLUGINS_ROOT/test.available")" >/dev/null
jq -e '.status == "ahead" and .updateAvailable == false' \
  <<<"$(classify_plugin_update test.ahead \
    "$PLUGINS_ROOT/test.ahead")" >/dev/null
jq -e '.status == "diverged" and .updateAvailable == false' \
  <<<"$(classify_plugin_update test.diverged \
    "$PLUGINS_ROOT/test.diverged")" >/dev/null
jq -e '.status == "dirty" and .dirty == true' \
  <<<"$(classify_plugin_update test.dirty \
    "$PLUGINS_ROOT/test.dirty")" >/dev/null
jq -e --arg reason "$MANUAL_UPDATE_REASON" \
  '.status == "manual" and .gitManaged == false and .reason == $reason' \
  <<<"$(classify_plugin_update test.manual \
    "$PLUGINS_ROOT/test.manual")" >/dev/null
jq -e --arg reason "$MANUAL_UPDATE_REASON" \
  '.status == "manual" and .gitManaged == false and .reason == $reason' \
  <<<"$(classify_plugin_update test.nested-manual \
    "$PLUGINS_ROOT/test.parent-repo/test.nested-manual")" >/dev/null
jq -e --arg reason "$UNSUPPORTED_UPDATE_REASON" \
  '.status == "unsupported" and .gitManaged == true and .reason == $reason' \
  <<<"$(classify_plugin_update test.worktree \
    "$PLUGINS_ROOT/test.worktree")" >/dev/null
if classify_plugin_update test.fetchfail \
    "$PLUGINS_ROOT/test.fetchfail" >"$TEMP_ROOT/fetch-failure.json"; then
  printf 'not ok - failed fetch was classified as successful\n' >&2
  exit 1
fi
jq -e '.status == "error" and (.reason | contains("Fetching"))' \
  "$TEMP_ROOT/fetch-failure.json" >/dev/null
printf 'ok - update classification covers safe and unsafe Git states\n'

if ! helper check-updates "$ROOT" >"$TEMP_ROOT/partial.json"; then
  printf 'not ok - warning update check reported failure\n' >&2
  exit 1
fi
jq -e '.updates.lastSuccessfulCheck != ""
  and .updates.lastCheckError == ""
  and .updates.counts.failed == 1
  and any(.records[]; .id == "test.fetchfail"
    and .updateStatus == "error"
    and (.updateReason | contains("Fetching")))
  and any(.records[]; .id == "test.available"
    and .updateAvailable == true)
  and all(.records[]; .id != "test.ahead" or .updateAvailable == false)
  and all(.records[]; .id != "test.diverged" or .updateAvailable == false)' \
  "$TEMP_ROOT/partial.json" >/dev/null
printf 'ok - warning checks retain actionable results and complete normally\n'

git -C "$PLUGINS_ROOT/test.fetchfail" remote set-url origin \
  "$TEMP_ROOT/remotes/test.fetchfail.git"
helper check-updates "$ROOT" >"$TEMP_ROOT/complete.json"
successful_at="$(jq -r '.updates.lastSuccessfulCheck' \
  "$TEMP_ROOT/complete.json")"
[[ -n $successful_at ]]
jq -e '.updates.lastCheckError == ""
  and .updates.counts.available == 1
  and .updates.counts.manual == 1
  and .updates.counts.dirty == 1
  and .updates.counts.ahead == 1
  and .updates.counts.diverged == 1
  and (.updates.lastCheckNotice | contains("dirty"))' \
  "$TEMP_ROOT/complete.json" >/dev/null
printf 'ok - full checks record timestamps and exclusion counts\n'

git -C "$PLUGINS_ROOT/test.current" remote set-url origin \
  "$TEMP_ROOT/missing-again.git"
if ! helper check-updates "$ROOT" >"$TEMP_ROOT/later-partial.json"; then
  printf 'not ok - later warning update check reported failure\n' >&2
  exit 1
fi
jq -e \
  '.updates.lastSuccessfulCheck != ""
    and .updates.lastCheckError == ""
    and .updates.counts.failed == 1' \
  "$TEMP_ROOT/later-partial.json" >/dev/null
git -C "$PLUGINS_ROOT/test.current" remote set-url origin \
  "$TEMP_ROOT/remotes/test.current.git"
printf 'ok - later warning checks advance the successful timestamp\n'

plugin_lock="$(plugin_lock_path test.current)"
# $1 belongs to the child shell.
# shellcheck disable=SC2016
flock "$plugin_lock" bash -c \
  'touch "$1"; sleep 0.4' bash "$TEMP_ROOT/plugin-lock-ready" &
lock_pid=$!
while [[ ! -e $TEMP_ROOT/plugin-lock-ready ]]; do sleep 0.01; done
started="$(date +%s%3N)"
check_plugin_update test.current "$PLUGINS_ROOT/test.current" \
  "$TEMP_ROOT/locked-check.json"
elapsed=$(( $(date +%s%3N) - started ))
wait "$lock_pid"
(( elapsed >= 300 ))
jq -e '.status == "current"' "$TEMP_ROOT/locked-check.json" >/dev/null

# $1 belongs to the child shell.
# shellcheck disable=SC2016
flock "$ACTION_LOCK" bash -c \
  'touch "$1"; sleep 0.4' bash "$TEMP_ROOT/action-lock-ready" &
action_lock_pid=$!
while [[ ! -e $TEMP_ROOT/action-lock-ready ]]; do sleep 0.01; done
if helper check-updates "$ROOT" >"$TEMP_ROOT/busy-check.json" 2>/dev/null; then
  printf 'not ok - update check raced an active action lock\n' >&2
  exit 1
fi
wait "$action_lock_pid"
jq -e '.ok == false and (.error | contains("action"))' \
  "$TEMP_ROOT/busy-check.json" >/dev/null
printf 'ok - per-plugin and action locks prevent check races\n'

snapshot="$(helper cached "$ROOT")"
snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
: >"$MOCK_LOG"
helper action "$ROOT" update test.available "$snapshot_id" background \
  | jq -e '.started == true' >/dev/null
status="$(wait_action)"
jq -e '.ok == true and .operation == "update"
  and .message == "Plugin updated!"' <<<"$status" >/dev/null
grep -Fqx 'plugin update test.available --yes' "$MOCK_LOG"
grep -Fqx 'restart shell' "$MOCK_LOG"
printf 'ok - available updates use the native updater then restart the shell\n'

for id in test.current test.dirty test.ahead test.diverged test.manual; do
  : >"$MOCK_LOG"
  snapshot="$(helper cached "$ROOT")"
  snapshot_id="$(jq -r '.snapshotId' <<<"$snapshot")"
  helper action "$ROOT" update "$id" "$snapshot_id" background \
    | jq -e '.started == true' >/dev/null
  status="$(wait_action)"
  if grep -Eq '^(plugin update |restart shell$)' "$MOCK_LOG"; then
    printf 'not ok - unsafe or current plugin reached update execution: %s\n' \
      "$id" >&2
    exit 1
  fi
  if [[ $id == test.current ]]; then
    jq -e '.ok == true
      and .message == "Plugin already up-to-date!"' \
      <<<"$status" >/dev/null
  else
    jq -e '.ok == false' <<<"$status" >/dev/null
  fi
done
if rg -q 'git .* (merge|reset)( |$)' "$ROOT/lib/backend/updates.sh"; then
  printf 'not ok - read-only checker contains a merge or reset\n' >&2
  exit 1
fi
printf 'ok - current and unsafe plugins never invoke the native updater\n'
