# Plugin Control

Think of Sublime Text's classic Package Control or the VS Code Command Palette,
but for Omarchy Quattro plugins.

Press Ctrl+P (or click the tray icon), type a few letters to invoke fuzzy find,
and install or remove a plugin hitting enter.

![Plugin Control command palette](preview.png)

Plugin Control keeps the full [@HANCORE-linux](https://github.com/HANCORE-linux)
[community marketplace](https://omarchyplugins.com/) and local plugin state in a
small cache, then filters it in process on every keypress.

## Install

```bash
omarchy plugin add https://github.com/ilyaZar/plugin-control.git --enable
```

Plugin manifests cannot add global bindings. For a keyboard-only path, add this
optional binding to your repo-managed or user-owned `bindings.lua`:

```lua
o.bind(
  "CTRL + P",
  "Plugin Control",
  "omarchy-shell shell toggle io.github.ilyazar.plugin-control '{}'"
)
```

Bare Ctrl+P is quick, but it replaces the usual application shortcut while the
binding is active. Change the first string if that disrupts your setup.

## Use

- open the palette and start typing to browse
  - matching is case-insensitive and fuzzy across names, IDs, descriptions,
    authors, tags, sources, plugin kinds, etc.
- press enter on a plugin, to get install/remove and similar options
- use other keybindings (yellow; footer) to get plugin metadata and settings
- fast routing to github plugin page of the corresponding author or the
  marketplace

Use the following to make changes explicit:

- `plug-install:` shows available installable plugins
- `plug-remove:` shows removable local plugins

The commands stay out of the empty result list but you can start typing
`install` or `remove`, or use a command-shaped fuzzy query such as `plug-in` or
`plg-in`, and the matching command moves above ordinary plugin results. Press
Tab or Enter to complete it through the colon. Plugin search restarts
immediately in that mode. After completion, Backspace removes the trailing space
first; a second press clears the whole `plug-install:` or `plug-remove:`
command. When a plugin name follows the prefix, Backspace edits that name
normally before this two-step reset. A malformed colon command is inert until
edited.

For example:

```text
plug-install: btp
plug-remove: keylay
```

Name and ID matches rank ahead of metadata-only matches. Results are stable by
name and then ID.

Enter opens a cancel-first confirmation only when the selected plugin has an
available install, remove, enable, disable, or add-to-bar action. Use
Ctrl+Shift+I for the same plugin's non-mutating information view.

Useful keys:

| Keys                                 | Action                                       |
| ------------------------------------ | -------------------------------------------- |
| `Ctrl+P`, `Escape`                   | Close palette from plugin list               |
| `Up`, `Down`, `Page Up`, `Page Down` | Move selection                               |
| `Home`, `End`                        | Jump to first or last result                 |
| `Enter`                              | Complete command or confirm available action |
| `Tab`                                | Complete selected command                    |
| `Ctrl+Backspace`                     | Remove previous word                         |
| `Ctrl+U`                             | Clear query                                  |
| `Ctrl+R`                             | Refresh catalog                              |
| `Ctrl+Shift+I`                       | Open selected plugin information             |
| `Ctrl+Shift+O`                       | Open selected plugin or marketplace page     |
| `Ctrl+Shift+G`                       | Open selected or marketplace repository      |
| `Ctrl+Shift+S`                       | Open settings; Escape returns to list        |

## Install output and bar placement

The install confirmation has a small `Run in Omarchy terminal` switch. Its
choice is remembered in:

```text
~/.config/omarchy/plugin-control/settings.json
```

With the switch off, Plugin Control runs the native installer in the background
and reports its result in the palette and a desktop notification. This is the
fastest path. Bounded, sanitized output is retained for a failed action.

With the switch on, the same guarded action opens in an Omarchy terminal and
runs:

```text
omarchy plugin add <repository> --enable
```

Output is live. Omarchy performs its normal trust confirmation and, for a bar
widget, asks whether it belongs in the left, center, or right section. Center is
Omarchy's name for the middle section. The terminal shows the final result and
waits for Enter before closing.

Both modes use the same confirmed catalog snapshot, action lock, repository
checks, durable result, and installed-state rebuild. The terminal switch is not
offered for unlisted submissions because those require an immediate
reviewed-commit recheck in the background path.

## Start and stop

The included Bash CLI follows Omarchy's GNU-style long-option convention:

```bash
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control start
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control start --tray-hidden
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control stop
```

`start` enables the plugin and keeps the package launcher visible unless the
settings file or an explicit `--tray-hidden` says otherwise. `--tray-visible`
overrides a hidden default. A hidden launcher occupies no bar space, while the
service and any configured keyboard binding remain available. `stop` uses
Omarchy's native plugin disable command.

Plugin checkouts do not add their `bin` directories to `PATH`. If the command is
already linked or aliased locally, its short form is simply
`plugin-control start` or `plugin-control stop`.

## Catalog and speed

Plugin Control combines:

- the live catalog at `https://omarchyplugins.com/catalog.json`
- Omarchy's built-in plugins and bar widgets
- locally installed third-party plugins
- optional validated submission or custom catalog channels

Every valid catalog record remains searchable, including browse-only entries.
Install mode only includes records with a supported installation path.

A bundled bootstrap appears first, followed by the last validated disk snapshot.
Network channels refresh in the background when their 30-minute TTL expires and
use HTTP validators when available. Offline, malformed, oversized, or failed
responses leave the previous valid cache in place.

The matcher is deliberately small JavaScript rather than an `fzf` subprocess. At
marketplace scale it filters faster than the process startup and IPC needed for
an external picker, while keeping the palette responsive into thousands of
records.

## Safety

Omarchy plugins run unsandboxed inside the long-running shell. Marketplace
validation is not a security review.

Plugin Control never executes command strings from a catalog, issue, or README.
It accepts public HTTPS GitHub repository roots, passes validated values as
separate process arguments, and confirms actions against an immutable snapshot.
Actions are serialized.

Removal is refused for Plugin Control itself, for an unexpected path or manifest
identity, and for a Git checkout with local changes. Commit, stash, or discard
those changes before removing that plugin.

The footer follows the selection. Command rows keep the two global links;
selecting a marketplace plugin changes them to its detail page and GitHub
repository.

## Settings

Ctrl+Shift+S replaces the plugin rows with three choices: Plugin settings,
Keybindings, or Cancel. Typing is disabled in this menu; use `j`/`k`, the arrow
keys, mouse selection, and Enter. Escape or Cancel returns to the still-open
plugin list. Plugin settings opens the YAML file at its current validation
error, if any. Keybindings opens `bindings.lua` at the `Plugin Control` entry:

```text
~/.config/omarchy/plugin-control/channels.yaml
```

```yaml
settings:
  tray-icon-hidden: false
```

The Ctrl+P launcher is user-owned in `~/.config/hypr/bindings.lua`; Plugin
Control never rewrites or removes it. The screen always shows its effective live
Hyprland value. Ctrl+Shift+I/O/G/S and Ctrl+R are fixed controls that only apply
while the palette has focus. Tray visibility is applied the next time
`plugin-control start` runs; an explicit start flag wins for that invocation.

The listed marketplace is enabled by default. The included HANCORE submission
channel is disabled, and unlisted installation has a separate disabled gate.
Configuration schema 2 requires `tray-icon-hidden`. Older schemas fail clearly
and remain untouched; there is no compatibility reader or automatic migration.
The parser also rejects unknown fields, duplicate IDs, credentials in URLs,
non-HTTPS catalogs, arbitrary command fields, aliases, and object tags. An
invalid edit leaves a schema-2 last-good configuration active.

Enabling unlisted browsing does not enable unlisted installation. When both are
explicitly enabled, Plugin Control validates the issue labels, root manifest,
regular entry-point files, and exact default-branch commit. It rechecks that
commit immediately before installation.

## Dependencies

Runtime dependencies are Omarchy Quattro and its shell, Bash, curl, Git, jq,
Ruby with Psych, util-linux (`flock` and `setsid`), GNU coreutils, and
`timeout`. Terminal installs use Omarchy's `omarchy-launch-terminal`. The plugin
does not install packages or request elevated privileges.

## State

- settings: `~/.config/omarchy/plugin-control/`
- catalog cache: `~/.cache/omarchy/plugin-control/channels/`
- snapshots and action results: `~/.local/state/omarchy/plugin-control/`
- runtime locks: `${XDG_RUNTIME_DIR}/omarchy-plugin-control/`

GitHub tokens are neither required nor stored.

## Troubleshooting

Rescan and enable the plugin if it is installed but not discovered:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.ilyazar.plugin-control
```

Force a catalog refresh or inspect a warm-cache benchmark:

```bash
bin/plugin-control refresh "$PWD" --force
bin/plugin-control benchmark "$PWD"
```

## Remove

```bash
omarchy plugin remove io.github.ilyazar.plugin-control
```

Remove the optional Ctrl+P binding separately. Native removal retains user-owned
settings, cache, and action history. After reviewing the paths above, remove
them explicitly if they are no longer wanted.

## Development

```bash
tests/all.sh
shellcheck bin/plugin-control scripts/*.sh tests/*.sh
omarchy plugin validate .
```

The tests cover fuzzy ranking, catalog failures, strict channel parsing,
snapshot confirmation, native argv boundaries, interactive terminal handoff,
locking, removal guards, durable results, QML models, and real Quickshell
instantiation.

## License

MIT. See [LICENSE](LICENSE).
