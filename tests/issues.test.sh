#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT
TEMP_ROOT="$(mktemp -d /tmp/plugin-control-issues-test.XXXXXX)"
readonly TEMP_ROOT
trap 'rm -rf -- "$TEMP_ROOT"' EXIT

result="$(jq -c \
  --argjson required '["submission","validated"]' \
  --argjson excluded '["listed","needs-fixes"]' \
  -f "$ROOT/lib/issues.jq" "$TEST_DIR/fixtures/issues.json")"
jq -e 'length == 1 and .[0].issueNumber == 1
  and .[0].repository == "https://github.com/example/valid"
  and (.[0].warnings | index("security-review-required"))' \
  <<<"$result" >/dev/null
printf 'ok - validated submission is included with security warning\n'
printf 'ok - listed needs-fixes pull requests and malformed bodies are excluded\n'

export HOME="$TEMP_ROOT/home"
export XDG_CONFIG_HOME="$TEMP_ROOT/config"
export XDG_CACHE_HOME="$TEMP_ROOT/cache"
export XDG_STATE_HOME="$TEMP_ROOT/state"
export XDG_RUNTIME_DIR="$TEMP_ROOT/runtime"
source "$ROOT/bin/plugin-control"
init_paths

cat >"$TEMP_ROOT/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "io.example.valid",
  "name": "Valid",
  "version": "1.0.0",
  "author": "Example",
  "description": "Valid root plugin",
  "kinds": ["overlay"],
  "entryPoints": {"overlay":"Plugin.qml"}
}
JSON
cat >"$TEMP_ROOT/tree.json" <<'JSON'
{"tree":[{"path":"Plugin.qml","type":"blob","mode":"100644"}]}
JSON
valid_submission_manifest "$TEMP_ROOT/manifest.json"
submission_tree_valid "$TEMP_ROOT/manifest.json" "$TEMP_ROOT/tree.json"
printf 'ok - root manifest and regular entry points are required\n'

jq '.tree[0].mode="120000"' "$TEMP_ROOT/tree.json" \
  >"$TEMP_ROOT/symlink-tree.json"
if submission_tree_valid "$TEMP_ROOT/manifest.json" \
  "$TEMP_ROOT/symlink-tree.json"; then
  printf 'not ok - symlink entry point was accepted\n' >&2
  exit 1
fi
printf 'ok - symlink entry points are rejected\n'

if submission_installable '{"allow_unlisted_installs":false}'; then
  printf 'not ok - disabled unlisted installation became actionable\n' >&2
  exit 1
fi
submission_installable '{"allow_unlisted_installs":true}'
printf 'ok - unlisted browsing and installation use separate action gates\n'

record='{"repository":"https://github.com/example/valid",
  "commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
github_get() {
  case "$1" in
    */repos/example/valid)
      printf '{"default_branch":"main"}\n' >"$2"
      ;;
    */commits/main)
      printf '{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}\n' >"$2"
      ;;
    *) return 1 ;;
  esac
}
if submission_commit_current "$record"; then
  printf 'not ok - changed commit was accepted\n' >&2
  exit 1
fi
printf 'ok - changed commit before install is rejected\n'

existing='{"ok":true,"records":[{"id":"cached.issue"}]}'
printf '%s\n' "$existing" >"$CHANNEL_CACHE/hancore-submissions.json"
github_get() { return 1; }
github_get_conditional() { return 1; }
channel='{"id":"hancore-submissions","name":"Unlisted marketplace submissions",
  "type":"github-submissions","enabled":true,
  "repository":"HANCORE-linux/omarchy-plugin-marketplace",
  "required_labels":["submission","validated"],
  "excluded_labels":["listed","needs-fixes"]}'
config='{"allow_unlisted_installs":false}'
if refresh_submission_channel "$ROOT" "$channel" "$config"; then
  printf 'not ok - rate-limit-style failure was accepted\n' >&2
  exit 1
fi
jq -e '.records[0].id == "cached.issue"' \
  "$CHANNEL_CACHE/hancore-submissions.json" >/dev/null
printf 'ok - API failure preserves the submission cache\n'

jq '.[0] as $valid | [
  $valid,
  ($valid
    | .number = 6
    | .html_url = "https://example.invalid/6"
    | .title = "Unavailable"
    | .body = "### Repository URL\n\nhttps://github.com/example/fails\n")
]' "$TEST_DIR/fixtures/issues.json" >"$TEMP_ROOT/mixed-issues.json"
metadata='{"etag":"old","retrievedAt":"old","repository":"old"}'
printf '%s\n' "$metadata" \
  >"$CHANNEL_CACHE/hancore-submissions.issues.meta.json"
cp "$CHANNEL_CACHE/hancore-submissions.json" "$TEMP_ROOT/cache.before"
cp "$CHANNEL_CACHE/hancore-submissions.issues.meta.json" \
  "$TEMP_ROOT/metadata.before"
github_get_conditional() {
  cp "$TEMP_ROOT/mixed-issues.json" "$2"
  : >"$3"
  printf '200\n'
}
github_get() {
  case "$1" in
    */repos/example/valid)
      printf '{"default_branch":"main"}\n' >"$2"
      ;;
    */repos/example/valid/commits/main)
      printf '{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n' >"$2"
      ;;
    *raw.githubusercontent.com/example/valid/*/manifest.json)
      cp "$TEMP_ROOT/manifest.json" "$2"
      ;;
    */repos/example/valid/git/trees/*)
      cp "$TEMP_ROOT/tree.json" "$2"
      ;;
    *) return 1 ;;
  esac
}
if refresh_submission_channel "$ROOT" "$channel" "$config"; then
  printf 'not ok - repository API failure was accepted\n' >&2
  exit 1
fi
cmp -s "$TEMP_ROOT/cache.before" \
  "$CHANNEL_CACHE/hancore-submissions.json"
cmp -s "$TEMP_ROOT/metadata.before" \
  "$CHANNEL_CACHE/hancore-submissions.issues.meta.json"
printf 'ok - candidate API failure preserves the submission cache\n'

github_get_conditional() {
  printf '304\n'
}
refresh_submission_channel "$ROOT" "$channel" "$config"
jq -e '.records[0].id == "cached.issue"' \
  "$CHANNEL_CACHE/hancore-submissions.json" >/dev/null
printf 'ok - unchanged GitHub issues reuse the validated cache\n'
