default_action_status() {
  jq -cn '{ok:true,running:false,acknowledged:true,actionId:"",operation:"",
    pluginId:"",executionMode:"",startedAt:"",finishedAt:"",
    message:"No action has run.",output:""}'
}

write_action_status() {
  atomic_write_text "$ACTION_STATE" "$1"
}

cleanup_action_worker() {
  local action_id="$1"
  [[ $action_id =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9]+$ ]] || return 1
  rm -rf -- "$STATE_ROOT/worker/plugin-control-$action_id"
}

status_command() {
  local status
  if [[ ! -f $ACTION_STATE || -L $ACTION_STATE ]] \
    || ! status="$(jq -c . "$ACTION_STATE" 2>/dev/null)"; then
    default_action_status
    return
  fi
  if ! jq -e '.running == true' <<<"$status" >/dev/null; then
    printf '%s\n' "$status"
    return
  fi
  if jq -e '.handoff == true' <<<"$status" >/dev/null 2>&1; then
    local queued_epoch now
    queued_epoch="$(jq -r '.queuedAtEpoch // 0' <<<"$status")"
    now="$(epoch_now)"
    if [[ $queued_epoch =~ ^[0-9]+$ ]] \
      && (( now >= queued_epoch && now - queued_epoch < 10 )); then
      printf '%s\n' "$status"
      return
    fi
  fi
  exec 7>>"$ACTION_LOCK"
  if ! flock -n 7; then
    printf '%s\n' "$status"
    return
  fi
  status="$(jq -c --arg finishedAt "$(utc_now)" '
    .ok=false | .running=false | .finishedAt=$finishedAt
    | .message="The detached action worker stopped before completing."
    | .acknowledged=false | .abandoned=true
  ' <<<"$status")"
  write_action_status "$status" || true
  cleanup_action_worker "$(jq -r '.actionId // ""' <<<"$status")" || true
  printf '%s\n' "$status"
}

sanitize_output() {
  local file="$1"
  sed -E $'s/\x1B\[[0-9;?]*[ -/]*[@-~]//g' "$file" \
    | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' \
    | tail -c 12000
}

action_snapshot_record() {
  local snapshot="$1"
  local id="$2"
  jq -ce --arg id "$id" '[.records[] | select(.id == $id)][0] // empty' "$snapshot"
}

preflight_remove() {
  local record="$1"
  local id="$2"
  jq -e '.installed == true and .removable == true and .builtIn != true' \
    <<<"$record" >/dev/null || return 1
  local path expected manifest_id
  path="$(jq -r '.installedPath // ""' <<<"$record")"
  expected="$PLUGINS_ROOT/$id"
  [[ -n $path && $path == "$expected" && $(dirname -- "$path") == "$PLUGINS_ROOT"
    && ( -e $path || -L $path ) && -f $path/manifest.json ]] || return 1
  manifest_id="$(jq -r '.id // ""' "$path/manifest.json" 2>/dev/null || true)"
  [[ $manifest_id == "$id" ]] || return 1
  if [[ -d $path/.git || -f $path/.git ]] \
    && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && [[ -n $(git -C "$path" status --porcelain --untracked-files=normal 2>/dev/null) ]]; then
    return 2
  fi
}

submission_commit_current() {
  local record="$1"
  local url slug stage repo_json commit_json branch encoded_branch current expected
  url="$(jq -r '.repository' <<<"$record")"
  slug="$(github_slug "$url")" || return 1
  expected="$(jq -r '.commit // ""' <<<"$record")"
  [[ $expected =~ ^[0-9a-f]{40}$ ]] || return 1
  stage="$(mktemp -d "$RUNTIME_ROOT/action-commit.XXXXXX")"
  repo_json="$stage/repo.json"
  commit_json="$stage/commit.json"
  github_get "https://api.github.com/repos/$slug" "$repo_json" || {
    rm -rf -- "$stage"
    return 1
  }
  branch="$(jq -r '.default_branch // ""' "$repo_json")"
  encoded_branch="$(jq -rn --arg value "$branch" '$value | @uri')"
  github_get "https://api.github.com/repos/$slug/commits/$encoded_branch" "$commit_json" || {
    rm -rf -- "$stage"
    return 1
  }
  current="$(jq -r '.sha // ""' "$commit_json")"
  rm -rf -- "$stage"
  [[ $current == "$expected" ]]
}

set_action_result() {
  ACTION_SUCCEEDED="$1"
  ACTION_MESSAGE="$2"
}

write_running_action_status() {
  local message="$1"
  local stage="$2"
  local status
  status="$(jq -cn --arg actionId "$CURRENT_ACTION_ID" \
    --arg operation "$CURRENT_OPERATION" --arg pluginId "$CURRENT_PLUGIN_ID" \
    --arg executionMode "$CURRENT_EXECUTION_MODE" \
    --arg startedAt "$CURRENT_STARTED_AT" --arg message "$message" \
    --arg stage "$stage" \
    '{ok:true,running:true,acknowledged:false,actionId:$actionId,
      operation:$operation,pluginId:$pluginId,executionMode:$executionMode,
      handoff:false,startedAt:$startedAt,finishedAt:"",message:$message,
      stage:$stage,output:""}')"
  write_action_status "$status"
}

plugin_action_subject() {
  local record="$1"
  local name
  name="$(jq -r '
    (if (.name // "") != "" then .name else (.id // "plugin") end)
    | gsub("[\\r\\n\\t]+"; " ") | gsub("  +"; " ")
  ' <<<"$record")"
  if [[ $name == Plugin\ * ]]; then
    printf '%s\n' "$name"
  else
    printf 'Plugin %s\n' "$name"
  fi
}

finish_plugin_activation() {
  local output_file="$1"
  local success_message="$2"
  local changed_message="$3"
  local failure_message
  local rc=0

  timeout --signal=TERM --kill-after=5s 30s \
    omarchy restart shell >>"$output_file" 2>&1 || rc=$?
  if (( rc == 0 )); then
    set_action_result true "$success_message"
  else
    printf '\nOmarchy Shell restart failed with exit code %d.\n' "$rc" \
      >>"$output_file"
    failure_message="$changed_message, but Omarchy Shell could not restart, "
    failure_message+="so activation is incomplete. Run omarchy restart shell."
    set_action_result false "$failure_message"
  fi
}

run_add_action() {
  local record="$1"
  local snapshot="$2"
  local execution_mode="$3"
  local output_file="$4"
  local plugin_subject repository source allow_unlisted rc
  plugin_subject="$(plugin_action_subject "$record")"
  repository="$(jq -r '.repository // ""' <<<"$record")"
  source="$(jq -r '.source // ""' <<<"$record")"
  allow_unlisted="$(jq -r '.config.allow_unlisted_installs // false' \
    "$snapshot")"

  if ! jq -e '.installable == true and .installed != true' \
    <<<"$record" >/dev/null || ! valid_github_repository_url "$repository"; then
    set_action_result false \
      "The confirmed record has no supported add path."
  elif [[ $source == submission && $allow_unlisted != true ]]; then
    set_action_result false \
      "Adding unlisted plugins is disabled in Plugin Control settings."
  elif [[ $source == submission && $execution_mode == terminal ]]; then
    set_action_result false \
      "Unlisted installs require the reviewed background path."
  elif [[ $source == submission ]] \
    && ! submission_commit_current "$record"; then
    set_action_result false \
      "The unlisted repository changed after review; refresh and confirm it again."
  elif [[ $execution_mode == terminal ]]; then
    if omarchy plugin add "$repository" --enable; then
      finish_plugin_activation "$output_file" \
        "$plugin_subject added and enabled in the Omarchy terminal." \
        "$plugin_subject was added and enabled"
    else
      rc=$?
      set_action_result false "Plugin add failed with exit code $rc."
    fi
  elif timeout --signal=TERM --kill-after=5s 300s \
    omarchy plugin add "$repository" --enable --yes \
      >"$output_file" 2>&1; then
    finish_plugin_activation "$output_file" \
      "$plugin_subject added and enabled." \
      "$plugin_subject was added and enabled"
  else
    rc=$?
    set_action_result false "Plugin add failed with exit code $rc."
  fi
}

run_remove_action() {
  local root="$1"
  local record="$2"
  local id="$3"
  local operation="$4"
  local execution_mode="$5"
  local output_file="$6"
  local plugin_subject rc

  plugin_subject="$(plugin_action_subject "$record")"

  if preflight_remove "$record" "$id"; then
    :
  else
    rc=$?
    if (( rc == 2 )); then
      set_action_result false \
        "Removal refused because the Git checkout has local changes."
    else
      set_action_result false \
        "Removal refused because the installed identity or path changed."
    fi
    return
  fi
  if [[ $operation == remove-purge ]] \
    && [[ $id != "$SELF_ID" || $execution_mode != background ]]; then
    set_action_result false \
      "Clean removal is supported only for Plugin Control."
  elif [[ $operation == remove-purge ]] && ! purge_user_data "$root"; then
    set_action_result false \
      "Plugin Control user data could not be removed safely."
  elif timeout --signal=TERM --kill-after=5s 300s \
    omarchy plugin remove "$id" --yes >"$output_file" 2>&1; then
    if [[ $operation == remove-purge ]]; then
      set_action_result true "Plugin Control and its user data were removed."
    else
      set_action_result true "$plugin_subject removed."
    fi
  else
    rc=$?
    if [[ $id == "$SELF_ID" && ! -e $PLUGINS_ROOT/$id
        && ! -L $PLUGINS_ROOT/$id ]]; then
      set_action_result true \
        "$plugin_subject removed, but Omarchy reported a shell refresh error."
    else
      set_action_result false "Plugin removal failed with exit code $rc."
    fi
  fi
}

run_switch_action() {
  local record="$1"
  local id="$2"
  local operation="$3"
  local output_file="$4"
  local plugin_subject success_message rc
  local -a command

  if ! jq -e '.builtIn == true or .installed == true' \
      <<<"$record" >/dev/null; then
    set_action_result false \
      "The confirmed plugin does not support enable or disable."
    return
  fi
  plugin_subject="$(plugin_action_subject "$record")"
  case "$operation" in
    enable)
      if ! jq -e '.enabled == false' <<<"$record" >/dev/null; then
        set_action_result false "The confirmed plugin is already enabled."
        return
      fi
      if ! jq -e '.canDisable == true or .fullBar == true' \
          <<<"$record" >/dev/null; then
        set_action_result false \
          "The confirmed plugin does not support enable or disable."
        return
      fi
      command=(omarchy plugin enable "$id")
      success_message="$plugin_subject enabled."
      ;;
    disable)
      if ! jq -e '.enabled == true' <<<"$record" >/dev/null; then
        set_action_result false "The confirmed plugin is already disabled."
        return
      fi
      if ! jq -e '.canDisable == true' <<<"$record" >/dev/null; then
        set_action_result false \
          "The confirmed plugin does not support enable or disable."
        return
      fi
      command=(omarchy plugin disable "$id")
      success_message="$plugin_subject disabled."
      ;;
  esac
  if timeout --signal=TERM --kill-after=2s 30s \
    "${command[@]}" >"$output_file" 2>&1; then
    set_action_result true "$success_message"
  else
    rc=$?
    set_action_result false \
      "Plugin state change failed with exit code $rc."
  fi
}

run_update_action() {
  local record="$1"
  local id="$2"
  local output_file="$3"
  local path expected manifest_id classification status reason rc current
  local current_commit plugin_subject

  if ! jq -e '.installed == true and .builtIn != true' \
    <<<"$record" >/dev/null; then
    set_action_result false \
      "The confirmed plugin is not an added user plugin."
    return
  fi
  plugin_subject="$(plugin_action_subject "$record")"
  path="$(jq -r '.installedPath // ""' <<<"$record")"
  expected="$PLUGINS_ROOT/$id"
  [[ -n $path && $path == "$expected" && $(dirname -- "$path") == "$PLUGINS_ROOT"
    && ( -e $path || -L $path ) && -f $path/manifest.json ]] || {
    set_action_result false \
      "Update refused because the installed identity or path changed."
    return
  }
  manifest_id="$(jq -r '.id // ""' "$path/manifest.json" 2>/dev/null || true)"
  [[ $manifest_id == "$id" ]] || {
    set_action_result false \
      "Update refused because the installed identity or path changed."
    return
  }

  write_running_action_status "Checking for updates..." checking
  classification="$(classify_plugin_update "$id" "$path")" || true
  [[ -n $classification ]] || classification="$(update_result "$id" error \
    true false "" "" "The plugin could not be checked for updates.")"
  store_update_record "$classification" || true
  status="$(jq -r '.status // "error"' <<<"$classification")"
  reason="$(jq -r '.reason // ""' <<<"$classification")"
  case "$status" in
    current)
      set_action_result true "Plugin already up-to-date!"
      ;;
    available)
      write_running_action_status "Updating plugins..." updating
      if timeout --signal=TERM --kill-after=5s 300s \
        omarchy plugin update "$id" --yes >"$output_file" 2>&1; then
        current_commit="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
        current="$(jq -c --arg currentCommit "$current_commit" '
          .status="current" | .updateAvailable=false | .reason=""
          | .localCommit=$currentCommit | .remoteCommit=$currentCommit
          | .checkedAt=$checkedAt
        ' --arg checkedAt "$(utc_now)" <<<"$classification")"
        store_update_record "$current" || true
        finish_plugin_activation "$output_file" \
          "$plugin_subject updated!" "$plugin_subject updated"
      else
        rc=$?
        set_action_result false "Plugin update failed with exit code $rc."
      fi
      ;;
    manual|dirty|ahead|diverged|unsupported|error)
      [[ -n $reason ]] || reason="The plugin cannot be updated safely."
      set_action_result false "$reason"
      ;;
    *)
      set_action_result false "The plugin update state is not supported."
      ;;
  esac
}

execute_action() {
  local root="$1"
  local record="$2"
  local snapshot="$3"
  local operation="$4"
  local id="$5"
  local execution_mode="$6"
  local output_file="$7"
  set_action_result false "Unsupported action."
  if [[ -z $record ]]; then
    set_action_result false \
      "The confirmed plugin record is no longer available."
  elif [[ $operation == add ]]; then
    run_add_action "$record" "$snapshot" "$execution_mode" "$output_file"
  elif [[ $operation == remove || $operation == remove-purge ]]; then
    run_remove_action "$root" "$record" "$id" "$operation" \
      "$execution_mode" "$output_file"
  elif [[ $operation == enable || $operation == disable ]]; then
    run_switch_action "$record" "$id" "$operation" "$output_file"
  elif [[ $operation == update ]]; then
    run_update_action "$record" "$id" "$output_file"
  fi
}

finish_action() {
  local root="$1"
  local action_id="$2"
  local operation="$3"
  local id="$4"
  local execution_mode="$5"
  local started="$6"
  local output_file="$7"
  local output="" acknowledged=false status title

  if [[ -s $output_file ]]; then
    output="$(sanitize_output "$output_file")"
  fi
  rm -f -- "$output_file"
  if [[ $ACTION_SUCCEEDED == true \
      && ( $operation == remove || $operation == remove-purge ) ]]; then
    remove_update_record "$id" || true
  fi
  if [[ $ACTION_SUCCEEDED == true && $operation == remove-purge \
      && $id == "$SELF_ID" ]]; then
    command -v omarchy-notification-send >/dev/null 2>&1 \
      && omarchy-notification-send "Plugin Control" "$ACTION_MESSAGE" \
        >/dev/null 2>&1 || true
    rm -rf -- "$STATE_ROOT" "$RUNTIME_ROOT"
    return 0
  elif [[ $ACTION_SUCCEEDED == true && $operation == remove \
      && $id == "$SELF_ID" ]]; then
    acknowledged=true
    rm -f -- "$SNAPSHOT_STATE"
  else
    build_snapshot "$root" >/dev/null 2>&1 || true
  fi
  status="$(jq -cn --argjson ok "$ACTION_SUCCEEDED" \
    --argjson acknowledged "$acknowledged" --arg actionId "$action_id" \
    --arg operation "$operation" --arg pluginId "$id" \
    --arg executionMode "$execution_mode" --arg startedAt "$started" \
    --arg finishedAt "$(utc_now)" --arg message "$ACTION_MESSAGE" \
    --arg output "$output" \
    '{ok:$ok,running:false,acknowledged:$acknowledged,actionId:$actionId,
      operation:$operation,pluginId:$pluginId,executionMode:$executionMode,
      handoff:false,startedAt:$startedAt,finishedAt:$finishedAt,
      message:$message,output:$output}')"
  write_action_status "$status" || return 1
  title="Plugin Control"
  [[ $ACTION_SUCCEEDED == true ]] || title="Plugin Control action failed"
  command -v omarchy-notification-send >/dev/null 2>&1 \
    && omarchy-notification-send "$title" "$ACTION_MESSAGE" \
      >/dev/null 2>&1 || true
  if [[ $execution_mode == terminal ]]; then
    exec 9>&-
    printf '\n%s\n' "$ACTION_MESSAGE"
    printf 'Press Enter to close this terminal. '
    IFS= read -r _ || true
  fi
  [[ $ACTION_SUCCEEDED == true ]]
}

worker_command() {
  local root="$1"
  local action_id="$2"
  local operation="$3"
  local id="$4"
  local snapshot="$5"
  local execution_mode="$6"
  local started status record output_file
  ACTION_WORKER_CLEANUP_ID="$action_id"
  trap 'cleanup_action_worker "$ACTION_WORKER_CLEANUP_ID" || true' EXIT
  exec 9>>"$ACTION_LOCK"
  if ! flock -w 8 9; then
    if [[ $execution_mode == terminal ]]; then
      printf 'Another Plugin Control action is still running.\n'
      printf 'Press Enter to close this terminal. '
      IFS= read -r _ || true
    fi
    return 1
  fi
  if [[ ! -f $ACTION_STATE || -L $ACTION_STATE ]] \
    || ! jq -e --arg actionId "$action_id" \
      '.running == true and .actionId == $actionId' \
      "$ACTION_STATE" >/dev/null 2>&1; then
    if [[ $execution_mode == terminal ]]; then
      exec 9>&-
      printf 'This add request is no longer current.\n'
      printf 'Press Enter to close this terminal. '
      IFS= read -r _ || true
    fi
    return 1
  fi
  started="$(utc_now)"
  CURRENT_ACTION_ID="$action_id"
  CURRENT_OPERATION="$operation"
  CURRENT_PLUGIN_ID="$id"
  CURRENT_EXECUTION_MODE="$execution_mode"
  CURRENT_STARTED_AT="$started"
  local running_message="Working..." running_stage="working"
  if [[ $operation == update ]]; then
    running_message="Checking for updates..."
    running_stage="checking"
  fi
  status="$(jq -cn --arg actionId "$action_id" --arg operation "$operation" \
    --arg pluginId "$id" --arg executionMode "$execution_mode" \
    --arg startedAt "$started" --arg message "$running_message" \
    --arg stage "$running_stage" \
    '{ok:true,running:true,acknowledged:false,actionId:$actionId,
      operation:$operation,pluginId:$pluginId,executionMode:$executionMode,
      handoff:false,startedAt:$startedAt,finishedAt:"",message:$message,
      stage:$stage,output:""}')"
  write_action_status "$status" || return 1
  record="$(action_snapshot_record "$snapshot" "$id" 2>/dev/null || true)"
  output_file="$(mktemp "$RUNTIME_ROOT/.action-output.XXXXXX")"
  local plugin_lock
  plugin_lock="$(plugin_lock_path "$id")" || return 1
  exec 8>>"$plugin_lock"
  if flock -w 35 8; then
    execute_action "$root" "$record" "$snapshot" "$operation" "$id" \
      "$execution_mode" "$output_file"
  else
    set_action_result false "The plugin is busy with another operation."
  fi
  finish_action "$root" "$action_id" "$operation" "$id" \
    "$execution_mode" "$started" "$output_file"
}

validate_action_request() {
  local operation="$1"
  local id="$2"
  local confirmed_snapshot_id="$3"
  local execution_mode="$4"
  valid_plugin_id "$id" || {
    json_error "a valid plugin ID is required"
    return 2
  }
  [[ $operation == add || $operation == remove \
    || $operation == remove-purge || $operation == enable
    || $operation == disable || $operation == update ]] || {
    json_error "unsupported plugin operation"
    return 2
  }
  [[ $execution_mode == background || $execution_mode == terminal ]] || {
    json_error "unsupported action execution mode"
    return 2
  }
  [[ $execution_mode != terminal || $operation == add ]] || {
    json_error "terminal mode is supported only when adding plugins"
    return 2
  }
  if [[ $execution_mode == terminal ]]; then
    require_tool omarchy-launch-terminal
  fi
  if ! snapshot_is_current "$SNAPSHOT_STATE" \
    || ! jq -e --arg snapshotId "$confirmed_snapshot_id" \
      '.snapshotId == $snapshotId' "$SNAPSHOT_STATE" >/dev/null; then
    json_error "the catalog changed after confirmation"
    return 1
  fi
}

acquire_action_lock() {
  exec 9>>"$ACTION_LOCK"
  if ! flock -n 9; then
    jq -cn '{ok:false,busy:true,error:"another plugin action is already running"}'
    return 1
  fi
  if [[ -f $ACTION_STATE && ! -L $ACTION_STATE ]] \
    && jq -e '.running == true' "$ACTION_STATE" >/dev/null 2>&1; then
    local previous queued_epoch now
    previous="$(jq -c . "$ACTION_STATE")"
    queued_epoch="$(jq -r '.queuedAtEpoch // 0' <<<"$previous")"
    now="$(epoch_now)"
    if jq -e '.handoff == true' <<<"$previous" >/dev/null 2>&1 \
      && [[ $queued_epoch =~ ^[0-9]+$ ]] \
      && (( now >= queued_epoch && now - queued_epoch < 10 )); then
      jq -cn '{ok:false,busy:true,error:"another plugin action is starting"}'
      return 1
    fi
  fi
}

stage_action_worker() {
  local action_id="$1"
  local confirmed_snapshot_id="$2"
  local module
  STAGED_WORKER_ROOT="$STATE_ROOT/worker/plugin-control-$action_id"
  STAGED_WORKER="$STAGED_WORKER_ROOT/bin/plugin-control"
  STAGED_SNAPSHOT="$STAGED_WORKER_ROOT/snapshot.json"
  mkdir -p -- "$STAGED_WORKER_ROOT/bin" \
    "$STAGED_WORKER_ROOT/lib/backend"
  [[ ! -L $STATE_ROOT/worker && ! -L $STAGED_WORKER_ROOT
    && $(realpath -m -- "$STAGED_WORKER_ROOT") == "$STAGED_WORKER_ROOT" ]] || {
    json_error "the action worker directory is unsafe"
    return 1
  }
  install -m 0700 -- "$SCRIPT_PATH" "$STAGED_WORKER"
  for module in common config catalog updates snapshot actions lifecycle; do
    install -m 0600 -- "$BACKEND_ROOT/$module.sh" \
      "$STAGED_WORKER_ROOT/lib/backend/$module.sh"
  done
  atomic_write_stream "$STAGED_SNAPSHOT" <"$SNAPSHOT_STATE"
  if ! snapshot_is_current "$STAGED_SNAPSHOT" \
    || ! jq -e --arg snapshotId "$confirmed_snapshot_id" \
      '.snapshotId == $snapshotId' "$STAGED_SNAPSHOT" >/dev/null; then
    rm -rf -- "$STAGED_WORKER_ROOT"
    json_error "the catalog changed after confirmation"
    return 1
  fi
}

queue_action() {
  local action_id="$1"
  local operation="$2"
  local id="$3"
  local execution_mode="$4"
  local queued
  queued="$(jq -cn --arg actionId "$action_id" --arg operation "$operation" \
    --arg pluginId "$id" --arg executionMode "$execution_mode" \
    --argjson queuedAtEpoch "$(epoch_now)" \
    '{ok:true,running:true,acknowledged:false,actionId:$actionId,
      operation:$operation,pluginId:$pluginId,executionMode:$executionMode,
      handoff:true,queuedAtEpoch:$queuedAtEpoch,startedAt:"",finishedAt:"",
      message:"Queued...",output:""}')"
  write_action_status "$queued"
}

launch_action_worker() {
  local root="$1"
  local action_id="$2"
  local operation="$3"
  local id="$4"
  local execution_mode="$5"
  local pid
  if [[ -f $ACTION_LOG && ! -L $ACTION_LOG ]]; then
    tail -c 65536 "$ACTION_LOG" >"$ACTION_LOG.tmp" 2>/dev/null || true
    mv -fT -- "$ACTION_LOG.tmp" "$ACTION_LOG" 2>/dev/null || true
  fi
  if [[ $execution_mode == terminal ]]; then
    omarchy-launch-terminal bash "$STAGED_WORKER" _worker "$root" \
      "$action_id" "$operation" "$id" "$STAGED_SNAPSHOT" "$execution_mode" \
      9>&- </dev/null >>"$ACTION_LOG" 2>&1 &
  else
    setsid bash "$STAGED_WORKER" _worker "$root" "$action_id" \
      "$operation" "$id" "$STAGED_SNAPSHOT" "$execution_mode" \
      9>&- </dev/null >>"$ACTION_LOG" 2>&1 &
  fi
  pid=$!
  exec 9>&-
  jq -cn --arg actionId "$action_id" --argjson pid "$pid" \
    '{ok:true,started:true,actionId:$actionId,pid:$pid}'
}

action_command() {
  local root="$1"
  local operation="$2"
  local id="$3"
  local confirmed_snapshot_id="$4"
  local execution_mode="$5"
  local action_id
  validate_action_request "$operation" "$id" "$confirmed_snapshot_id" \
    "$execution_mode" || return $?
  acquire_action_lock || return $?
  action_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"
  stage_action_worker "$action_id" "$confirmed_snapshot_id" || return $?
  queue_action "$action_id" "$operation" "$id" "$execution_mode"
  launch_action_worker "$root" "$action_id" "$operation" "$id" \
    "$execution_mode"
}

ack_command() {
  local action_id="$1"
  [[ -f $ACTION_STATE && ! -L $ACTION_STATE ]] || {
    default_action_status
    return
  }
  local status
  status="$(jq -c --arg actionId "$action_id" '
    if .actionId == $actionId and .running == false
    then .acknowledged=true else error("action is not current or complete") end
  ' "$ACTION_STATE")" || {
    json_error "action is not current or complete"
    return 1
  }
  write_action_status "$status"
  printf '%s\n' "$status"
}

benchmark_command() {
  local root="$1"
  local started ended snapshot count
  started="$(date +%s%3N)"
  snapshot="$(cached_command "$root")" || return 1
  ended="$(date +%s%3N)"
  count="$(jq '.records | length' <<<"$snapshot")"
  jq -cn --argjson snapshotMs "$((ended - started))" --argjson recordCount "$count" \
    '{ok:true,snapshotMs:$snapshotMs,recordCount:$recordCount}'
}
