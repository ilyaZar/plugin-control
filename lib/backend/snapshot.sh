manifest_record() {
  local id="$1"
  local enabled="$2"
  local can_disable="$3"
  local path="$4"
  local manifest="$path/manifest.json"
  local dirty=false repository=""
  [[ -f $manifest ]] || return 1
  [[ "$(jq -r '.id // ""' "$manifest" 2>/dev/null)" == "$id" ]] || return 1
  if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [[ -z $(git -C "$path" status --porcelain --untracked-files=normal 2>/dev/null) ]] || dirty=true
    repository="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
    repository="$(normalize_github_url "$repository" 2>/dev/null || true)"
  fi

  jq -c \
    --arg id "$id" --arg path "$path" --arg repository "$repository" \
    --argjson enabled "$enabled" --argjson canDisable "$can_disable" \
    --argjson dirty "$dirty" '
      {
        id:$id,
        name:(.name // $id),
        description:(.description // ""),
        author:(.author // ""),
        version:(.version // ""),
        kind:((.kinds // []) | join(" + ")),
        repository:$repository,
        source:"local",
        sourceName:"Local checkout",
        sourceRank:50,
        installed:true,
        enabled:$enabled,
        canDisable:$canDisable,
        builtIn:false,
        installable:false,
        removable:true,
        dirty:$dirty,
        installedPath:$path
      }
      | with_entries(select(.value != ""))
    ' "$manifest"
}
installed_records() {
  local output="$1"
  local stage="$2"
  local runtime="$stage/runtime.json"
  local seen="$stage/seen.txt"
  : >"$output"
  : >"$seen"
  timeout 5s omarchy plugin list --json >"$runtime" 2>/dev/null || return 1
  jq -e 'type == "array"' "$runtime" >/dev/null || return 1

  jq -c '
    .[]
    | select(.firstParty == true)
    | select(.id | type == "string" and length <= 128
      and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")
      and (contains("..") | not))
    | {
        id,
        name:(.name // .id),
        kind:((.kinds // []) | if type == "array" then join(" + ") else "" end),
        builtIn:true,
        source:"builtin",
        sourceName:"Omarchy built-in",
        sourceRank:40,
        installed:false,
        enabled:(.enabled == true),
        canDisable:(.canDisable == true),
        installable:false,
        removable:false
      }
  ' "$runtime" >>"$output"

  local id enabled can_disable path record
  while IFS=$'\t' read -r id enabled can_disable; do
    valid_plugin_id "$id" || continue
    printf '%s\n' "$id" >>"$seen"
    path="$PLUGINS_ROOT/$id"
    [[ -e $path || -L $path ]] || continue
    record="$(manifest_record "$id" "$enabled" "$can_disable" "$path" \
      2>/dev/null || true)"
    [[ -n $record ]] && printf '%s\n' "$record" >>"$output"
  done < <(jq -r '
    .[]
    | select(.firstParty != true)
    | [.id, (.enabled == true), (.canDisable == true)]
    | @tsv
  ' "$runtime")

  if [[ -d $PLUGINS_ROOT ]]; then
    local entry
    for entry in "$PLUGINS_ROOT"/*; do
      [[ -e $entry || -L $entry ]] || continue
      [[ $(dirname -- "$entry") == "$PLUGINS_ROOT" ]] || continue
      [[ -f $entry/manifest.json ]] || continue
      id="$(basename -- "$entry")"
      valid_plugin_id "$id" || continue
      grep -Fqx -- "$id" "$seen" && continue
      record="$(manifest_record "$id" false false "$entry" \
        2>/dev/null || true)"
      [[ -n $record ]] && printf '%s\n' "$record" >>"$output"
    done
  fi
  return 0
}

build_snapshot() (
  local root="$1"
  exec 6>>"$SNAPSHOT_LOCK"
  flock 6
  local config="${2:-}"
  [[ -n $config ]] || config="$(load_config "$root")" || return 1
  local stage records_jsonl installed_jsonl merged_file diagnostics_file
  local config_file refresh_file snapshot_file snapshot_id
  stage="$(mktemp -d "$RUNTIME_ROOT/snapshot.XXXXXX")"
  records_jsonl="$stage/records.jsonl"
  installed_jsonl="$stage/installed.jsonl"
  : >"$records_jsonl"

  local channel channel_id cache marketplace_loaded=false
  while IFS= read -r channel; do
    channel_id="$(jq -r '.id' <<<"$channel")"
    cache="$CHANNEL_CACHE/$channel_id.json"
    if [[ -f $cache && ! -L $cache ]] && jq -e '.ok == true and (.records | type == "array")' \
      "$cache" >/dev/null 2>&1; then
      if [[ $channel_id == marketplace ]]; then
        jq -c '.records[] | .marketplaceListed = true' "$cache" \
          >>"$records_jsonl"
        marketplace_loaded=true
      else
        jq -c '.records[]' "$cache" >>"$records_jsonl"
      fi
    fi
  done < <(jq -c '.channels[] | select(.enabled == true)' <<<"$config")

  if [[ $marketplace_loaded != true ]]; then
    jq -c '.plugins[] | .marketplaceListed = true' \
      "$root/bootstrap/catalog.json" >>"$records_jsonl"
  fi
  installed_records "$installed_jsonl" "$stage" || {
    rm -rf -- "$stage"
    return 1
  }
  cat "$installed_jsonl" >>"$records_jsonl"

  merged_file="$stage/records.json"
  diagnostics_file="$stage/diagnostics.json"
  config_file="$stage/config.json"
  refresh_file="$stage/refresh.json"
  snapshot_file="$stage/snapshot.json"
  jq -sc '
    group_by(.id)
    | map(sort_by(.sourceRank // 0) | reduce .[] as $record ({}; . * $record))
    | sort_by((.name // .id | ascii_downcase), .id)
  ' "$records_jsonl" >"$merged_file"
  jq -sc '
    group_by(.id)
    | map({id:.[0].id,repositories:([.[].repository // ""] | map(select(length > 0)) | unique)})
    | map(select(.repositories | length > 1)
      | {type:"repository-collision",id,repositories})
  ' "$records_jsonl" >"$diagnostics_file"
  printf '%s\n' "$config" >"$config_file"
  snapshot_id="$(jq -cnS \
    --slurpfile records "$merged_file" --slurpfile config "$config_file" \
    '{records:$records[0],config:$config[0]}' \
    | sha256sum | awk '{print $1}')"

  if [[ -f $REFRESH_STATE && ! -L $REFRESH_STATE ]]; then
    jq -c . "$REFRESH_STATE" >"$refresh_file" 2>/dev/null \
      || printf '{}\n' >"$refresh_file"
  else
    printf '{}\n' >"$refresh_file"
  fi
  jq -cn \
    --arg snapshotId "$snapshot_id" --arg generatedAt "$(utc_now)" \
    --slurpfile records "$merged_file" \
    --slurpfile diagnostics "$diagnostics_file" \
    --slurpfile config "$config_file" --slurpfile refresh "$refresh_file" \
    '{ok:true,snapshotId:$snapshotId,generatedAt:$generatedAt,
      records:$records[0],diagnostics:$diagnostics[0],config:$config[0],
      cache:{lastSuccessfulRefresh:($refresh[0].lastSuccessfulRefresh // ""),
        lastRefreshError:($refresh[0].lastRefreshError // ""),
        refreshDurationMs:($refresh[0].refreshDurationMs // 0)}}' \
    >"$snapshot_file"
  atomic_write_stream "$SNAPSHOT_STATE" <"$snapshot_file"
  cat "$snapshot_file"
  rm -rf -- "$stage"
)

refresh_command() {
  local root="$1"
  local force="${2:-}"
  [[ -z $force || $force == --force ]] || {
    json_error "refresh accepts only --force"
    return 2
  }
  local config
  config="$(load_config "$root")" || return 1
  exec 8>>"$REFRESH_LOCK"
  if ! flock -n 8; then
    jq -cn '{ok:false,busy:true,error:"a catalog refresh is already running"}'
    return 1
  fi

  local started now last_epoch=0 ttl refresh_needed=true
  started="$(date +%s%3N)"
  now="$(epoch_now)"
  ttl=$(( $(jq -r '.refresh_minutes' <<<"$config") * 60 ))
  if [[ $force != --force && -f $REFRESH_STATE && ! -L $REFRESH_STATE ]]; then
    last_epoch="$(jq -r '.lastSuccessfulEpoch // 0' "$REFRESH_STATE" 2>/dev/null || printf 0)"
    if [[ $last_epoch =~ ^[0-9]+$ ]] && (( now - last_epoch < ttl )); then
      refresh_needed=false
    fi
  fi

  local -a errors=()
  local channel channel_name
  if [[ $refresh_needed == true ]]; then
    while IFS= read -r channel; do
      channel_name="$(jq -r '.name' <<<"$channel")"
      if ! refresh_channel "$root" "$channel" "$config"; then
        errors+=("$channel_name refresh failed; using its last valid cache")
      fi
    done < <(jq -c '.channels[] | select(.enabled == true)' <<<"$config")
  fi

  local ended duration error_text="" successful_at="" successful_epoch="$last_epoch"
  ended="$(date +%s%3N)"
  duration=$((ended - started))
  if (( ${#errors[@]} > 0 )); then
    error_text="$(IFS='; '; printf '%s' "${errors[*]}")"
  elif [[ $refresh_needed == true ]]; then
    successful_at="$(utc_now)"
    successful_epoch="$now"
  else
    successful_at="$(jq -r '.lastSuccessfulRefresh // ""' "$REFRESH_STATE" 2>/dev/null || true)"
  fi
  if [[ -z $successful_at && -f $REFRESH_STATE ]]; then
    successful_at="$(jq -r '.lastSuccessfulRefresh // ""' "$REFRESH_STATE" 2>/dev/null || true)"
  fi
  jq -cn --arg lastSuccessfulRefresh "$successful_at" \
    --argjson lastSuccessfulEpoch "${successful_epoch:-0}" \
    --arg lastRefreshError "$error_text" --argjson refreshDurationMs "$duration" \
    '{lastSuccessfulRefresh:$lastSuccessfulRefresh,
      lastSuccessfulEpoch:$lastSuccessfulEpoch,
      lastRefreshError:$lastRefreshError,
      refreshDurationMs:$refreshDurationMs}' | atomic_write_stream "$REFRESH_STATE"

  local snapshot
  snapshot="$(build_snapshot "$root" "$config")" || return 1
  if [[ -n $error_text ]]; then
    printf '%s\n' "$snapshot"
    return 1
  fi
  printf '%s\n' "$snapshot"
}

snapshot_is_current() {
  local path="$1"
  [[ -f $path && ! -L $path ]] && jq -e '
    .ok == true
    and (.snapshotId | type == "string" and length > 0)
    and (.records | type == "array")
    and .config.version == 2
    and (.config.settings | type == "object")
    and (.config.settings | keys == ["tray-icon-hidden"])
    and (.config.settings["tray-icon-hidden"] | type == "boolean")
  ' "$path" >/dev/null 2>&1
}

cached_command() {
  local root="$1"
  if snapshot_is_current "$SNAPSHOT_STATE"; then
    cat "$SNAPSHOT_STATE"
    return
  fi
  build_snapshot "$root"
}
