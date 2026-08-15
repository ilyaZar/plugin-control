def labels:
  [(.labels // [])[] | if type == "object" then .name else . end | tostring];

def repository_url:
  (.body // "")
  | capture("(?im)^### Repository URL[ \\t]*\\r?\\n+[ \\t]*(?<url>https://github\\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}(?:\\.git)?/?)[ \\t]*$").url
  | sub("/$"; "")
  | sub("\\.git$"; "");

[
  .[]
  | . as $issue
  | (labels) as $labels
  | select((has("pull_request") | not))
  | select(all($required[]; . as $label | $labels | index($label)))
  | select(all($excluded[]; . as $label | $labels | index($label) | not))
  | try {
      issueNumber: .number,
      issueUrl: (.html_url // ""),
      title: (.title // ""),
      repository: repository_url,
      labels: $labels,
      warnings: [
        $labels[]
        | select(. == "security-review-required" or . == "security-needs-fixes")
      ]
    } catch empty
]
