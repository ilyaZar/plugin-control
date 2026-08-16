readonly SELF_ID="io.github.ilyazar.plugin-control"
readonly USER_DATA_ID="ilyazar.plugin-control"
readonly LEGACY_USER_DATA_ID="plugin-control"
json_error() {
  jq -cn --arg error "$1" '{ok:false,error:$error}'
}
utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

epoch_now() {
  date -u +%s
}

valid_plugin_id() {
  [[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $1 != *..* ]]
}

valid_channel_id() {
  [[ ${1:-} =~ ^[a-z0-9][a-z0-9._-]*$ && ${#1} -le 80 ]]
}

valid_github_repository_url() {
  [[ ${1:-} =~ ^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}(\.git)?/?$ ]]
}

normalize_github_url() {
  local value="${1:-}"
  value="${value%/}"
  value="${value%.git}"
  if valid_github_repository_url "$value"; then
    printf '%s\n' "$value"
    return
  fi
  if [[ $value =~ ^git@github\.com:([A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100})$ ]]; then
    printf 'https://github.com/%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  return 1
}

github_slug() {
  local value
  value="$(normalize_github_url "$1")" || return 1
  printf '%s\n' "${value#https://github.com/}"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    json_error "'$1' is required"
    exit 1
  }
}

cli_fail() {
  printf 'plugin-control: %s\n' "$*" >&2
  return 1
}

require_cli_tool() {
  command -v "$1" >/dev/null 2>&1 ||
    cli_fail "required command not found: $1"
}

init_paths() {
  local user_home="${HOME:-}"
  [[ -n $user_home && $user_home == /* ]] || {
    json_error "HOME must be an absolute path"
    exit 1
  }

  local config_base="${XDG_CONFIG_HOME:-$user_home/.config}"
  local cache_base="${XDG_CACHE_HOME:-$user_home/.cache}"
  local state_base="${XDG_STATE_HOME:-$user_home/.local/state}"
  local runtime_base="${XDG_RUNTIME_DIR:-$state_base/runtime}"

  CONFIG_ROOT="$(realpath -m -- "$config_base/omarchy/$USER_DATA_ID")"
  CACHE_ROOT="$(realpath -m -- "$cache_base/omarchy/$USER_DATA_ID")"
  STATE_ROOT="$(realpath -m -- "$state_base/omarchy/$USER_DATA_ID")"
  RUNTIME_ROOT="$(realpath -m -- "$runtime_base/omarchy-$USER_DATA_ID")"
  LEGACY_CONFIG_ROOT="$(realpath -m -- \
    "$config_base/omarchy/$LEGACY_USER_DATA_ID")"
  LEGACY_CACHE_ROOT="$(realpath -m -- \
    "$cache_base/omarchy/$LEGACY_USER_DATA_ID")"
  LEGACY_STATE_ROOT="$(realpath -m -- \
    "$state_base/omarchy/$LEGACY_USER_DATA_ID")"
  LEGACY_RUNTIME_ROOT="$(realpath -m -- \
    "$runtime_base/omarchy-$LEGACY_USER_DATA_ID")"
  PLUGINS_ROOT="$(realpath -m -- "$config_base/omarchy/plugins")"
  BINDINGS_FILE="$(realpath -m -- "$config_base/hypr/bindings.lua")"
  CHANNEL_CONFIG="$CONFIG_ROOT/channels.yaml"
  LAST_GOOD_CONFIG="$STATE_ROOT/channels.json"
  CONFIG_ERROR="$STATE_ROOT/config-error.json"
  CHANNEL_CACHE="$CACHE_ROOT/channels"
  SNAPSHOT_STATE="$STATE_ROOT/snapshot.json"
  REFRESH_STATE="$STATE_ROOT/refresh.json"
  ACTION_STATE="$STATE_ROOT/action.json"
  ACTION_LOG="$STATE_ROOT/action.log"
  ACTION_LOCK="$RUNTIME_ROOT/action.lock"
  REFRESH_LOCK="$RUNTIME_ROOT/refresh.lock"
  SNAPSHOT_LOCK="$RUNTIME_ROOT/snapshot.lock"

  [[ $CONFIG_ROOT == /* && $CACHE_ROOT == /* && $STATE_ROOT == /*
    && $RUNTIME_ROOT == /* && $PLUGINS_ROOT == /*
    && $(basename -- "$CONFIG_ROOT") == "$USER_DATA_ID"
    && $(basename -- "$CACHE_ROOT") == "$USER_DATA_ID"
    && $(basename -- "$STATE_ROOT") == "$USER_DATA_ID"
    && $(basename -- "$RUNTIME_ROOT") == "omarchy-$USER_DATA_ID"
    && $(basename -- "$LEGACY_CONFIG_ROOT") == "$LEGACY_USER_DATA_ID"
    && $(basename -- "$LEGACY_CACHE_ROOT") == "$LEGACY_USER_DATA_ID"
    && $(basename -- "$LEGACY_STATE_ROOT") == "$LEGACY_USER_DATA_ID"
    && $(basename -- "$LEGACY_RUNTIME_ROOT") == \
      "omarchy-$LEGACY_USER_DATA_ID"
    && $(basename -- "$BINDINGS_FILE") == bindings.lua ]] || {
    json_error "refusing unsafe Plugin Control paths"
    exit 1
  }

  umask 077
  migrate_user_root "$LEGACY_CONFIG_ROOT" "$CONFIG_ROOT"
  migrate_user_root "$LEGACY_CACHE_ROOT" "$CACHE_ROOT"
  migrate_user_root "$LEGACY_STATE_ROOT" "$STATE_ROOT"
  migrate_user_root "$LEGACY_RUNTIME_ROOT" "$RUNTIME_ROOT"
  mkdir -p -- "$CONFIG_ROOT" "$CHANNEL_CACHE" "$STATE_ROOT" "$RUNTIME_ROOT"
}

migrate_user_root() {
  local legacy="$1"
  local namespaced="$2"
  [[ -d $legacy && ! -L $legacy && ! -e $namespaced && ! -L $namespaced ]] \
    || return 0
  mkdir -p -- "$(dirname -- "$namespaced")"
  mv -T -- "$legacy" "$namespaced"
}

purge_user_data() {
  local root="$1"
  local binding_helper="$root/scripts/remove-keybinding.rb"
  [[ -f $binding_helper && ! -L $binding_helper ]] || return 1

  ruby "$binding_helper" "$BINDINGS_FILE" "$SELF_ID" || return 1
  rm -rf -- "$CONFIG_ROOT" "$CACHE_ROOT" "$STATE_ROOT" \
    "$LEGACY_CONFIG_ROOT" "$LEGACY_CACHE_ROOT" "$LEGACY_STATE_ROOT" \
    "$LEGACY_RUNTIME_ROOT"
}

source_root() {
  local candidate="${1:-}"
  [[ -n $candidate ]] || return 1
  candidate="$(realpath -m -- "$candidate")"
  [[ -d $candidate && -f $candidate/manifest.json
    && -f $candidate/lib/catalog.jq
    && -f $candidate/lib/channel_config.rb ]]
  printf '%s\n' "$candidate"
}

atomic_write_stream() {
  local target="$1"
  local parent temporary
  parent="$(dirname -- "$target")"
  mkdir -p -- "$parent"
  [[ ! -L $target && ! -d $target ]] || return 1
  temporary="$(mktemp "$parent/.$(basename -- "$target").tmp.XXXXXX")"
  if ! cat >"$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod 0600 "$temporary"
  if ! mv -fT -- "$temporary" "$target"; then
    rm -f -- "$temporary"
    return 1
  fi
}

atomic_write_text() {
  local target="$1"
  local content="$2"
  printf '%s\n' "$content" | atomic_write_stream "$target"
}
