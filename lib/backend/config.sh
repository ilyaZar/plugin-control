ensure_config() {
  local root="$1"
  local template="$root/config/channels.yaml"
  [[ -f $template && ! -L $template ]] || return 1
  if [[ -e $CHANNEL_CONFIG || -L $CHANNEL_CONFIG ]]; then
    [[ -f $CHANNEL_CONFIG && ! -L $CHANNEL_CONFIG ]]
    return
  fi
  atomic_write_stream "$CHANNEL_CONFIG" <"$template"
}
parse_config() {
  local root="$1"
  ruby "$root/lib/channel_config.rb" "$CHANNEL_CONFIG"
}

load_config() {
  local root="$1"
  local result="" fallback="" fallback_config="" default_result=""
  ensure_config "$root" || {
    json_error "could not create or safely read the channel configuration"
    return 1
  }

  if result="$(parse_config "$root")" && jq -e '.ok == true' <<<"$result" >/dev/null; then
    jq -c '.config' <<<"$result" | atomic_write_stream "$LAST_GOOD_CONFIG"
    rm -f -- "$CONFIG_ERROR"
    jq -c '.config' <<<"$result"
    return
  fi

  [[ -n $result ]] || result='{}'
  if [[ -f $LAST_GOOD_CONFIG && ! -L $LAST_GOOD_CONFIG ]] \
    && jq -e 'type == "object" and .version == 2' "$LAST_GOOD_CONFIG" >/dev/null 2>&1; then
    fallback="last-good"
    fallback_config="$(jq -c . "$LAST_GOOD_CONFIG")"
  elif jq -e '.recoverable == true' <<<"$result" >/dev/null 2>&1 \
      && default_result="$(ruby "$root/lib/channel_config.rb" \
        "$root/config/channels.yaml")" \
      && jq -e '.ok == true and .config.version == 2' \
        <<<"$default_result" >/dev/null 2>&1; then
    fallback="defaults"
    fallback_config="$(jq -c '.config' <<<"$default_result")"
  fi

  jq -c --arg at "$(utc_now)" --arg fallback "$fallback" '
    {
      error:(.error // "invalid channel configuration"),
      line:(.line // null),
      field:(.field // null),
      actual:(.actual // null),
      expected:(.expected // null),
      at:$at,
      fallback:$fallback
    }
  ' <<<"$result" | atomic_write_stream "$CONFIG_ERROR" || true
  [[ -n $fallback_config ]] || return 1
  printf '%s\n' "$fallback_config"
}

config_status() {
  local root="$1"
  local config
  config="$(load_config "$root")" || {
    if [[ -f $CONFIG_ERROR && ! -L $CONFIG_ERROR ]]; then
      jq -c --arg path "$CHANNEL_CONFIG" \
        '. + {ok:false,path:$path,usingLastGood:false,
          usingDefaults:false,config:null}' \
        "$CONFIG_ERROR"
      return 1
    fi
    json_error "no valid channel configuration is available"
    return 1
  }
  if [[ -f $CONFIG_ERROR && ! -L $CONFIG_ERROR ]]; then
    jq -c --arg path "$CHANNEL_CONFIG" --argjson config "$config" \
      '. + {ok:false,path:$path,
        usingLastGood:(.fallback == "last-good"),
        usingDefaults:(.fallback == "defaults"),config:$config}' \
      "$CONFIG_ERROR"
  else
    jq -cn --arg path "$CHANNEL_CONFIG" --argjson config "$config" \
      '{ok:true,path:$path,usingLastGood:false,usingDefaults:false,
        config:$config}'
  fi
}
