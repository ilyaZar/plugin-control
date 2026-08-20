readonly UPDATE_CHECK_JOBS=4
readonly MANUAL_UPDATE_REASON="Manually copied/installed plugin. No Git repository to update."
readonly DIRTY_UPDATE_REASON="This plugin has local changes. Commit or stash them before updating."
readonly AHEAD_UPDATE_REASON="This plugin is ahead of upstream and cannot be updated safely."
readonly DIVERGED_UPDATE_REASON="This plugin has diverged from upstream and cannot be updated safely."
readonly UNSUPPORTED_UPDATE_REASON="This Git checkout layout is not supported by the native Omarchy plugin updater."

default_update_state() {
  jq -cn '{lastSuccessfulCheck:"",lastSuccessfulEpoch:0,
    lastCheckAttempt:"",lastCheckError:"",lastCheckNotice:"",
    checkDurationMs:0,
    counts:{checked:0,available:0,current:0,manual:0,dirty:0,
      ahead:0,diverged:0,unsupported:0,failed:0},records:[]}'
}

load_update_state() {
  if [[ -f $UPDATE_STATE && ! -L $UPDATE_STATE ]] \
    && jq -e 'type == "object" and (.records | type == "array")' \
      "$UPDATE_STATE" >/dev/null 2>&1; then
    jq -c . "$UPDATE_STATE"
  else
    default_update_state
  fi
}

update_result() {
  local id="$1"
  local status="$2"
  local git_managed="$3"
  local dirty="$4"
  local local_commit="${5:-}"
  local remote_commit="${6:-}"
  local reason="${7:-}"
  local available=false
  [[ $status == available ]] && available=true
  jq -cn --arg id "$id" --arg status "$status" \
    --argjson gitManaged "$git_managed" --argjson dirty "$dirty" \
    --argjson updateAvailable "$available" \
    --arg localCommit "$local_commit" --arg remoteCommit "$remote_commit" \
    --arg reason "$reason" --arg checkedAt "$(utc_now)" \
    '{id:$id,status:$status,gitManaged:$gitManaged,dirty:$dirty,
      updateAvailable:$updateAvailable,localCommit:$localCommit,
      remoteCommit:$remoteCommit,reason:$reason,checkedAt:$checkedAt}'
}

classify_plugin_update() {
  local id="$1"
  local path="$2"
  local local_commit=""
  local remote_commit=""
  local relation_rc
  local porcelain

  # Match the native updater, which accepts only a .git directory.
  if [[ -f $path/.git ]]; then
    local_commit="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    update_result "$id" unsupported true false "$local_commit" "" \
      "$UNSUPPORTED_UPDATE_REASON"
    return
  fi
  if [[ ! -d $path/.git ]]; then
    update_result "$id" manual false false "" "" "$MANUAL_UPDATE_REASON"
    return
  fi
  if ! local_commit="$(git -C "$path" rev-parse HEAD 2>/dev/null)" \
    || [[ ! $local_commit =~ ^[0-9a-f]{40,64}$ ]]; then
    update_result "$id" error true false "" "" \
      "The local Git commit could not be read."
    return 1
  fi
  if ! porcelain="$(git -C "$path" status --porcelain \
      --untracked-files=normal 2>/dev/null)"; then
    update_result "$id" error true false "$local_commit" "" \
      "The local Git state could not be read."
    return 1
  fi
  if [[ -n $porcelain ]]; then
    update_result "$id" dirty true true "$local_commit" "" \
      "$DIRTY_UPDATE_REASON"
    return
  fi
  if ! git -C "$path" remote get-url origin >/dev/null 2>&1; then
    update_result "$id" error true false "$local_commit" "" \
      "This Git checkout has no origin remote to check."
    return 1
  fi
  if ! timeout --signal=TERM --kill-after=3s 25s \
    git -C "$path" fetch --quiet origin HEAD 2>/dev/null; then
    update_result "$id" error true false "$local_commit" "" \
      "Fetching the upstream plugin commit failed."
    return 1
  fi
  if ! remote_commit="$(git -C "$path" rev-parse FETCH_HEAD 2>/dev/null)" \
    || [[ ! $remote_commit =~ ^[0-9a-f]{40,64}$ ]]; then
    update_result "$id" error true false "$local_commit" "" \
      "The fetched upstream commit could not be read."
    return 1
  fi
  if [[ $local_commit == "$remote_commit" ]]; then
    update_result "$id" current true false "$local_commit" \
      "$remote_commit" ""
    return
  fi
  if git -C "$path" merge-base --is-ancestor \
      "$local_commit" "$remote_commit" >/dev/null 2>&1; then
    update_result "$id" available true false "$local_commit" \
      "$remote_commit" ""
    return
  fi
  relation_rc=0
  git -C "$path" merge-base --is-ancestor \
    "$remote_commit" "$local_commit" >/dev/null 2>&1 || relation_rc=$?
  if (( relation_rc == 0 )); then
    update_result "$id" ahead true false "$local_commit" \
      "$remote_commit" "$AHEAD_UPDATE_REASON"
  elif (( relation_rc == 1 )); then
    update_result "$id" diverged true false "$local_commit" \
      "$remote_commit" "$DIVERGED_UPDATE_REASON"
  else
    update_result "$id" error true false "$local_commit" \
      "$remote_commit" "The plugin's Git history could not be compared."
    return 1
  fi
}

check_plugin_update() (
  local id="$1"
  local path="$2"
  local output="$3"
  local lock_path
  lock_path="$(plugin_lock_path "$id")" || return 1
  exec 7>>"$lock_path"
  if ! flock -w 30 7; then
    update_result "$id" error true false "" "" \
      "The plugin is busy with another action." >"$output"
    return 1
  fi
  classify_plugin_update "$id" "$path" >"$output"
)

update_counts() {
  jq -c '
    reduce .[] as $record (
      {checked:0,available:0,current:0,manual:0,dirty:0,
        ahead:0,diverged:0,unsupported:0,failed:0};
      .checked += 1
      | if $record.status == "available" then .available += 1
        elif $record.status == "current" then .current += 1
        elif $record.status == "manual" then .manual += 1
        elif $record.status == "dirty" then .dirty += 1
        elif $record.status == "ahead" then .ahead += 1
        elif $record.status == "diverged" then .diverged += 1
        elif $record.status == "unsupported" then .unsupported += 1
        elif $record.status == "error" then .failed += 1
        else . end)
  '
}

update_check_notice_text() {
  local counts="$1"
  local dirty ahead diverged unsupported
  dirty="$(jq -r '.dirty' <<<"$counts")"
  ahead="$(jq -r '.ahead' <<<"$counts")"
  diverged="$(jq -r '.diverged' <<<"$counts")"
  unsupported="$(jq -r '.unsupported' <<<"$counts")"
  local -a messages=()
  (( dirty == 0 )) || messages+=("$dirty dirty checkout(s)")
  (( ahead == 0 )) || messages+=("$ahead local-ahead checkout(s)")
  (( diverged == 0 )) || messages+=("$diverged diverged checkout(s)")
  (( unsupported == 0 )) \
    || messages+=("$unsupported unsupported checkout(s)")
  (IFS='; '; printf '%s' "${messages[*]}")
}

write_update_state() (
  local value="$1"
  exec 6>>"$UPDATE_STATE_LOCK"
  flock 6
  atomic_write_text "$UPDATE_STATE" "$value"
)

store_update_record() (
  local record="$1"
  local state records counts next
  exec 6>>"$UPDATE_STATE_LOCK"
  flock 6
  state="$(load_update_state)"
  records="$(jq -c --argjson record "$record" '
    [.records[] | select(.id != $record.id)] + [$record]
  ' <<<"$state")"
  counts="$(update_counts <<<"$records")"
  next="$(jq -c --argjson records "$records" --argjson counts "$counts" '
    .records = $records | .counts = $counts
  ' <<<"$state")"
  atomic_write_text "$UPDATE_STATE" "$next"
)

remove_update_record() (
  local id="$1"
  local state records counts next
  exec 6>>"$UPDATE_STATE_LOCK"
  flock 6
  state="$(load_update_state)"
  records="$(jq -c --arg id "$id" '
    [.records[] | select(.id != $id)]
  ' <<<"$state")"
  counts="$(update_counts <<<"$records")"
  next="$(jq -c --argjson records "$records" --argjson counts "$counts" '
    .records = $records | .counts = $counts
  ' <<<"$state")"
  atomic_write_text "$UPDATE_STATE" "$next"
)

check_updates_command() (
  local root="$1"
  local stage=""
  trap '[[ -z $stage ]] || rm -rf -- "$stage"' EXIT
  exec 5>>"$UPDATE_LOCK"
  if ! flock -n 5; then
    json_error "an update check is already running"
    return 1
  fi
  exec 8>>"$ACTION_LOCK"
  if ! flock -n 8; then
    json_error "a plugin action is already running"
    return 1
  fi
  if [[ -f $ACTION_STATE && ! -L $ACTION_STATE ]] \
    && jq -e '.running == true' "$ACTION_STATE" >/dev/null 2>&1; then
    json_error "a plugin action is already running"
    return 1
  fi

  local started now installed results
  local active=0 expected_count=0
  started="$(date +%s%3N)"
  now="$(epoch_now)"
  stage="$(mktemp -d "$RUNTIME_ROOT/update-check.XXXXXX")"
  installed="$stage/installed.jsonl"
  results="$stage/results.jsonl"
  : >"$results"
  if ! installed_records "$installed" "$stage"; then
    json_error "installed plugins could not be inspected"
    return 1
  fi

  local record id path output
  while IFS= read -r record; do
    id="$(jq -r '.id' <<<"$record")"
    path="$(jq -r '.installedPath // ""' <<<"$record")"
    [[ -n $path ]] || continue
    expected_count=$((expected_count + 1))
    output="$stage/result-$id.json"
    check_plugin_update "$id" "$path" "$output" &
    active=$((active + 1))
    if (( active >= UPDATE_CHECK_JOBS )); then
      wait || true
      active=0
    fi
  done < <(jq -c 'select(.installed == true and .builtIn != true)' \
    "$installed")
  wait || true

  local result_file
  for result_file in "$stage"/result-*.json; do
    [[ -f $result_file ]] || continue
    cat "$result_file" >>"$results"
  done
  local records_json counts notice_text attempted_at
  if ! records_json="$(jq -sc 'sort_by(.id)' "$results")" \
    || (( $(jq -r 'length' <<<"$records_json") != expected_count )); then
    json_error "one or more installed plugins could not be inspected"
    return 1
  fi
  counts="$(update_counts <<<"$records_json")"
  notice_text="$(update_check_notice_text "$counts")"
  attempted_at="$(utc_now)"
  local duration state
  duration=$(( $(date +%s%3N) - started ))
  state="$(jq -cn --arg lastSuccessfulCheck "$attempted_at" \
    --argjson lastSuccessfulEpoch "$now" \
    --arg lastCheckAttempt "$attempted_at" --arg lastCheckError "" \
    --arg lastCheckNotice "$notice_text" \
    --argjson checkDurationMs "$duration" --argjson counts "$counts" \
    --argjson records "$records_json" \
    '{lastSuccessfulCheck:$lastSuccessfulCheck,
      lastSuccessfulEpoch:$lastSuccessfulEpoch,
      lastCheckAttempt:$lastCheckAttempt,lastCheckError:$lastCheckError,
      lastCheckNotice:$lastCheckNotice,
      checkDurationMs:$checkDurationMs,counts:$counts,records:$records}')"
  write_update_state "$state"
  local snapshot
  snapshot="$(build_snapshot "$root")" || return 1
  rm -rf -- "$stage"
  stage=""
  printf '%s\n' "$snapshot"
)
