manifest_record() {
  local id="$1"
  local enabled="$2"
  local can_disable="$3"
  local path="$4"
  local manifest="$path/manifest.json"
  local dirty=false git_managed=false native_update_supported=false
  local repository="" local_commit=""
  [[ -f $manifest ]] || return 1
  [[ "$(jq -r '.id // ""' "$manifest" 2>/dev/null)" == "$id" ]] || return 1
  if [[ -d $path/.git || -f $path/.git ]] \
    && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_managed=true
    [[ -d $path/.git ]] && native_update_supported=true
    [[ -z $(git -C "$path" status --porcelain --untracked-files=normal 2>/dev/null) ]] || dirty=true
    local_commit="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    repository="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
    repository="$(normalize_github_url "$repository" 2>/dev/null || true)"
  fi

  jq -c \
    --arg id "$id" --arg path "$path" --arg repository "$repository" \
    --arg localCommit "$local_commit" \
    --argjson enabled "$enabled" --argjson canDisable "$can_disable" \
    --argjson dirty "$dirty" --argjson gitManaged "$git_managed" \
    --argjson nativeUpdateSupported "$native_update_supported" \
    --arg manualReason "$MANUAL_UPDATE_REASON" \
    --arg dirtyReason "$DIRTY_UPDATE_REASON" \
    --arg unsupportedReason "$UNSUPPORTED_UPDATE_REASON" '
      {
        id:$id,
        name:(.name // $id),
        description:(.description // ""),
        author:(.author // ""),
        version:(.version // ""),
        kinds:(.kinds // []),
        kind:((.kinds // []) | join(" + ")),
        fullBar:((.kinds // []) | index("bar") != null),
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
        gitManaged:$gitManaged,
        nativeUpdateSupported:$nativeUpdateSupported,
        localCommit:$localCommit,
        updateAvailable:false,
        updateStatus:(if $dirty then "dirty"
          elif $gitManaged and ($nativeUpdateSupported | not)
            then "unsupported"
          elif $gitManaged then "unknown" else "manual" end),
        updateReason:(if $dirty then $dirtyReason
          elif $gitManaged and ($nativeUpdateSupported | not)
            then $unsupportedReason
          elif $gitManaged then "" else $manualReason end),
        installedPath:$path
      }
      | with_entries(select(.value != ""))
    ' "$manifest"
}

channel_cache_valid() {
  local cache="$1"
  [[ -f $cache && ! -L $cache ]] \
    && jq -e '.ok == true and (.records | type == "array")' \
      "$cache" >/dev/null 2>&1
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
        kinds:(.kinds // []),
        kind:((.kinds // []) | if type == "array" then join(" + ") else "" end),
        fullBar:((.kinds // []) | if type == "array"
          then index("bar") != null else false end),
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
  local stage records_jsonl installed_jsonl merged_file base_merged_file
  local diagnostics_file config_file refresh_file update_file stats_file
  local snapshot_file snapshot_id
  stage="$(mktemp -d "$RUNTIME_ROOT/snapshot.XXXXXX")"
  records_jsonl="$stage/records.jsonl"
  installed_jsonl="$stage/installed.jsonl"
  : >"$records_jsonl"

  local channel channel_id cache marketplace_loaded=false
  while IFS= read -r channel; do
    channel_id="$(jq -r '.id' <<<"$channel")"
    cache="$CHANNEL_CACHE/$channel_id.json"
    if channel_cache_valid "$cache"; then
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

  base_merged_file="$stage/records-base.json"
  merged_file="$stage/records.json"
  diagnostics_file="$stage/diagnostics.json"
  config_file="$stage/config.json"
  refresh_file="$stage/refresh.json"
  update_file="$stage/updates.json"
  stats_file="$stage/stats.json"
  snapshot_file="$stage/snapshot.json"
  jq -sc '
    group_by(.id)
    | map(sort_by(.sourceRank // 0) | reduce .[] as $record ({}; . * $record))
    | sort_by((.name // .id | ascii_downcase), .id)
  ' "$records_jsonl" >"$base_merged_file"
  jq -sc '
    group_by(.id)
    | map({id:.[0].id,repositories:([.[].repository // ""] | map(select(length > 0)) | unique)})
    | map(select(.repositories | length > 1)
      | {type:"repository-collision",id,repositories})
  ' "$records_jsonl" >"$diagnostics_file"
  printf '%s\n' "$config" >"$config_file"

  load_update_state >"$update_file"
  if [[ -f $MARKETPLACE_STATS_CACHE && ! -L $MARKETPLACE_STATS_CACHE ]] \
    && jq -e '.schemaVersion == 1 and (.plugins | type == "object")' \
      "$MARKETPLACE_STATS_CACHE" >/dev/null 2>&1; then
    jq -c . "$MARKETPLACE_STATS_CACHE" >"$stats_file"
  else
    printf '{"schemaVersion":1,"plugins":{}}\n' >"$stats_file"
  fi
  jq -c --slurpfile updates "$update_file" --slurpfile stats "$stats_file" '
    ($updates[0].records // []
      | map({key:.id,value:.}) | from_entries) as $updatesById
    | ($stats[0].plugins // {}) as $statsById
    | map(
        . as $record
        | ($updatesById[.id] // null) as $update
        | ($statsById[.id] // null) as $metrics
        | if .installed == true and .gitManaged == true
            and .dirty != true and $update != null
            and $update.gitManaged == true
            and $update.localCommit == .localCommit
          then . + {
            updateAvailable:($update.updateAvailable == true),
            updateStatus:($update.status // "unknown"),
            updateReason:($update.reason // ""),
            remoteCommit:($update.remoteCommit // ""),
            updateCheckedAt:($update.checkedAt // "")
          }
          else . end
        | if .marketplaceListed == true and $metrics != null
          then . + {metricsAvailable:true,
            views:$metrics.views,copies:$metrics.copies,hearts:$metrics.hearts}
          else . + {metricsAvailable:false} end)
  ' "$base_merged_file" >"$merged_file"
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
    --slurpfile updates "$update_file" \
    '{ok:true,snapshotId:$snapshotId,generatedAt:$generatedAt,
      records:$records[0],diagnostics:$diagnostics[0],config:$config[0],
      cache:{lastSuccessfulRefresh:($refresh[0].lastSuccessfulRefresh // ""),
        refreshWarnings:(($refresh[0].refreshWarnings // [])
          | if type == "array" then . else [] end),
        refreshDurationMs:($refresh[0].refreshDurationMs // 0)},
      updates:{lastSuccessfulCheck:($updates[0].lastSuccessfulCheck // ""),
        lastCheckAttempt:($updates[0].lastCheckAttempt // ""),
        lastCheckError:($updates[0].lastCheckError // ""),
        lastCheckNotice:($updates[0].lastCheckNotice // ""),
        checkDurationMs:($updates[0].checkDurationMs // 0),
        counts:($updates[0].counts // {})}}' \
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

  local started now last_epoch=0 last_successful_at=""
  local ttl refresh_needed=true
  started="$(date +%s%3N)"
  now="$(epoch_now)"
  ttl=$(( $(jq -r '.refresh_minutes' <<<"$config") * 60 ))
  if [[ -f $REFRESH_STATE && ! -L $REFRESH_STATE ]]; then
    last_epoch="$(jq -r '.lastSuccessfulEpoch // 0' "$REFRESH_STATE" 2>/dev/null || printf 0)"
    last_successful_at="$(jq -r '.lastSuccessfulRefresh // ""' \
      "$REFRESH_STATE" 2>/dev/null || true)"
  fi
  [[ $last_epoch =~ ^[0-9]+$ ]] || last_epoch=0
  if [[ $force != --force ]]; then
    if (( now - last_epoch < ttl )); then
      refresh_needed=false
    fi
  fi

  local -a warnings=()
  local channel channel_id channel_name cache metadata fallback cache_retrieved_at
  if [[ $refresh_needed == true ]]; then
    while IFS= read -r channel; do
      channel_id="$(jq -r '.id' <<<"$channel")"
      channel_name="$(jq -r '.name' <<<"$channel")"
      if ! refresh_channel "$root" "$channel" "$config"; then
        cache="$CHANNEL_CACHE/$channel_id.json"
        metadata="$CHANNEL_CACHE/$channel_id.meta.json"
        fallback=none
        cache_retrieved_at=""
        if channel_cache_valid "$cache"; then
          fallback=cache
          if [[ -f $metadata && ! -L $metadata ]]; then
            cache_retrieved_at="$(jq -r '.retrievedAt // ""' \
              "$metadata" 2>/dev/null || true)"
          fi
        elif [[ $channel_id == marketplace ]]; then
          fallback=bundled
        fi
        warnings+=("$(jq -cn --arg channelId "$channel_id" \
          --arg channelName "$channel_name" --arg fallback "$fallback" \
          --arg cacheRetrievedAt "$cache_retrieved_at" \
          '{channelId:$channelId,channelName:$channelName,
            fallback:$fallback,cacheRetrievedAt:$cacheRetrievedAt}')")
      fi
    done < <(jq -c '.channels[] | select(.enabled == true)' <<<"$config")
    if jq -e 'any(.channels[];
        .enabled == true and .id == "marketplace")' \
      <<<"$config" >/dev/null; then
      refresh_marketplace_stats || true
    fi
  fi

  local ended duration refresh_warnings='[]'
  local successful_at="$last_successful_at" successful_epoch="$last_epoch"
  ended="$(date +%s%3N)"
  duration=$((ended - started))
  if (( ${#warnings[@]} > 0 )); then
    refresh_warnings="$(printf '%s\n' "${warnings[@]}" | jq -sc .)"
  elif [[ $refresh_needed == true ]]; then
    successful_at="$(utc_now)"
    successful_epoch="$now"
  fi
  jq -cn --arg lastSuccessfulRefresh "$successful_at" \
    --argjson lastSuccessfulEpoch "${successful_epoch:-0}" \
    --argjson refreshWarnings "$refresh_warnings" \
    --argjson refreshDurationMs "$duration" \
    '{lastSuccessfulRefresh:$lastSuccessfulRefresh,
      lastSuccessfulEpoch:$lastSuccessfulEpoch,
      refreshWarnings:$refreshWarnings,
      refreshDurationMs:$refreshDurationMs}' | atomic_write_stream "$REFRESH_STATE"

  build_snapshot "$root" "$config"
}

snapshot_is_current() {
  local path="$1"
  [[ -f $path && ! -L $path ]] && jq -e '
    .ok == true
    and (.snapshotId | type == "string" and length > 0)
    and (.records | type == "array")
    and .config.version == 2
    and (.config.settings | type == "object")
    and (.config.settings | keys == ["background_dim", "tray-icon-hidden"])
    and (.config.settings["tray-icon-hidden"] | type == "boolean")
    and (.config.settings.background_dim | type == "boolean")
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
