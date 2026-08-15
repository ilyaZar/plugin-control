#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT
TEMP_ROOT="$(mktemp -d /tmp/plugin-control-catalog-test.XXXXXX)"
readonly TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

normalize() {
  jq -c --arg channelName "Omarchy Plugins Marketplace" \
    --arg channelSource marketplace --argjson channelRank 30 \
    -f "$ROOT/lib/catalog.jq" "$1"
}

valid="$(normalize "$TEST_DIR/fixtures/catalog-valid.json")"
jq -e '.ok == true and (.records | length) == 2' <<<"$valid" >/dev/null
jq -e '.records[0].installable == true' <<<"$valid" >/dev/null
jq -e '.records[1].installable == false' <<<"$valid" >/dev/null
jq -e '.records[0].listingValidatedCommit != .records[0].upstreamObservedCommit' \
  <<<"$valid" >/dev/null
printf 'ok - marketplace-like catalog and browse-only rows\n'

jq '.plugins += [{"name":"missing id"},
  {"id":"bad/id","name":"bad","sourceType":"community"},
  {"id":"bad.url","name":"bad","sourceType":"community",
    "repo":"http://github.com/example/bad","repositoryLayout":"root-plugin",
    "manifestPath":"manifest.json","installAvailable":true}]' \
  "$TEST_DIR/fixtures/catalog-valid.json" >"$TEMP_ROOT/malformed-rows.json"
malformed="$(normalize "$TEMP_ROOT/malformed-rows.json")"
jq -e '(.records | length) == 2 and (.errors | length) == 3' \
  <<<"$malformed" >/dev/null
printf 'ok - missing fields invalid IDs and unsafe URLs are row errors\n'

printf '{"stateSchemaVersion":1,"plugins":"wrong"}\n' \
  >"$TEMP_ROOT/malformed-root.json"
normalize "$TEMP_ROOT/malformed-root.json" \
  | jq -e '.ok == false and (.records | length) == 0' >/dev/null
printf 'ok - malformed catalog root is rejected\n'

jq -n '{stateSchemaVersion:1,plugins:
  [range(0;5001)|{id:("x."+tostring),name:"x",sourceType:"community"}]}' \
  >"$TEMP_ROOT/oversized-count.json"
normalize "$TEMP_ROOT/oversized-count.json" \
  | jq -e '.ok == false and (.error | contains("too many"))' >/dev/null
printf 'ok - excessive record counts are rejected\n'

jq '.plugins[0].sourceType="builtin" | .plugins[0].builtIn=true' \
  "$TEST_DIR/fixtures/catalog-valid.json" >"$TEMP_ROOT/custom-builtin.json"
custom="$(jq -c --arg channelName Custom \
  --arg channelSource custom --argjson channelRank 10 \
  -f "$ROOT/lib/catalog.jq" "$TEMP_ROOT/custom-builtin.json")"
jq -e '.records[0].builtIn == false and .records[0].source == "custom"' \
  <<<"$custom" >/dev/null
printf 'ok - custom catalogs cannot impersonate native built-ins\n'

export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/config"
export XDG_CACHE_HOME="$TEMP_ROOT/cache"
export XDG_STATE_HOME="$TEMP_ROOT/state"
export XDG_RUNTIME_DIR="$TEMP_ROOT/runtime"
source "$ROOT/bin/plugin-control"
init_paths

good_config="$(load_config "$ROOT")"
printf 'version: [\n' >"$CHANNEL_CONFIG"
fallback_config="$(load_config "$ROOT")"
jq -e --argjson expected "$good_config" '. == $expected' \
  <<<"$fallback_config" >/dev/null
jq -e '.error | length > 0' "$CONFIG_ERROR" >/dev/null
cp "$ROOT/config/channels.yaml" "$CHANNEL_CONFIG"
printf 'ok - malformed YAML preserves the last good configuration\n'

target="$CACHE_ROOT/atomic.json"
printf '{"value":1}\n' | atomic_write_stream "$target"
jq -e '.value == 1' "$target" >/dev/null
printf '{"value":2}\n' | atomic_write_stream "$target"
jq -e '.value == 2' "$target" >/dev/null
if find "$CACHE_ROOT" -name '.atomic.json.tmp.*' -print -quit | grep -q .; then
  printf 'not ok - atomic cache left a temporary file\n' >&2
  exit 1
fi
printf 'ok - atomic cache replacement\n'

channel='{"id":"marketplace","name":"Omarchy Plugins Marketplace",
  "type":"marketplace-catalog","enabled":true,
  "catalog_url":"https://omarchyplugins.com/catalog.json"}'
mkdir -p "$CHANNEL_CACHE"
printf '%s\n' "$valid" >"$CHANNEL_CACHE/marketplace.json"
before="$(sha256sum "$CHANNEL_CACHE/marketplace.json")"

download_catalog() {
  printf '{bad json' >"$2"
  : >"$3"
  printf '200\n'
}
if refresh_catalog_channel "$ROOT" "$channel"; then
  printf 'not ok - malformed replacement was accepted\n' >&2
  exit 1
fi
[[ $(sha256sum "$CHANNEL_CACHE/marketplace.json") == "$before" ]]
printf 'ok - malformed download preserves the last valid cache\n'

download_catalog() {
  : >"$2"
  : >"$3"
  printf '000\n'
}
if refresh_catalog_channel "$ROOT" "$channel"; then
  printf 'not ok - failed oversized-style download was accepted\n' >&2
  exit 1
fi
[[ $(sha256sum "$CHANNEL_CACHE/marketplace.json") == "$before" ]]
printf 'ok - failed or oversized downloads preserve cache\n'

download_catalog() {
  : >"$2"
  : >"$3"
  printf '304\n'
}
refresh_catalog_channel "$ROOT" "$channel"
[[ $(sha256sum "$CHANNEL_CACHE/marketplace.json") == "$before" ]]
printf 'ok - ETag unchanged response keeps cache\n'

download_catalog() {
  printf '{"stateSchemaVersion":1,"plugins":[]}\n' >"$2"
  : >"$3"
  printf '200\n'
}
refresh_catalog_channel "$ROOT" "$channel"
jq -e '.ok == true and (.records | length) == 0' \
  "$CHANNEL_CACHE/marketplace.json" >/dev/null
printf 'ok - valid empty catalog clears stale records\n'
