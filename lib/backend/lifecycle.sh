public_usage() {
  cat <<'USAGE'
Usage:
  plugin-control start [--tray-hidden | --tray-visible]
  plugin-control stop
  plugin-control help

With no tray flag, start uses settings.tray-icon-hidden from the Plugin
Control settings file. The shipped default is a visible tray icon.
USAGE
}
start_command() {
  local root="$1"
  shift

  local tray_override="" config tray_hidden discovered=0 attempt
  case "${1:-}" in
    "") ;;
    --tray-hidden) tray_override=true ;;
    --tray-visible) tray_override=false ;;
    *)
      public_usage >&2
      return 2
      ;;
  esac
  (( $# <= 1 )) || {
    public_usage >&2
    return 2
  }

  if ! config="$(load_config "$root")"; then
    local config_error="invalid Plugin Control settings"
    if [[ -f $CONFIG_ERROR && ! -L $CONFIG_ERROR ]]; then
      config_error="$(jq -r '.error // "invalid Plugin Control settings"' \
        "$CONFIG_ERROR")"
    fi
    cli_fail "$config_error"
  fi
  tray_hidden="$(jq -r '.settings["tray-icon-hidden"] // false' \
    <<<"$config")"
  if [[ -n $tray_override ]]; then
    tray_hidden="$tray_override"
  fi

  omarchy-shell shell rescanPlugins >/dev/null ||
    cli_fail "could not rescan installed plugins"
  for (( attempt = 0; attempt < 40; attempt++ )); do
    if omarchy plugin list --json | jq -e --arg id "$SELF_ID" \
      'any(.[]; .id == $id)' >/dev/null; then
      discovered=1
      break
    fi
    sleep 0.05
  done
  (( discovered )) || cli_fail "plugin is not installed or was not discovered"

  omarchy plugin enable "$SELF_ID" >/dev/null ||
    cli_fail "could not enable Plugin Control"
  omarchy bar set "$SELF_ID" trayIconHidden "$tray_hidden" --json \
    >/dev/null || cli_fail "Plugin Control started, but tray visibility was not applied"

  if [[ $tray_hidden == true ]]; then
    printf 'Plugin Control started with its tray icon hidden\n'
  else
    printf 'Plugin Control started with its tray icon visible\n'
  fi
}

stop_command() {
  (( $# == 0 )) || {
    public_usage >&2
    return 2
  }
  omarchy plugin disable "$SELF_ID" >/dev/null ||
    cli_fail "could not disable Plugin Control"
  printf 'Plugin Control stopped\n'
}
