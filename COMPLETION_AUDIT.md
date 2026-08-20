# Plugin Control completion audit

This audit records release-readiness evidence for
`io.github.ilyazar.plugin-control`.

## Product and repository

- [x] Correct repository shape. The repository root contains one
  `manifest.json`, separate service, overlay, bar launcher, dialog, JavaScript
  model and view model, focused palette components, modular Bash backend,
  strict YAML parser, jq normalizers, editor helpers, copied shortcut library,
  fixtures, tests, domain glossary, manual UI checklist, documentation, MIT
  license, and `preview.png`.
- [x] Runtime validation. `omarchy plugin validate .` exited 0. The publishing
  preflight reported 0 errors.
- [x] No plugin-tree symlinks. The publishing preflight checked this directly.
  The local installation is a normal Git checkout at the plugin root, outside
  the repository tree.
- [x] Local installation. Omarchy lists the plugin as enabled with service,
  overlay, and bar-widget kinds. The feature branch is installed at the exact
  manifest-ID path for owner testing.
- [x] One-way 0.2.0 contract. The `plug-install:` alias, unnamespaced user-data
  migration, old-root deletion, supporting tests, and stale documentation were
  removed. `plug-add:` and the author-namespaced paths are the only supported
  routes.
- [x] Refactor audit. The update-count reducer now has one implementation. A
  second duplication and stale-code pass found no further reduction that would
  simplify the update state machine or QML presentation.

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
  `plug-enable:`, `plug-disable:`, `plug-update:`, case differences, whitespace
  around the colon, fuzzy command-only completion, unpinned empty results,
  operation-intent promotion, exact Tab/Enter completion data, and the two-step
  Backspace transition.
- [x] Source merging. Tests prove local-over-marketplace and
  built-in-over-marketplace precedence plus repository-collision diagnostics.
- [x] Listed marketplace. The live marketplace catalog held 694 records on
  2026-08-20. Strict normalization accepts current stars, verification state,
  and tags without weakening URL, ID, size, or record-count bounds.
- [x] Marketplace metrics. One aggregate read-only stats request per explicit
  Ctrl+R supplies views, command copies, and anonymous hearts. Strict schema
  validation, atomic replacement, and ID joins preserve the last valid cache
  on failure and never invent zero values. No engagement POST is present.
- [x] Marketplace detail metadata. Catalog normalization retains GitHub stars,
  verification state, and the listing/version timestamps used by the website's
  twelve-hour New and Updated badges. A normalizer version invalidates stale
  conditional-request metadata once, so an unchanged upstream catalog still
  gains newly supported fields after upgrade.
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
  slugs, arbitrary command fields and schema-2 last-good fallback. Rejected
  values report their field, actual value, and admissible type or range; a
  recoverable first-run typo uses shipped defaults without rewriting YAML.
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
  interactive terminal, `omarchy plugin remove local.test --yes`, and
  `omarchy plugin update test.available --yes`. Switchable built-in and
  third-party plugins use native enable and disable. Inactive full bars may use
  native enable, while active full bars cannot be disabled.
- [x] Read-only update classification. Added plugins are classified as current,
  available, manual, dirty, local-ahead, diverged, unsupported-layout, or
  failed. Checks fetch `origin HEAD`, compare commits, and never merge, reset,
  pull, checkout, or invoke the native updater.
- [x] Update execution. Update is invoked only after a fresh per-plugin
  classification proves a clean fast-forward. Current plugins report the exact
  already-current result without entering the updating state; unsafe states
  expose a dimmed explanation and never reach the native updater.
- [x] Confirmation safety. Every selected plugin opens the same
  keyboard-cancel-first action dialog with only currently meaningful actions.
  Ctrl+I reuses it with Close as a non-mutating information view. The action
  path pins a copy of the displayed record and its snapshot ID; backend
  execution requires that exact snapshot to remain current.
- [x] Remote command isolation. Fixtures include a hostile remote command
  string; it is never executed or interpolated into a shell.
- [x] Guarded self-removal. The settings menu opens a snapshot-pinned,
  abort-first warning with separate preserve-data and delete-data actions. The
  staged worker survives checkout deletion. Native removal preserves user
  state; clean removal deletes namespaced state plus the recognized Plugin
  Control binding before invoking the native command.
- [x] Dirty-checkout protection. Removal is blocked before the native remove
  command when Git reports local changes, including `.git` file layouts used
  by worktrees and submodules.
- [x] Path containment. IDs reject traversal and removal requires the exact
  lexical plugin-ID path plus matching manifest identity.
- [x] Locking. A simultaneous second action receives a busy response. Update
  checks serialize against actions globally and per plugin. Snapshot builds
  share a separate lock so refresh and action completion cannot publish stale
  added-plugin state out of order.
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
  Ctrl+U, Ctrl+R, hover, click, and selection scrolling.
- [x] Shared action model. Built-ins receive Cancel plus Enable or Disable;
  added user plugins receive Cancel, Update, Enable or Disable, and Remove;
  available plugins receive Cancel and Add. Normal search and all explicit
  command modes open this same state-derived menu.
- [x] Dimmed action help. Unsafe Update remains focusable. A one-second
  keyboard or pointer rest reveals its reason, leaving the action hides it
  immediately, and Enter or Space reveals it without mutation.
- [x] Compact result metadata. Repository links use a smaller third line while
  rows remain 60 logical pixels. The redundant mode-explanation row is gone.
- [x] Ctrl+P toggle. The effective Hyprland binding description is `Plugin
  Control`, key P, modifier mask 4. The focused field also handles Ctrl+P as a
  defensive close path.
- [x] Footer shortcuts. A top rule separates six equal-width shortcut cells;
  their bracketed keys use the active theme's yellow. Ctrl+U checks updates,
  Ctrl+I opens plugin details, Ctrl+W and Ctrl+G open the selected destination,
  Ctrl+R refreshes catalog and metrics, and Ctrl+S opens settings. The font
  shrinks by only one pixel at compact widths.
- [x] Parallel status row. Update/action status is left-aligned and catalog
  status is right-aligned. Running work is yellow, success remains green for
  ten seconds, and exact settled local timestamps are grey. The catalog label
  omits the former Cached, hyphen, and at text.
- [x] Visual smoke test. The live panel appeared top-centered below the bar on
  focused monitor DP-3. The six footer shortcuts fit, Ctrl+U entered
  `plug-update:`, and the left update status changed from yellow checking to a
  red partial result while the catalog timestamp remained right-aligned. The
  shared action dialog showed Cancel, dimmed Update, Disable, and Remove;
  resting on Update revealed its precise local-ahead explanation. Ctrl+I
  displayed cached views, copies, hearts, tags, and verification state. The
  The redesigned Ctrl+I view then showed larger grouped metadata; yellow star,
  orange view/copy, and red-orange heart icons; green New/Verified badges; and
  yellow Updated plus green Verified badges. Zero and nonzero stars both
  rendered honestly. The overlay was closed after the final capture.
- [x] Preview. `preview.png` is an exact 720 by 540 crop of the live 0.2.0
  marketplace detail dialog. It contains no desktop background, was inspected
  at original resolution, and is 64 KB.
- [x] QML loading. The real Quickshell instantiation harness created the
  service, overlay, and bar-widget entry points with isolated XDG paths. It
  also proved a late-injected manifest starts the service and arms the watcher
  after creating a fresh configuration directory. Qt 6 model tests passed 4
  of 4.

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
tests/updates.test.sh
tests/helpers.test.sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input tests/tst_models.qml -import .
tests/qml.test.sh
omarchy plugin validate .
/home/iz/.codex/skills/omarchy-plugin-publishing/scripts/preflight.sh .
```

ShellCheck 0.11.0 reported no findings. The publishing preflight and official
Omarchy validator reported 0 errors. Preflight warnings only request preview
ownership confirmation and note that the local feature branch has no upstream.

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
- Update checks compare each ordinary Git checkout with `origin HEAD`; the
  native Omarchy updater remains the sole owner of the actual fast-forward and
  plugin rescan.
- Full visual and destructive-state coverage remains an owner-run release gate
  in `MANUAL_UI_CHECKLIST.md` before merge or publication.
