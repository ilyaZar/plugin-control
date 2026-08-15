# Plugin Control completion audit

This audit records evidence for version 0.1.0 of
`io.github.ilyazar.plugin-control` on 15 August 2026.

## Product and repository

- [x] Correct repository shape. The repository root contains one
  `manifest.json`, separate service, overlay, dialog, JavaScript model, Bash
  backend, strict YAML parser, jq normalizers, editor helpers, copied shortcut
  library, fixtures, tests, documentation, MIT license, and `preview.png`.
- [x] Runtime validation. `omarchy plugin validate .` exited 0. The publishing
  preflight reported 0 errors.
- [x] No plugin-tree symlinks. The publishing preflight checked this directly.
  The development installation is a symlink at the plugin root, outside the
  repository tree.
- [x] Local installation. Omarchy lists the plugin as enabled with service and
  overlay kinds. The source is linked at the exact manifest-ID path.

## Loading and performance

- [x] Instant cached opening. The service reads a bundled bootstrap before
  starting its cached snapshot process. Opening invokes no network or Git
  function. The final live service became ready in 535 ms.
- [x] Warm latency. Ten repeated shell toggles measured 38-57 ms command
  round-trip, median 47 ms and worst 57 ms. Final focus-ready measurements
  were 4-13 ms.
- [x] Filtering latency. Final live filtering measured 1-3 ms against 177
  merged records. Five thousand synthetic records averaged 3.1 ms per fuzzy
  query, while 10,000 averaged 10.7 ms.
- [x] Refresh measurement. Ten persistent snapshot reads measured 9-24 ms,
  median 11.5 ms. Seven local installed-state rebuilds measured 413-572 ms,
  median 490 ms. A forced conditional network refresh spent 258 ms in channel
  refresh work and completed end to end in 830 ms.
- [x] Hidden cost. `keepLoaded` is true. The service has no rapid timer; the
  only resident polling is the shared binding helper's ten-second Hyprland
  state check and action-status polling while an action is running.

## Search and sources

- [x] Fuzzy behavior. Node and QML tests cover exact, prefix, word-boundary,
  substring and subsequence ranking, stable ties, case-insensitivity,
  ID/name/author/tag matching, result caps, and browse-only records.
- [x] Command grammar. Tests cover `plug-install:`, `plug-remove:`, case
  differences, and whitespace around the colon.
- [x] Source merging. Tests prove local-over-marketplace and
  built-in-over-marketplace precedence plus repository-collision diagnostics.
- [x] Listed marketplace. The live normalized cache held 172 records: 125
  installable, 36 built-in, and 0 normalization errors. All 136 community IDs
  matched the website catalog exactly and were reachable through exact-ID
  fuzzy search; the remaining 11 community entries stayed browse-only.
- [x] Offline behavior. Malformed, failed, oversized, and unchanged catalog
  responses preserve the last valid cache. A valid empty catalog clears stale
  records, while an unverifiable submission candidate preserves the complete
  previous issue cache and metadata.

## Channels and settings

- [x] YAML editor. Shift+S dispatches `scripts/open-channels.sh`, which creates
  the config safely, reports the parser line, and opens it with the configured
  Omarchy editor.
- [x] Strict YAML. Tests cover schema version, booleans, duplicate IDs, unsafe
  tags, aliases, non-HTTPS URLs, embedded credentials, repository slugs,
  arbitrary command fields and last-good fallback.
- [x] Optional issue channel. It is disabled by default. Parsing requires
  `submission` plus `validated`, rejects `listed`, `needs-fixes`, and pull
  requests, validates the current root manifest at an exact commit, rejects
  symlink entry points, and keeps security-review labels as warnings.
- [x] Separate install gate. Live config had unlisted browsing and unlisted
  installation disabled.
- [x] Commit revalidation. A mocked changed default-branch commit is rejected
  immediately before an unlisted install.
- [x] One guarded install path. Background and terminal execution share the
  same snapshot validation, action lock, durable state, and installed-state
  rebuild. Both use the native default-branch add command.

## Mutations and safety

- [x] Native command boundary. Mock tests observed exactly
  `omarchy plugin add https://github.com/example/weather --enable --yes` and
  `omarchy plugin add https://github.com/example/weather --enable` in the
  interactive terminal, plus `omarchy plugin remove local.test --yes`.
  Built-in actions use native enable, disable, and bar placement commands.
- [x] Confirmation safety. Enter opens a keyboard-cancel-first dialog showing
  operation, ID, repository, source, version, reviewed commit when present,
  trust warning, and the unsandboxed-code warning. The dialog pins a copy of
  the displayed record and its snapshot ID; backend execution requires that
  exact snapshot to remain current.
- [x] Remote command isolation. Fixtures include a hostile remote command
  string; it is never executed or interpolated into a shell.
- [x] Self-removal protection. Both the model and backend exclude or reject the
  active Plugin Control ID.
- [x] Dirty-checkout protection. Removal is blocked before the native remove
  command when Git reports local changes.
- [x] Path containment. IDs reject traversal and removal requires the exact
  lexical plugin-ID path plus matching manifest identity.
- [x] Locking. A simultaneous second action receives a busy response. Snapshot
  builds share a separate lock so refresh and action completion cannot publish
  stale installed state out of order.
- [x] Interactive terminal handoff. The persisted install toggle launches the
  same detached worker through `omarchy-launch-terminal`, streams native
  output and prompts, lets Omarchy choose left, center, or right for bar
  widgets, and releases the action lock before waiting for Enter to close.
- [x] Durable actions. Detached workers write atomic status, bounded sanitized
  output, and a durable result before cleanup. Tests read the result through a
  fresh status call and prove worker staging cleanup after failure.
- [x] Installed-state refresh. A successful mocked action caused another
  native plugin-list query and rebuilt the snapshot.

## UI and local integration

- [x] Shell lifecycle. The overlay exposes `opened`, `open`, `close`, and
  `toggle`, and is summoned through the existing shell endpoint. No competing
  Quickshell process is used in production.
- [x] Keyboard and mouse input. The overlay has a real focused `TextInput`, all
  specified navigation and editing keys, Ctrl+R, hover, click, and selection
  scrolling.
- [x] Ctrl+P toggle. The effective Hyprland binding description is `Plugin
  Control`, key P, modifier mask 4. The focused field also handles Ctrl+P as a
  defensive close path.
- [x] Footer shortcuts. Shift+O opens the marketplace, Shift+G opens its HANCORE
  repository, and Shift+S opens channel settings.
- [x] Visual smoke test. The live panel appeared top-centered below the bar on
  focused monitor DP-3, with immediate cursor focus, five compact left-aligned
  rows, theme tokens, source/status metadata, and a short dropdown animation.
  Repeated toggling produced one overlay and left it closed.
- [x] Preview. `preview.png` is a 722 by 502 crop containing only the palette.
  It was inspected at original resolution for layout and privacy.
- [x] QML loading. The real Quickshell instantiation harness created both
  service and overlay entry points. Qt 6 model tests passed 4 of 4.

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
- [x] Native removal intentionally retains user-owned channel settings and
  cache; the README gives explicit optional cleanup commands.
- [x] No task-owned command wrote under `/usr/share/omarchy`. This is a
  task-scoped statement because the shared tree had unrelated concurrent
  changes.

## Known limitations

- Unauthenticated GitHub API limits apply to the optional issue channel.
- Only the first 100 open submission issues are considered per refresh.
- Normal-update integration is not implemented.
- The two authorized live removal targets were dirty development symlinks, so
  the palette correctly blocked removal. Mutation behavior was tested with
  disposable plugin directories and mocked native commands.
