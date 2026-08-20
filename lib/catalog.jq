def safe_string($maximum):
  type == "string"
  and length <= $maximum
  and (test("[[:cntrl:]]") | not);

def valid_id:
  safe_string(128)
  and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")
  and (contains("..") | not);

def valid_repository:
  safe_string(2048)
  and test("^https://github\\.com/[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}(?:\\.git)?/?$");

def optional_string($key; $maximum):
  (has($key) | not) or .[$key] == null or (.[$key] | safe_string($maximum));

def valid_optional_date($key):
  (has($key) | not) or .[$key] == null
  or (.[$key] | safe_string(10)
      and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"));

def valid_optional_timestamp($key):
  (has($key) | not) or .[$key] == null
  or (.[$key] | safe_string(40)
      and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?Z$"));

def valid_optional_repository:
  (.repo == null) or (.repo == "") or (.repo | valid_repository);

def valid_tags:
  (.tags == null)
  or (.tags | type == "array"
      and length <= 30
      and all(.[]; safe_string(80)));

def valid_release:
  (.repositoryRelease == null)
  or (.repositoryRelease | type == "object"
      and optional_string("tag"; 160)
      and optional_string("url"; 2048));

def valid_optional_count($key):
  (has($key) | not) or .[$key] == null
  or (.[$key] | type == "number" and floor == . and . >= 0
      and . <= 1000000000000);

def valid_verification:
  (.verificationStatus == null)
  or (.verificationStatus | type == "string"
      and IN("verified", "unverified"));

def row_valid:
  type == "object"
  and (.id | valid_id)
  and (.name | safe_string(120))
  and optional_string("description"; 500)
  and optional_string("author"; 120)
  and optional_string("version"; 64)
  and optional_string("repo"; 2048)
  and valid_optional_repository
  and optional_string("sourceType"; 40)
  and optional_string("manifestPath"; 240)
  and optional_string("repositoryLayout"; 80)
  and optional_string("category"; 120)
  and optional_string("kind"; 120)
  and optional_string("status"; 120)
  and optional_string("listingValidatedCommit"; 80)
  and optional_string("upstreamObservedCommit"; 80)
  and optional_string("upstreamCheckStatus"; 80)
  and valid_optional_date("addedAt")
  and valid_optional_timestamp("listedAt")
  and valid_optional_timestamp("versionUpdatedAt")
  and ((.sourceType // "") | IN("builtin", "community"))
  and valid_tags
  and valid_release
  and valid_optional_count("stars")
  and valid_verification;

def normalized_repository:
  (.repo // "")
  | sub("/$"; "")
  | sub("\\.git$"; "");

def normalized_record($channel_name; $channel_source; $channel_rank):
  (normalized_repository) as $repository
  | (($channel_source == "marketplace")
      and (.sourceType == "builtin")) as $builtin
  | {
      id,
      name,
      description: (.description // ""),
      author: (.author // ""),
      version: (.version // ""),
      repository: $repository,
      category: (.category // ""),
      tags: (.tags // []),
      stars: (.stars // null),
      verificationStatus: (.verificationStatus // ""),
      addedAt: (.addedAt // ""),
      listedAt: (.listedAt // ""),
      versionUpdatedAt: (.versionUpdatedAt // ""),
      kind: (.kind // ""),
      builtIn: $builtin,
      source: (if $builtin then "builtin" else $channel_source end),
      sourceName: (if $builtin then "Omarchy built-in" else $channel_name end),
      sourceRank: (if $builtin then 40 else $channel_rank end),
      installable: (
        ($builtin | not)
        and .installAvailable == true
        and .sourceType == "community"
        and .repositoryLayout == "root-plugin"
        and .manifestPath == "manifest.json"
        and ($repository | valid_repository)
      ),
      listingValidatedCommit: (.listingValidatedCommit // ""),
      upstreamObservedCommit: (.upstreamObservedCommit // ""),
      upstreamCheckStatus: (.upstreamCheckStatus // "unknown"),
      releaseTag: (.repositoryRelease.tag // "")
    }
  | with_entries(select(.value != null));

if type != "object" then
  {ok: false, error: "catalog root must be an object", records: [], errors: []}
elif (.stateSchemaVersion != null and .stateSchemaVersion != 1) then
  {ok: false, error: "unsupported catalog state schema version", records: [], errors: []}
elif (.plugins | type) != "array" then
  {ok: false, error: "catalog plugins must be an array", records: [], errors: []}
elif (.plugins | length) > 5000 then
  {ok: false, error: "catalog has too many records", records: [], errors: []}
else
  .plugins as $plugins
  | {
      ok: true,
      generatedAt: (.generatedAt // ""),
      records: [
        $plugins
        | to_entries[]
        | select(.value | row_valid)
        | .value
        | normalized_record($channelName; $channelSource; $channelRank)
      ],
      errors: [
        $plugins
        | to_entries[]
        | select((.value | row_valid) | not)
        | {index: .key, error: "unsafe or malformed catalog row rejected"}
      ]
    }
end
