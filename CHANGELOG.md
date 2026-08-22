# Changelog

Notable changes are recorded here for each published release.

## [0.2.1] - 2026-08-22

- Add safe update checks and one action menu for adding, updating, enabling,
  disabling, and removing plugins.
- Add richer marketplace details, activity totals, and on-demand previews.
- Adopt marketplace catalog schema 2 and keep the last usable catalog when a
  source has a recoverable failure.
- Make YAML settings strict and live, including optional background dimming.
- Make submenu keys, focus, status feedback, and settings navigation reliable.
- Restart Omarchy Shell after successful additions and changed updates.
- Keep development symlinks outside automatic update and source-removal paths.

## [0.1.7] - 2026-08-16

- Split the backend and palette into focused modules.
- Add direct Add, Remove, Enable, and Disable actions for each plugin state.
- Improve catalog refresh feedback while keeping startup cache-only.
- Keep settings and cached data in stable namespaced paths.

## [0.1.6] - 2026-08-15

- Validate and document clean self-removal against a live Omarchy shell.

## [0.1.5] - 2026-08-15

- Simplify settings and repair command, confirmation, and information keys.
- Apply saved tray visibility immediately.
- Add guarded self-removal with a choice to preserve or delete user data.
- Support large plugin catalogs without shell argument-size limits.

## [0.1.4] - 2026-08-15

- Add lifecycle controls for starting, stopping, and removing Plugin Control.
- Refine palette interaction and make helper actions easier to discover.

## [0.1.3] - 2026-08-15

- Improve keyboard control, query handling, selection, and palette feedback.

## [0.1.2] - 2026-08-15

- Refine command typing and completion for faster, more stable interaction.

## [0.1.1] - 2026-08-15

- Add the bar launcher so Plugin Control is available from Omarchy Shell.

## [0.1.0] - 2026-08-15

- Publish the first Plugin Control palette with plugin add and remove flows.

[0.2.1]: https://github.com/ilyaZar/plugin-control/compare/v0.1.7...v0.2.1
[0.1.7]: https://github.com/ilyaZar/plugin-control/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/ilyaZar/plugin-control/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/ilyaZar/plugin-control/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/ilyaZar/plugin-control/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/ilyaZar/plugin-control/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/ilyaZar/plugin-control/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ilyaZar/plugin-control/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ilyaZar/plugin-control/releases/tag/v0.1.0
