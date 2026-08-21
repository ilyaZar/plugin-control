# Plugin Control 0.2.0 manual UI checklist

Run these checks from `feat-plugin-update-ux` before merging or publishing.
Use at least one light theme and one dark theme. Keep a terminal open for
`omarchy plugin list --json` and Git-state confirmation.

## Setup

- [ ] Confirm `manifest.json` reports version 0.2.0 and Plugin Control is
  enabled from this checkout.
- [ ] Open and close the palette repeatedly with Ctrl+p and the bar icon;
  confirm focus always starts in search and only one overlay appears.
- [ ] Confirm the empty search field uses this hint:
  `Search plugins (or type "plug-..." for direct plugin commands).`
- [ ] Confirm `background_dim: false` leaves the workspace undimmed behind the
  palette and dialogs; set it to `true`, save, and confirm dimming appears.
- [ ] Confirm opening the palette performs no network request or update check.
- [ ] Record one disposable Git-managed user plugin and one manually copied
  plugin for the action tests below.

## Shared action menu

- [ ] Select an enabled built-in plugin and confirm the menu is exactly Cancel
  and Disable.
- [ ] Select a disabled built-in plugin and confirm the menu is exactly Cancel
  and Enable.
- [ ] Disable and re-enable a built-in bar widget. Confirm Omarchy removes and
  restores its bar placement even though the UI consistently says Disable and
  Enable.
- [ ] Select the active full bar and confirm only Cancel is available.
- [ ] Select an inactive full bar and confirm Cancel and Enable are available.
- [ ] Select an available user plugin and confirm only Cancel and Add appear.
- [ ] Add that plugin and confirm the menu becomes Cancel, Update,
  Enable/Disable, and Remove after the shell restarts and the snapshot
  refreshes.
- [ ] Disable and re-enable the added plugin. Confirm the action label and
  result row update without reopening Plugin Control.
- [ ] Remove the disposable plugin. Confirm it disappears from added-only
  command results and becomes available to Add when it is catalog-listed.
- [ ] Confirm Cancel is initially selected in every mutating action menu.
- [ ] Confirm Left, Right, Tab, Shift+Tab, Enter, and Space operate the action
  row. Confirm Escape or q returns to the plugin list and hovering keeps the
  normal arrow pointer.
- [ ] Repeat plugin selection through ordinary search and every applicable
  explicit command. Confirm the selected plugin gets the same full menu.
- [ ] Select Plugin Control itself for removal, then cancel the special
  preserve/delete-data dialog without changing the installation.

## Explicit commands and update search

- [ ] Type and complete `plug-add:`, `plug-remove:`, `plug-enable:`,
  `plug-disable:`, and `plug-update:` with both Tab and Enter.
- [ ] Confirm fuzzy command discovery still finds all five commands and that
  `plug-add:` is the only add command.
- [ ] Press Ctrl+u and confirm the query becomes `plug-update: ` and a check
  starts only then.
- [ ] Type `plug-update:` manually, press Tab or Enter, and confirm one trailing
  space is added and the check starts.
- [ ] At the empty completed update prefix, press Backspace twice. Confirm the
  first press removes the space and the second clears the prefix.
- [ ] Type after `plug-update: ` and confirm fuzzy search is limited to checked,
  safely updateable added plugins.
- [ ] Confirm a successful check with no candidates shows
  `All plugins are up to date!`.
- [ ] Confirm Escape or q closes a plugin action menu and leaves the palette
  available for continued searching.

## Update states and execution

- [ ] Make a disposable plugin's remote one commit ahead, run Ctrl+u, and
  confirm it appears in the results.
- [ ] Open that result and confirm the full added-plugin action menu appears,
  not an Update-only dialog.
- [ ] Choose Update and confirm `Updating plugins...` appears in yellow only
  after confirmation, then `Plugin <name> updated!` appears in green.
- [ ] Confirm the local plugin commit advanced through
  `omarchy plugin update <id> --yes`, the shell restarted, and the plugin left
  update results.
- [ ] Choose Update on a current Git plugin without first running Ctrl+u.
  Confirm it reports `Plugin already up-to-date!` and never shows
  `Updating plugins...`.
- [ ] Confirm enable or disable leaves an updateable plugin in update results,
  while Remove removes it from those results.
- [ ] Disconnect networking during Ctrl+u. Confirm the last fully successful
  update timestamp remains and any successfully classified update candidates
  remain usable.
- [ ] Restore networking, press Ctrl+u again, and confirm the check recovers.

## Dimmed Update explanations

- [ ] Select a manually copied plugin and confirm Update is dimmed.
- [ ] Rest keyboard selection or the pointer on dimmed Update for less than one
  second, then leave. Confirm no explanation flashes.
- [ ] Rest on dimmed Update for one second. Confirm the explanation appears and
  reads `Manually copied/installed plugin. No Git repository to update.`
- [ ] Move to the next action and confirm the explanation disappears
  immediately; return for one second and confirm it reappears.
- [ ] Press Enter or Space on dimmed Update and confirm the explanation appears
  immediately without invoking an update.
- [ ] Repeat the dimmed behavior with a dirty Git checkout and confirm local
  files remain unchanged.
- [ ] Repeat with local-ahead and diverged disposable histories. Confirm no
  merge, reset, pull, checkout, or native update occurs.
- [ ] Repeat with a Git worktree or submodule-style `.git` file. Confirm Update
  is dimmed with the native-updater-layout explanation and dirty removal stays
  blocked.
- [ ] Symlink a dirty external development checkout into the plugin root.
  Confirm Update is dimmed with the development-link explanation, Remove
  unlinks it, and the external checkout remains unchanged.

## Information and marketplace metrics

- [ ] Press Ctrl+i on a listed user plugin. Confirm Close is the only action and
  no mutation can be triggered.
- [ ] Confirm the information view shows the complete description with no
  result-row ellipsis. Use a long description and scroll the content while the
  Close action remains visible.
- [ ] Confirm a marketplace plugin with preview metadata shows its card image
  below the description. Confirm a plugin without a preview leaves no empty
  image panel.
- [ ] Click the preview and confirm the larger marketplace detail image fills
  the overlay without distortion. Confirm clicking it or pressing Enter or
  Space returns to the information view. Confirm Escape or q returns directly
  to the main plugin list.
- [ ] Reopen Ctrl+i and confirm Enter, Space, Escape, and q each returns to the
  main plugin list.
- [ ] Confirm Ctrl+i never shows Add, Remove, Update, Enable, Disable, or the
  install-in-terminal switch, including for an installable marketplace plugin.
- [ ] Confirm the dialog uses a larger plugin title, clear metadata groups,
  bordered metric chips, and enough whitespace to avoid a wall of text.
- [ ] Confirm the information card ends shortly below its final metadata or tag
  row, with only normal spacing before Close and no large empty middle area.
- [ ] Confirm author, version, source, repository, reviewed commit when known,
  tags, stars, verification state, views, command copies, and anonymous hearts
  match the cached upstream data.
- [ ] Confirm GitHub stars use a yellow star; views and command copies use
  orange icons; anonymous hearts use the marketplace red-orange heart.
- [ ] Confirm a zero-star repository displays a yellow `0 stars` chip rather
  than hiding the GitHub metric.
- [ ] Confirm Verified and New use marketplace green, while Unverified uses
  marketplace red-orange and Updated uses marketplace yellow.
- [ ] Confirm Updated wins over New when both timestamps are recent. Confirm
  both badges disappear after the marketplace's twelve-hour window and are
  absent for built-ins.
- [ ] Hover the verification label. Confirm the explanation says verification
  is associated with marketplace checks and is not a security audit.
- [ ] Confirm an unverified listing is not described as malicious or unsafe.
- [ ] Press Ctrl+i on a built-in plugin and confirm user-listing verification
  and star fields are absent.
- [ ] Press Ctrl+i on an unlisted user plugin and confirm
  `Not listed on Omarchy Plugins` appears.
- [ ] Simulate unavailable metrics with a valid catalog. Confirm values remain
  unknown and are not displayed as zero.
- [ ] Press Ctrl+r repeatedly while the metrics endpoint fails. Confirm each
  press retries silently and the last valid metrics stay visible.

## Footer, status, and visual quality

- [ ] Confirm footer order is Ctrl+u, Ctrl+i, Ctrl+w, Ctrl+g, Ctrl+r, Ctrl+s and
  every shortcut works.
- [ ] Confirm footer text fits at the narrowest supported palette width. Verify
  it shrinks only slightly and remains comfortably readable.
- [ ] During Ctrl+u, confirm `Checking for updates...` is yellow on the left and
  catalog status remains right-aligned on the same row.
- [ ] After a successful check, confirm
  `Last update: HH:MM:SS (YYYY-MM-DD)` is green for ten seconds, then grey.
- [ ] With one uncheckable Git plugin, confirm the check still succeeds and a
  yellow warning icon appears. Hover it and confirm the plugin name, ID, and
  complete reason are shown. Confirm the icon is absent after a clean check.
- [ ] During Ctrl+r, confirm `Refreshing catalog...` is yellow on the right.
- [ ] After refresh, confirm
  `Catalog refreshed: HH:MM:SS (YYYY-MM-DD)` is green for ten seconds, then
  grey.
- [ ] Make one catalog source unavailable while retaining its valid cache.
  Confirm Ctrl+r returns to the previous grey catalog timestamp with a yellow
  warning icon instead of red failure text. Hover the icon and confirm it names
  the source, says that the last valid cache is in use, and shows its timestamp.
- [ ] Repeat without a downloaded marketplace cache. Confirm the settled status
  says `Catalog cache ready`, the yellow warning explains that the bundled
  catalog is in use, and Plugin Control remains searchable.
- [ ] Confirm a later complete refresh removes the catalog warning icon and
  performs the normal ten-second green success transition.
- [ ] Confirm update and catalog statuses can coexist without overlap at normal
  width and remain understandable at minimum width.
- [ ] Inspect the action dialog, dimmed help, metrics, status row, and footer in
  light and dark themes and at 100%, 125%, and 150% scale.
- [ ] Confirm long plugin names, repositories, tags, notices, and translated
  date widths do not clip controls or push the dialog off screen.
- [ ] Confirm all focus indicators, selected/dimmed contrast, mouse hit targets,
  and warning/success colors remain clear.
- [ ] In plugin actions and Ctrl+i details, confirm the pointer stays an arrow
  everywhere except over the painted preview image, where it becomes a hand.

## Final preservation check

- [ ] Confirm every disposable plugin, bar placement, Git branch, local change,
  theme, scale, network state, and Plugin Control setting is restored.
- [ ] Run the automated release commands from `COMPLETION_AUDIT.md` again after
  the visual pass and confirm the branch remains clean.
