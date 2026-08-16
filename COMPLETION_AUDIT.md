# Plugin Control completion audit

This audit records release-readiness evidence for
`io.github.ilyazar.plugin-control`.

## Product and repository

- [x] Correct repository shape. The repository root contains one
  `manifest.json`, separate service, overlay, bar launcher, dialog, JavaScript
  model and view model, focused palette components, modular Bash backend,
  strict YAML parser, jq normalizers, editor helpers, copied shortcut library,
  fixtures, tests, documentation, MIT license, and `preview.png`.
- [x] Runtime validation. `omarchy plugin validate .` exited 0. The publishing
  preflight reported 0 errors.
- [x] No plugin-tree symlinks. The publishing preflight checked this directly.
  The development installation is a symlink at the plugin root, outside the
  repository tree.
- [x] Local installation. Omarchy lists the plugin as enabled with service,
  overlay, and bar-widget kinds. The source is linked at the exact manifest-ID
  path.

## Loading and performance

- [x] Instant cached opening. The service reads a bundled bootstrap before
  starting its cached snapshot process. Opening invokes no network or Git
  function, and enabling the plugin does not refresh remote sources. The final
  live service became ready in 510 ms.
- [x] Warm latency. Ten repeated shell toggles measured 38-57 ms command
  round-trip, median 47 ms and worst 57 ms. Final focus-ready measurements
  were 4-13 ms.
- [x] Filtering latency. Final live filtering measured 1-3 ms; the current
  merged catalog held 207 records. Five thousand synthetic records averaged
  3.1 ms per fuzzy query, while 10,000 averaged 10.7 ms.
- [x] Refresh measurement. Ten persistent snapshot reads measured 9-24 ms,
  median 11.5 ms. Seven local installed-state rebuilds measured 413-572 ms,
  median 490 ms. A forced conditional network refresh spent 258 ms in channel
  refresh work and completed end to end in 830 ms. The final public-catalog
  refresh spent 279 ms in channel work.
- [x] Large snapshot assembly. The live 203-record marketplace cache exceeded
  Linux's per-argument limit in the former in-memory jq handoff. Snapshot JSON
  now moves through private runtime files; a 400-record, 300 KB fixture proves
  the same path without large command-line arguments.
- [x] Hidden cost. `keepLoaded` is true. The service has no rapid timer; the
  only resident polling is the shared binding helper's ten-second Hyprland
  state check and action-status polling while an action is running.
- [x] Resident memory. Paired fresh-shell comparisons measured about 10 MiB
  median incremental PSS while enabled. The final first-open run added about
  19 MiB and hiding the palette returned about 11 MiB. These are approximate
  differentials because every plugin shares the Omarchy shell process.

## Search and sources

- [x] Fuzzy behavior. Node and QML tests cover exact, prefix, word-boundary,
  substring and subsequence ranking, stable ties, case-insensitivity,
  ID/name/author/tag matching, result caps, and browse-only records.
- [x] Command grammar. Tests cover `plug-add:`, `plug-remove:`,
  `plug-enable:`, `plug-disable:`, the `plug-install:` alias, case differences,
  whitespace around the colon, fuzzy command-only completion, unpinned empty
  results, operation-intent promotion, exact Tab/Enter completion data, and
  the Backspace transition.
- [x] Source merging. Tests prove local-over-marketplace and
  built-in-over-marketplace precedence plus repository-collision diagnostics.
- [x] Listed marketplace. The live normalized cache held 203 records: 156
  installable, 36 built-in, and 0 normalization errors. All 167 community IDs
  matched the website catalog exactly and were reachable through exact-ID
  fuzzy search; the remaining 11 community entries stayed browse-only.
- [x] Offline behavior. Malformed, failed, oversized, and unchanged catalog
  responses preserve the last valid cache. A valid empty catalog clears stale
  records, while an unverifiable submission candidate preserves the complete
  previous issue cache and metadata.

## Settings and channels

- [x] Settings editor. Ctrl+S opens an inline three-row menu. Typing is
  consumed; `j`/`k`, arrows, mouse, Enter, Escape, and Cancel route through
  `scripts/open-settings.sh` to the validated plugin YAML, the exact Plugin
  Control entry in `bindings.lua`, or back to the open palette.
- [x] Lifecycle CLI. Mocked `start` and `stop` calls observed the exact native
  enable, disable, and bar-setting arguments. The strict settings schema holds
  the tray default; explicit GNU-style tray flags
  take precedence without accepting surplus arguments. Live hidden, stopped,
  and visible starts produced the matching native plugin and bar states.
- [x] Strict YAML. Schema 2 requires the tray setting. Tests cover clear
  rejection without replacement, booleans, unknown fields, duplicate IDs,
  unsafe tags, aliases, non-HTTPS URLs, embedded credentials, repository
  slugs, arbitrary command fields and schema-2 last-good fallback.
- [x] Optional issue channel. It is disabled by default. Parsing requires
  `submission` plus `validated`, rejects `listed`, `needs-fixes`, and pull
  requests, validates the current root manifest at an exact commit, rejects
  symlink entry points, and keeps security-review labels as warnings.
- [x] Separate install gate. Live config had unlisted browsing and unlisted
  installation disabled.
- [x] Commit revalidation. A mocked changed default-branch commit is rejected
  immediately before an unlisted add.
- [x] One guarded add path. Background and terminal execution share the
  same snapshot validation, action lock, durable state, and installed-state
  rebuild. Both use the native default-branch add command.

## Mutations and safety

- [x] Native command boundary. Mock tests observed exactly
  `omarchy plugin add https://github.com/example/weather --enable --yes` and
  `omarchy plugin add https://github.com/example/weather --enable` in the
  interactive terminal, plus `omarchy plugin remove local.test --yes`.
  Switchable built-in and third-party plugins use native enable and disable;
  runtime `canDisable` state guards both actions.
- [x] Confirmation safety. Enter opens a keyboard-cancel-first dialog only for
  an available action. Ctrl+I reuses it as a non-mutating information
  view, and browse-only Enter is inert. The action path pins a copy of the
  displayed record and its snapshot ID; backend execution requires that exact
  snapshot to remain current.
- [x] Remote command isolation. Fixtures include a hostile remote command
  string; it is never executed or interpolated into a shell.
- [x] Guarded self-removal. The settings menu opens a snapshot-pinned,
  abort-first warning with separate preserve-data and delete-data actions. The
  staged worker survives checkout deletion. Native removal preserves user
  state; clean removal deletes namespaced and legacy state plus the recognized
  Plugin Control binding before invoking the native command.
- [x] Dirty-checkout protection. Removal is blocked before the native remove
  command when Git reports local changes.
- [x] Path containment. IDs reject traversal and removal requires the exact
  lexical plugin-ID path plus matching manifest identity.
- [x] Locking. A simultaneous second action receives a busy response. Snapshot
  builds share a separate lock so refresh and action completion cannot publish
  stale installed state out of order.
- [x] Interactive terminal handoff. The persisted terminal toggle launches the
  same detached worker through `omarchy-launch-terminal`, streams native
  output and prompts, lets Omarchy choose left, center, or right for bar
  widgets, and releases the action lock before waiting for Enter to close.
- [x] Durable actions. Detached workers write atomic status, bounded sanitized
  output, and a durable result before cleanup. Tests read the result through a
  fresh status call and prove worker staging cleanup after failure.
- [x] Bounded action notice. A failed action remains visible in the palette and
  red bar icon for ten seconds, then its durable status is acknowledged. A
  persisted unacknowledged result starts the same timer when the service loads.
- [x] Installed-state refresh. A successful mocked action caused another
  native plugin-list query and rebuilt the snapshot.

## UI and local integration

- [x] Bar launcher. The single native package glyph opens the existing overlay
  on left click, defaults to the right section, and exposes only Settings on
  right click. A hidden setting collapses visibility and implicit size while
  leaving the plugin service enabled.
- [x] Shell lifecycle. The overlay exposes `opened`, `open`, `close`, and
  `toggle`, and is summoned through the existing shell endpoint. No competing
  Quickshell process is used in production.
- [x] Keyboard and mouse input. The overlay has a real focused `TextInput`, all
  specified navigation and editing keys, command completion on Tab or Enter,
  Ctrl+R, hover, click, and selection scrolling.
- [x] Compact result metadata. Repository links use a smaller third line while
  rows remain 60 logical pixels. The redundant mode-explanation row is gone.
- [x] Ctrl+P toggle. The effective Hyprland binding description is `Plugin
  Control`, key P, modifier mask 4. The focused field also handles Ctrl+P as a
  defensive close path.
- [x] Footer shortcuts. A top rule separates five equal-width shortcut cells;
  their bracketed keys use the active theme's yellow. Ctrl+I opens plugin
  details, Ctrl+W and Ctrl+G follow the selected plugin or fall back to the
  marketplace, Ctrl+R refreshes, and Ctrl+S opens settings. These fixed
  controls are handled only by the focused palette.
- [x] Refresh status. An explicit refresh is yellow while running, then its
  local completion time is green for ten seconds before settling to grey.
- [x] Visual smoke test. The live panel appeared top-centered below the bar on
  focused monitor VGA-1, with immediate cursor focus, compact left-aligned
  rows, theme tokens, source/status metadata, and a short dropdown animation.
  Capital O remained search input, the failed-action notice expired after ten
  seconds, and repeated toggling produced one overlay and left it closed.
- [x] Preview. `preview.png` is a 722 by 500 crop containing only the palette.
  It was inspected at original resolution for layout and privacy.
- [x] QML loading. The real Quickshell instantiation harness created the
  service, overlay, and bar-widget entry points. Qt 6 model tests passed 4 of
  4.

## Verification commands

These commands passed unless a result is noted:

```bash
bash -n bin/plugin-control scripts/*.sh tests/*.sh
shellcheck bin/plugin-control scripts/*.sh tests/*.sh
node tests/model.test.js
ruby tests/channel_config.test.rb
tests/catalog.test.sh
tests/issues.test.sh
tests/backend.test.sh
tests/helpers.test.sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_models.qml -import .
tests/qml.test.sh
omarchy plugin validate .
omarchy-plugin-publishing preflight .
```

ShellCheck reported no findings. The publishing preflight reported 0 errors.

## Cleanup and shared-state preservation

- [x] Existing user config was preserved. Plugin-owned config, cache, state,
  and runtime paths are separate and documented.
- [x] Native removal intentionally retains user-owned settings and
  cache; the README identifies the retained paths and user-owned binding.
- [x] No task-owned command wrote under `/usr/share/omarchy`. This is a
  task-scoped statement because the shared tree had unrelated concurrent
  changes.

## Known limitations

- Unauthenticated GitHub API limits apply to the optional issue channel.
- Only the first 100 open submission issues are considered per refresh.
- Normal-update integration is not implemented.
