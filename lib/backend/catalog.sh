safe_header_value() {
  local value="${1:-}"
  [[ ${#value} -le 1024 && $value != *$'\n'* && $value != *$'\r'* ]]
}
header_value() {
  local name="$1"
  local file="$2"
  awk -v expected="$name" '
    BEGIN { IGNORECASE = 1 }
    $0 ~ "^" expected ":" {
      sub(/^[^:]+:[[:space:]]*/, "")
      sub(/\r$/, "")
      value = $0
    }
    END { print value }
  ' "$file"
}

normalize_catalog() {
  local root="$1"
  local raw="$2"
  local channel_name="$3"
  local source="$4"
  local rank="$5"
  jq -c \
    --arg channelName "$channel_name" \
    --arg channelSource "$source" \
    --argjson channelRank "$rank" \
    -f "$root/lib/catalog.jq" "$raw"
}

download_catalog() {
  local url="$1"
  local body="$2"
  local headers="$3"
  local etag="${4:-}"
  local modified="${5:-}"
  local -a request=(
    curl --silent --show-error --location
    --proto '=https' --proto-redir '=https'
    --connect-timeout 5 --max-time 20 --max-filesize 5242880
    --output "$body" --dump-header "$headers"
    --write-out '%{http_code}'
  )
  if [[ -n $etag ]] && safe_header_value "$etag"; then
    request+=(--header "If-None-Match: $etag")
  fi
  if [[ -n $modified ]] && safe_header_value "$modified"; then
    request+=(--header "If-Modified-Since: $modified")
  fi
  request+=(-- "$url")
  "${request[@]}"
}

download_marketplace_stats() {
  local body="$1"
  curl --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 20 --max-filesize 1048576 \
    --output "$body" --write-out '%{http_code}' -- \
    "https://api.omarchyplugins.com/v1/stats"
}

normalize_marketplace_stats() {
  local raw="$1"
  local retrieved_at="$2"
  jq -ce --arg retrievedAt "$retrieved_at" '
    def valid_id:
      type == "string" and length <= 128
      and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")
      and (contains("..") | not);
    def valid_count:
      type == "number" and floor == . and . >= 0 and . <= 1000000000000;
    if type != "object" or .schemaVersion != 1
      or (.plugins | type) != "object"
      or (.plugins | length) > 5000
      or (all(.plugins | to_entries[];
        (.key | valid_id)
        and (.value | type == "object"
          and keys == ["copies", "hearts", "views"]
          and (.copies | valid_count)
          and (.hearts | valid_count)
          and (.views | valid_count))) | not)
    then error("invalid marketplace stats")
    else {schemaVersion:1,retrievedAt:$retrievedAt,plugins:.plugins}
    end
  ' "$raw"
}

refresh_marketplace_stats() {
  local stage body normalized status
  stage="$(mktemp -d "$RUNTIME_ROOT/marketplace-stats.XXXXXX")"
  body="$stage/stats.json"
  status="$(download_marketplace_stats "$body")" || status="000"
  if [[ $status != 200 ]]; then
    rm -rf -- "$stage"
    return 1
  fi
  normalized="$(normalize_marketplace_stats "$body" "$(utc_now)" \
    2>/dev/null)" || {
    rm -rf -- "$stage"
    return 1
  }
  atomic_write_text "$MARKETPLACE_STATS_CACHE" "$normalized" || {
    rm -rf -- "$stage"
    return 1
  }
  rm -rf -- "$stage"
}

refresh_catalog_channel() {
  local root="$1"
  local channel="$2"
  local normalizer_version=3
  local channel_id channel_name source rank url
  channel_id="$(jq -r '.id' <<<"$channel")"
  channel_name="$(jq -r '.name' <<<"$channel")"
  url="$(jq -r '.catalog_url' <<<"$channel")"
  valid_channel_id "$channel_id" || return 1

  if [[ $channel_id == marketplace ]]; then
    source=marketplace
    rank=30
  else
    source=custom
    rank=10
  fi

  local cache="$CHANNEL_CACHE/$channel_id.json"
  local metadata="$CHANNEL_CACHE/$channel_id.meta.json"
  local stage body headers status etag="" modified="" metadata_version=0
  stage="$(mktemp -d "$RUNTIME_ROOT/catalog-$channel_id.XXXXXX")"
  body="$stage/catalog.json"
  headers="$stage/headers"
  if [[ -f $metadata && ! -L $metadata ]]; then
    metadata_version="$(jq -r '.normalizerVersion // 0' "$metadata" \
      2>/dev/null || printf 0)"
    if [[ $metadata_version == "$normalizer_version" ]]; then
      etag="$(jq -r '.etag // ""' "$metadata" 2>/dev/null || true)"
      modified="$(jq -r '.lastModified // ""' "$metadata" \
        2>/dev/null || true)"
    fi
  fi

  status="$(download_catalog "$url" "$body" "$headers" "$etag" "$modified")" || status="000"
  if [[ $status == 304 && $metadata_version == "$normalizer_version"
      && -f $cache && ! -L $cache ]]; then
    rm -rf -- "$stage"
    return
  fi
  if [[ $status != 200 ]]; then
    rm -rf -- "$stage"
    return 1
  fi

  local normalized
  normalized="$(normalize_catalog "$root" "$body" \
    "$channel_name" "$source" "$rank" 2>/dev/null)" || {
    rm -rf -- "$stage"
    return 1
  }
  if ! jq -e '.ok == true and (.records | type == "array")' \
    <<<"$normalized" >/dev/null; then
    rm -rf -- "$stage"
    return 1
  fi
  atomic_write_text "$cache" "$normalized" || {
    rm -rf -- "$stage"
    return 1
  }

  etag="$(header_value ETag "$headers")"
  modified="$(header_value Last-Modified "$headers")"
  safe_header_value "$etag" || etag=""
  safe_header_value "$modified" || modified=""
  jq -cn --argjson normalizerVersion "$normalizer_version" \
    --arg etag "$etag" --arg lastModified "$modified" \
    --arg retrievedAt "$(utc_now)" --arg url "$url" \
    '{normalizerVersion:$normalizerVersion,etag:$etag,
      lastModified:$lastModified,retrievedAt:$retrievedAt,url:$url}' \
    | atomic_write_stream "$metadata"
  rm -rf -- "$stage"
}

github_get() {
  local url="$1"
  local output="$2"
  curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 20 --max-filesize 1048576 \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --header 'User-Agent: plugin-control/0.2.0' \
    --output "$output" -- "$url"
}

github_get_conditional() {
  local url="$1"
  local output="$2"
  local headers="$3"
  local etag="${4:-}"
  local -a request=(
    curl --silent --show-error --location
    --proto '=https' --proto-redir '=https'
    --connect-timeout 5 --max-time 20 --max-filesize 1048576
    --header 'Accept: application/vnd.github+json'
    --header 'X-GitHub-Api-Version: 2022-11-28'
    --header 'User-Agent: plugin-control/0.2.0'
    --output "$output" --dump-header "$headers"
    --write-out '%{http_code}'
  )
  if [[ -n $etag ]] && safe_header_value "$etag"; then
    request+=(--header "If-None-Match: $etag")
  fi
  request+=(-- "$url")
  "${request[@]}"
}

valid_submission_manifest() {
  local manifest="$1"
  jq -e '
    type == "object"
    and .schemaVersion == 1
    and (.id | type == "string" and length <= 128
      and test("^[A-Za-z0-9][A-Za-z0-9._-]*$") and (contains("..") | not))
    and (.name | type == "string" and length > 0 and length <= 120)
    and (.version | type == "string" and length > 0 and length <= 64)
    and (.author | type == "string" and length > 0 and length <= 120)
    and (.description | type == "string" and length > 0 and length <= 500)
    and (.kinds | type == "array" and length > 0 and all(.[]; type == "string"))
    and (.entryPoints | type == "object" and length > 0
      and all(.[];
        (type == "string")
        and (length > 0)
        and (startswith("/") | not)
        and (contains("..") | not)
        and (test("[[:cntrl:]]") | not)))
  ' "$manifest" >/dev/null 2>&1
}

submission_tree_valid() {
  local manifest="$1"
  local tree="$2"
  local path
  while IFS= read -r path; do
    jq -e --arg path "$path" \
      'any((.tree // [])[]; .path == $path and .type == "blob" and .mode != "120000")' \
      "$tree" >/dev/null || return 1
  done < <(jq -r '.entryPoints[]' "$manifest")
}

submission_installable() {
  local config="$1"
  [[ $(jq -r '.allow_unlisted_installs == true' <<<"$config") == true ]]
}

refresh_submission_channel() {
  local root="$1"
  local channel="$2"
  local config="$3"
  local channel_id channel_name repository
  channel_id="$(jq -r '.id' <<<"$channel")"
  channel_name="$(jq -r '.name' <<<"$channel")"
  repository="$(jq -r '.repository' <<<"$channel")"
  valid_channel_id "$channel_id" || return 1
  [[ $repository =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$ ]] || return 1

  local stage issues candidates records
  local cache metadata headers etag="" status
  stage="$(mktemp -d "$RUNTIME_ROOT/submissions-$channel_id.XXXXXX")"
  issues="$stage/issues.json"
  headers="$stage/headers"
  candidates="$stage/candidates.json"
  records="$stage/records.jsonl"
  cache="$CHANNEL_CACHE/$channel_id.json"
  metadata="$CHANNEL_CACHE/$channel_id.issues.meta.json"
  : >"$records"
  if [[ -f $metadata && ! -L $metadata ]]; then
    etag="$(jq -r '.etag // ""' "$metadata" 2>/dev/null || true)"
  fi
  status="$(github_get_conditional \
    "https://api.github.com/repos/$repository/issues?state=open&per_page=100" \
    "$issues" "$headers" "$etag")" || status="000"
  if [[ $status == 304 && -f $cache && ! -L $cache ]]; then
    rm -rf -- "$stage"
    return
  fi
  if [[ $status != 200 ]]; then
    rm -rf -- "$stage"
    return 1
  fi
  jq -c --argjson required "$(jq -c '.required_labels // []' <<<"$channel")" \
    --argjson excluded "$(jq -c '.excluded_labels // []' <<<"$channel")" \
    -f "$root/lib/issues.jq" "$issues" >"$candidates" || {
    rm -rf -- "$stage"
    return 1
  }

  local candidate repo_url slug repo_json branch encoded_branch commit_json sha
  local manifest tree issue_number issue_url labels warnings installable
  while IFS= read -r candidate; do
    repo_url="$(jq -r '.repository' <<<"$candidate")"
    slug="$(github_slug "$repo_url")" || continue
    repo_json="$stage/repo.json"
    commit_json="$stage/commit.json"
    manifest="$stage/manifest.json"
    tree="$stage/tree.json"
    github_get "https://api.github.com/repos/$slug" "$repo_json" || {
      rm -rf -- "$stage"
      return 1
    }
    branch="$(jq -r '.default_branch // ""' "$repo_json")"
    [[ -n $branch && ${#branch} -le 240 && $branch != *$'\n'* ]] || continue
    encoded_branch="$(jq -rn --arg value "$branch" '$value | @uri')"
    github_get "https://api.github.com/repos/$slug/commits/$encoded_branch" "$commit_json" || {
      rm -rf -- "$stage"
      return 1
    }
    sha="$(jq -r '.sha // ""' "$commit_json")"
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || continue
    github_get "https://raw.githubusercontent.com/$slug/$sha/manifest.json" "$manifest" || {
      rm -rf -- "$stage"
      return 1
    }
    valid_submission_manifest "$manifest" || continue
    github_get "https://api.github.com/repos/$slug/git/trees/$sha?recursive=1" "$tree" || {
      rm -rf -- "$stage"
      return 1
    }
    submission_tree_valid "$manifest" "$tree" || continue

    issue_number="$(jq -r '.issueNumber' <<<"$candidate")"
    issue_url="$(jq -r '.issueUrl' <<<"$candidate")"
    labels="$(jq -c '.labels' <<<"$candidate")"
    warnings="$(jq -c '.warnings' <<<"$candidate")"
    installable=false
    if submission_installable "$config"; then
      installable=true
    fi
    jq -cn \
      --arg id "$(jq -r '.id' "$manifest")" \
      --arg name "$(jq -r '.name' "$manifest")" \
      --arg description "$(jq -r '.description' "$manifest")" \
      --arg author "$(jq -r '.author' "$manifest")" \
      --arg version "$(jq -r '.version' "$manifest")" \
      --arg kind "$(jq -r '.kinds | join(" + ")' "$manifest")" \
      --arg repository "$repo_url" --arg commit "$sha" \
      --arg sourceName "$channel_name" \
      --argjson issueNumber "$issue_number" --arg issueUrl "$issue_url" \
      --argjson labels "$labels" --argjson warnings "$warnings" \
      --argjson installable "$installable" \
      '{id:$id,name:$name,description:$description,author:$author,
        version:$version,kind:$kind,repository:$repository,commit:$commit,
        source:"submission",sourceName:$sourceName,
        sourceRank:20,unlisted:true,installable:$installable,builtIn:false,
        issueNumber:$issueNumber,issueUrl:$issueUrl,labels:$labels,
        securityWarnings:$warnings,
        upstreamCheckStatus:"unknown"}' >>"$records"
  done < <(jq -c '.[]' "$candidates")

  local output
  output="$(jq -sc --arg generatedAt "$(utc_now)" \
    '{ok:true,generatedAt:$generatedAt,records:.}' "$records")"
  atomic_write_text "$cache" "$output"
  etag="$(header_value ETag "$headers")"
  safe_header_value "$etag" || etag=""
  jq -cn --arg etag "$etag" --arg retrievedAt "$(utc_now)" \
    --arg repository "$repository" \
    '{etag:$etag,retrievedAt:$retrievedAt,repository:$repository}' \
    | atomic_write_stream "$metadata"
  rm -rf -- "$stage"
}

refresh_channel() {
  local root="$1"
  local channel="$2"
  local config="$3"
  case "$(jq -r '.type' <<<"$channel")" in
    marketplace-catalog) refresh_catalog_channel "$root" "$channel" ;;
    github-submissions) refresh_submission_channel "$root" "$channel" "$config" ;;
    *) return 1 ;;
  esac
}
