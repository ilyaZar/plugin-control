#!/bin/bash
# Backend functions invoke test doubles after their modules are sourced.
# shellcheck disable=SC2329

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
jq -e '.ok == true and (.records | length) == 4' <<<"$valid" >/dev/null
jq -e '.records[0].installable == true' <<<"$valid" >/dev/null
jq -e '.records[1].installable == true' <<<"$valid" >/dev/null
jq -e '.records[2].installable == false' <<<"$valid" >/dev/null
jq -e '.records[3].installable == false' <<<"$valid" >/dev/null
jq -e '.records[1].listingValidatedCommit != .records[1].upstreamObservedCommit' \
  <<<"$valid" >/dev/null
jq -e '.records[0].stars == 42
  and .records[0].verificationStatus == "verified"
  and .records[0].verificationSnapshotStatus == "verified"
  and .records[0].verificationCoverage == "snapshot-verified"
  and .records[0].verificationMethod == "maintainer-reviewed"
  and .records[0].verificationReviewedBy == "marketplace-maintainer"
  and .records[1].verificationStatus == "unverified"
  and .records[1].verificationSnapshotStatus == "verified"
  and .records[1].verificationCoverage == "update-unverified"
  and .records[2].verificationCoverage == "unverified"
  and .records[3].verificationStatus == ""
  and .records[0].addedAt == "2026-08-20"
  and .records[0].listedAt == "2026-08-20T08:00:00.000Z"
  and .records[0].versionUpdatedAt == "2026-08-20T09:00:00.000Z"
  and .records[0].previewImage
    == "assets/img/plugins/7-example-weather-detail.webp"
  and .records[0].previewWidth == 1600
  and .records[0].previewThumbnail
    == "assets/img/plugins/7-example-weather-card.webp"
  and .records[0].previewThumbnailHeight == 405
  and .records[2].stars == 0' \
  <<<"$valid" >/dev/null
printf 'ok - schema 2 verification states and browse-only rows\n'

automatic_verified="$(jq 'del(.plugins[0].verificationMethod,
  .plugins[0].verificationReviewedAt,.plugins[0].verificationReviewedBy)' \
  "$TEST_DIR/fixtures/catalog-valid.json" \
  | normalize /dev/stdin)"
jq -e '.ok == true and (.records | length) == 4
  and .records[0].verificationCoverage == "snapshot-verified"
  and .records[0].verificationMethod == ""' \
  <<<"$automatic_verified" >/dev/null
printf 'ok - automatic verification requires no maintainer review fields\n'

validated_fallback="$(jq 'del(.plugins[0].upstreamObservedCommit)' \
  "$TEST_DIR/fixtures/catalog-valid.json" \
  | normalize /dev/stdin)"
jq -e '.ok == true and (.records | length) == 4
  and .records[0].verificationCoverage == "snapshot-verified"
  and .records[0].upstreamObservedCommit
    == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
  <<<"$validated_fallback" >/dev/null
printf 'ok - verification follows the producer commit fallback\n'

updated_fallback="$(jq 'del(.plugins[1].upstreamObservedCommit)' \
  "$TEST_DIR/fixtures/catalog-valid.json" \
  | normalize /dev/stdin)"
jq -e '.ok == true and (.records | length) == 4
  and .records[1].verificationCoverage == "update-unverified"
  and .records[1].upstreamObservedCommit
    == "cccccccccccccccccccccccccccccccccccccccc"' \
  <<<"$updated_fallback" >/dev/null
printf 'ok - normalized drift keeps the producer commit fallback\n'

jq '.plugins += [{"name":"missing id"},
  {"id":"bad/id","name":"bad","sourceType":"community"},
  {"id":"bad.url","name":"bad","sourceType":"community",
    "repo":"http://github.com/example/bad","repositoryLayout":"root-plugin",
    "manifestPath":"manifest.json","installAvailable":true}]' \
  "$TEST_DIR/fixtures/catalog-valid.json" >"$TEMP_ROOT/malformed-rows.json"
malformed="$(normalize "$TEMP_ROOT/malformed-rows.json")"
jq -e '(.records | length) == 4 and (.errors | length) == 3' \
  <<<"$malformed" >/dev/null
printf 'ok - missing fields invalid IDs and unsafe URLs are row errors\n'

printf '{"stateSchemaVersion":2,"plugins":"wrong"}\n' \
  >"$TEMP_ROOT/malformed-root.json"
normalize "$TEMP_ROOT/malformed-root.json" \
  | jq -e '.ok == false and (.records | length) == 0' >/dev/null
printf 'ok - malformed catalog root is rejected\n'

for version in legacy missing future; do
  case "$version" in
    legacy)
      jq '.stateSchemaVersion = 1' "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/unsupported-schema.json"
      ;;
    missing)
      jq 'del(.stateSchemaVersion)' "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/unsupported-schema.json"
      ;;
    future)
      jq '.stateSchemaVersion = 3' "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/unsupported-schema.json"
      ;;
  esac
  normalize "$TEMP_ROOT/unsupported-schema.json" \
    | jq -e '.ok == false and (.error | contains("unsupported"))' >/dev/null
done
printf 'ok - only catalog state schema 2 is accepted\n'

for mutation in update-status missing-baseline missing-listing \
    mismatched-baseline \
    snapshot-observed-mismatch update-observed-match empty-baseline \
    unverified-baseline builtin-verification reviewed-without-reviewer \
    empty-reviewer; do
  case "$mutation" in
    update-status)
      jq '.plugins[1].verificationStatus = "verified"' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    missing-baseline)
      jq 'del(.plugins[0].verificationCommit)' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    missing-listing)
      jq 'del(.plugins[0].listingValidatedCommit)' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    mismatched-baseline)
      jq '.plugins[0].verificationCommit
        = "dddddddddddddddddddddddddddddddddddddddd"' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    snapshot-observed-mismatch)
      jq '.plugins[0].upstreamObservedCommit
        = "dddddddddddddddddddddddddddddddddddddddd"' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    update-observed-match)
      jq '.plugins[1].upstreamObservedCommit
        = .plugins[1].verificationCommit' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    empty-baseline)
      jq '.plugins[0].verificationBaselineVersion = ""' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    unverified-baseline)
      jq '.plugins[2].verificationBaselineVersion = "3"' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    builtin-verification)
      jq '.plugins[3] += {verificationStatus:"verified",
        verificationSnapshotStatus:"verified",
        verificationCoverage:"snapshot-verified"}' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    reviewed-without-reviewer)
      jq 'del(.plugins[0].verificationReviewedBy)' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
    empty-reviewer)
      jq '.plugins[0].verificationReviewedBy = ""' \
        "$TEST_DIR/fixtures/catalog-valid.json" \
        >"$TEMP_ROOT/invalid-verification.json"
      ;;
  esac
  invalid_verification="$(normalize "$TEMP_ROOT/invalid-verification.json")"
  jq -e '(.records | length) == 3 and (.errors | length) == 1' \
    <<<"$invalid_verification" >/dev/null
done
printf 'ok - inconsistent schema 2 verification states are rejected\n'

jq -n '{stateSchemaVersion:2,plugins:
  [range(0;5001)|{id:("x."+tostring),name:"x",sourceType:"community"}]}' \
  >"$TEMP_ROOT/oversized-count.json"
normalize "$TEMP_ROOT/oversized-count.json" \
  | jq -e '.ok == false and (.error | contains("too many"))' >/dev/null
printf 'ok - excessive record counts are rejected\n'

custom="$(jq -c --arg channelName Custom \
  --arg channelSource custom --argjson channelRank 10 \
  -f "$ROOT/lib/catalog.jq" "$TEST_DIR/fixtures/catalog-valid.json")"
jq -e '.records[3].builtIn == false and .records[3].source == "custom"
  and .records[3].previewImage == ""
  and .records[3].previewThumbnail == ""
  and (.records[3] | has("previewWidth") | not)' \
  <<<"$custom" >/dev/null
printf 'ok - custom catalogs cannot impersonate marketplace presentation\n'

export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/config"
export XDG_CACHE_HOME="$TEMP_ROOT/cache"
export XDG_STATE_HOME="$TEMP_ROOT/state"
export XDG_RUNTIME_DIR="$TEMP_ROOT/runtime"
source "$ROOT/bin/plugin-control"
init_paths

curl() {
  local output=""
  while (( $# > 0 )); do
    if [[ $1 == --output ]]; then
      output="$2"
      shift 2
    else
      shift
    fi
  done
  printf 'mock webp\n' >"$output"
}
magick() {
  local output="${!#}"
  printf '\211PNG\r\n\032\nmock\n' >"$output"
}
preview_json="$(preview_command io.example.preview \
  https://omarchyplugins.com/assets/img/plugins/7-example-preview-card.webp \
  https://omarchyplugins.com/assets/img/plugins/7-example-preview-detail.webp \
  2026-08-20T10:00:00Z)"
jq -e '.ok == true and .id == "io.example.preview"
  and (.cardUrl | startswith("file://"))
  and (.detailUrl | endswith(".png"))' <<<"$preview_json" >/dev/null
if preview_command io.example.preview \
    https://example.com/preview-card.webp \
    https://omarchyplugins.com/assets/img/plugins/7-example-preview-detail.webp \
    current >"$TEMP_ROOT/unsafe-preview.json"; then
  printf 'not ok - unsafe preview origin accepted\n' >&2
  exit 1
fi
unset -f curl magick
printf 'ok - marketplace previews use an owned converted cache\n'

good_config="$(load_config "$ROOT")"
sed 's/tray-icon-hidden: false/tray-icon-hidden: hidden/' \
  "$ROOT/config/channels.yaml" >"$CHANNEL_CONFIG"
invalid_status="$(config_status "$ROOT")"
jq -e '.ok == false and .usingLastGood == true
  and .usingDefaults == false and .fallback == "last-good"
  and .field == "settings.tray-icon-hidden"
  and .actual == "\"hidden\"" and .expected == "true or false"
  and .config.settings["tray-icon-hidden"] == false
  and .config.settings.background_dim == false' \
  <<<"$invalid_status" >/dev/null
cp "$ROOT/config/channels.yaml" "$CHANNEL_CONFIG"
printf 'ok - invalid fields report admissible values and keep last good\n'

printf 'version: [\n' >"$CHANNEL_CONFIG"
fallback_config="$(load_config "$ROOT")"
jq -e --argjson expected "$good_config" '. == $expected' \
  <<<"$fallback_config" >/dev/null
jq -e '.error | length > 0' "$CONFIG_ERROR" >/dev/null
cp "$ROOT/config/channels.yaml" "$CHANNEL_CONFIG"
printf 'ok - malformed YAML preserves the last good configuration\n'

rm -f -- "$LAST_GOOD_CONFIG"
sed 's/^version: 2$/version: 1/' "$ROOT/config/channels.yaml" \
  >"$CHANNEL_CONFIG"
cp "$CHANNEL_CONFIG" "$TEMP_ROOT/legacy-config.yaml"
if load_config "$ROOT" >"$TEMP_ROOT/legacy-output.json"; then
  printf 'not ok - unsupported config fell back to defaults\n' >&2
  exit 1
fi
cmp "$CHANNEL_CONFIG" "$TEMP_ROOT/legacy-config.yaml"
legacy_status="$(config_status "$ROOT" || true)"
jq -e '.ok == false and .usingLastGood == false and .config == null
  and .usingDefaults == false and .fallback == ""
  and .field == "version" and .expected == "the integer 2"
  and (.error | contains("unsupported"))' <<<"$legacy_status" >/dev/null
mkdir -p -- "$(dirname -- "$SNAPSHOT_STATE")"
jq -cn '{ok:true,snapshotId:"legacy",records:[],config:{version:1}}' \
  >"$SNAPSHOT_STATE"
if cached_command "$ROOT" >"$TEMP_ROOT/legacy-snapshot.json"; then
  printf 'not ok - cached command returned a legacy snapshot\n' >&2
  exit 1
fi
[[ ! -s $TEMP_ROOT/legacy-snapshot.json ]]

sed 's/tray-icon-hidden: false/tray-icon-hidden: hidden/' \
  "$ROOT/config/channels.yaml" >"$CHANNEL_CONFIG"
default_status="$(config_status "$ROOT")"
jq -e '.ok == false and .usingLastGood == false
  and .usingDefaults == true and .fallback == "defaults"
  and .field == "settings.tray-icon-hidden"
  and .config.settings["tray-icon-hidden"] == false
  and .config.settings.background_dim == false' \
  <<<"$default_status" >/dev/null
printf 'ok - recoverable first-run errors use shipped defaults\n'

cp "$ROOT/config/channels.yaml" "$CHANNEL_CONFIG"
load_config "$ROOT" >/dev/null
printf 'ok - unsupported config and snapshot fail without replacement\n'

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
  [[ ${4:-} == '"current"' ]]
  : >"$2"
  : >"$3"
  printf '304\n'
}
printf '%s\n' '{"normalizerVersion":4,"etag":"\"current\""}' \
  >"$CHANNEL_CACHE/marketplace.meta.json"
refresh_catalog_channel "$ROOT" "$channel"
[[ $(sha256sum "$CHANNEL_CACHE/marketplace.json") == "$before" ]]
printf 'ok - ETag unchanged response keeps cache\n'

download_catalog() {
  [[ -z ${4:-} && -z ${5:-} ]]
  cp "$TEST_DIR/fixtures/catalog-valid.json" "$2"
  printf 'ETag: "new"\n' >"$3"
  printf '200\n'
}
printf '%s\n' '{"normalizerVersion":3,"etag":"\"stale\""}' \
  >"$CHANNEL_CACHE/marketplace.meta.json"
refresh_catalog_channel "$ROOT" "$channel"
jq -e '.normalizerVersion == 4 and .etag == "\"new\""' \
  "$CHANNEL_CACHE/marketplace.meta.json" >/dev/null
jq -e '.records[0].stars == 42
  and .records[0].versionUpdatedAt == "2026-08-20T09:00:00.000Z"' \
  "$CHANNEL_CACHE/marketplace.json" >/dev/null
printf 'ok - changed normalizer forces a complete catalog download\n'

download_catalog() {
  printf '{"stateSchemaVersion":2,"plugins":[]}\n' >"$2"
  : >"$3"
  printf '200\n'
}
refresh_catalog_channel "$ROOT" "$channel"
jq -e '.ok == true and (.records | length) == 0' \
  "$CHANNEL_CACHE/marketplace.json" >/dev/null
printf 'ok - valid empty catalog clears stale records\n'

cat >"$TEMP_ROOT/stats-valid.json" <<'JSON'
{
  "schemaVersion": 1,
  "plugins": {
    "io.example.weather": {"views": 123, "copies": 45, "hearts": 6}
  }
}
JSON
normalized_stats="$(normalize_marketplace_stats \
  "$TEMP_ROOT/stats-valid.json" "2026-08-20T12:00:00Z")"
jq -e '.schemaVersion == 1
  and .retrievedAt == "2026-08-20T12:00:00Z"
  and .plugins["io.example.weather"].views == 123
  and .plugins["io.example.weather"].copies == 45
  and .plugins["io.example.weather"].hearts == 6' \
  <<<"$normalized_stats" >/dev/null
for mutation in negative extra wrong-schema; do
  case "$mutation" in
    negative)
      jq '.plugins["io.example.weather"].views = -1' \
        "$TEMP_ROOT/stats-valid.json" >"$TEMP_ROOT/stats-invalid.json"
      ;;
    extra)
      jq '.plugins["io.example.weather"].downloads = 9' \
        "$TEMP_ROOT/stats-valid.json" >"$TEMP_ROOT/stats-invalid.json"
      ;;
    wrong-schema)
      jq '.schemaVersion = 2' "$TEMP_ROOT/stats-valid.json" \
        >"$TEMP_ROOT/stats-invalid.json"
      ;;
  esac
  if normalize_marketplace_stats "$TEMP_ROOT/stats-invalid.json" \
      "2026-08-20T12:00:00Z" >/dev/null 2>&1; then
    printf 'not ok - invalid marketplace stats were accepted: %s\n' \
      "$mutation" >&2
    exit 1
  fi
done
printf 'ok - marketplace metrics use a strict aggregate schema\n'

printf '%s\n' "$normalized_stats" >"$MARKETPLACE_STATS_CACHE"
stats_before="$(sha256sum "$MARKETPLACE_STATS_CACHE")"
download_marketplace_stats() {
  printf '{bad json' >"$1"
  printf '200\n'
}
if refresh_marketplace_stats; then
  printf 'not ok - malformed metrics replaced the last valid cache\n' >&2
  exit 1
fi
[[ $(sha256sum "$MARKETPLACE_STATS_CACHE") == "$stats_before" ]]

download_marketplace_stats() {
  cp "$TEMP_ROOT/stats-valid.json" "$1"
  printf '200\n'
}
refresh_marketplace_stats
jq -e '.plugins["io.example.weather"].views == 123' \
  "$MARKETPLACE_STATS_CACHE" >/dev/null
printf 'ok - metric refresh retries and preserves the last valid cache\n'

printf '%s\n' "$valid" >"$CHANNEL_CACHE/marketplace.json"
installed_records() {
  : >"$1"
}
rm -f -- "$SNAPSHOT_STATE"
metrics_snapshot="$(build_snapshot "$ROOT")"
jq -e '.records[] | select(.id == "io.example.weather")
  | .metricsAvailable == true and .views == 123 and .copies == 45
    and .hearts == 6 and .stars == 42
    and .verificationStatus == "verified"
    and .verificationSnapshotStatus == "verified"
    and .verificationCoverage == "snapshot-verified"
    and .verificationMethod == "maintainer-reviewed"' \
  <<<"$metrics_snapshot" >/dev/null
jq -e '.records[] | select(.id == "io.example.timer")
  | .verificationStatus == "unverified"
    and .verificationSnapshotStatus == "verified"
    and .verificationCoverage == "update-unverified"' \
  <<<"$metrics_snapshot" >/dev/null
jq -e '.records[] | select(.id == "suite.example")
  | .metricsAvailable == false
    and (has("views") | not) and (has("copies") | not)
    and (has("hearts") | not)' <<<"$metrics_snapshot" >/dev/null
printf 'ok - snapshots join metrics by id without invented zero values\n'

refresh_calls=0
refresh_channel() {
  return 0
}
refresh_marketplace_stats() {
  refresh_calls=$((refresh_calls + 1))
  return 1
}
refresh_command "$ROOT" --force >/dev/null
refresh_command "$ROOT" --force >/dev/null
(( refresh_calls == 2 ))
jq -e '.refreshWarnings == [] and (has("lastRefreshError") | not)' \
  "$REFRESH_STATE" >/dev/null
if rg -q -- '--request[[:space:]]+POST|-X[[:space:]]+POST' \
    "$ROOT/lib/backend" "$ROOT"/*.qml; then
  printf 'not ok - marketplace information emits engagement events\n' >&2
  exit 1
fi
printf 'ok - Ctrl+R retries metrics silently without engagement posts\n'

previous_refresh="2026-08-20T12:00:00Z"
previous_epoch=1787227200
jq -cn --arg lastSuccessfulRefresh "$previous_refresh" \
  --argjson lastSuccessfulEpoch "$previous_epoch" \
  '{lastSuccessfulRefresh:$lastSuccessfulRefresh,
    lastSuccessfulEpoch:$lastSuccessfulEpoch,refreshWarnings:[],
    refreshDurationMs:10}' >"$REFRESH_STATE"
jq -cn '{normalizerVersion:4,retrievedAt:"2026-08-20T11:59:00Z"}' \
  >"$CHANNEL_CACHE/marketplace.meta.json"
refresh_channel() {
  return 1
}
refresh_command "$ROOT" --force >"$TEMP_ROOT/warning-snapshot.json"
warning_snapshot="$(<"$TEMP_ROOT/warning-snapshot.json")"
jq -e --arg refreshed "$previous_refresh" \
  --argjson epoch "$previous_epoch" '
    .lastSuccessfulRefresh == $refreshed
    and .lastSuccessfulEpoch == $epoch
    and (.refreshWarnings | length) == 1
    and .refreshWarnings[0].channelId == "marketplace"
    and .refreshWarnings[0].fallback == "cache"
    and .refreshWarnings[0].cacheRetrievedAt == "2026-08-20T11:59:00Z"
    and (has("lastRefreshError") | not)' "$REFRESH_STATE" >/dev/null
jq -e --arg refreshed "$previous_refresh" '
    .cache.lastSuccessfulRefresh == $refreshed
    and (.cache.refreshWarnings | length) == 1' \
  <<<"$warning_snapshot" >/dev/null
printf 'ok - recoverable refresh warnings preserve cache time and epoch\n'

mv "$CHANNEL_CACHE/marketplace.json" \
  "$TEMP_ROOT/marketplace-cache-preserved.json"
refresh_command "$ROOT" --force >"$TEMP_ROOT/bundled-warning-snapshot.json"
jq -e 'has("stateSchemaVersion") | not' \
  "$ROOT/bootstrap/catalog.json" >/dev/null
jq -e '
    (.cache.refreshWarnings | length) == 1
    and .cache.refreshWarnings[0].channelId == "marketplace"
    and .cache.refreshWarnings[0].fallback == "bundled"
    and (.records | length) > 0' \
  "$TEMP_ROOT/bundled-warning-snapshot.json" >/dev/null
mv "$TEMP_ROOT/marketplace-cache-preserved.json" \
  "$CHANNEL_CACHE/marketplace.json"
printf 'ok - missing marketplace cache falls back to bundled catalog\n'

refresh_channel() {
  return 0
}
refresh_command "$ROOT" --force >/dev/null
jq -e --arg refreshed "$previous_refresh" --argjson epoch "$previous_epoch" '
    .lastSuccessfulRefresh != $refreshed
    and .lastSuccessfulEpoch > $epoch
    and .refreshWarnings == []' "$REFRESH_STATE" >/dev/null
printf 'ok - complete refresh clears warnings and advances success time\n'
