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

Start typing to search plugin names, IDs, descriptions, authors, and tags.
Enter opens the selected plugin's available action; Ctrl+Shift+I shows details
without changing anything.

Use either command to narrow the action first:

- `plug-install:` shows available installable plugins
- `plug-remove:` shows removable local plugins

Commands are not pinned. Type `install`, `remove`, `plug-in`, or `plg-in` to
bring one forward, then press Tab or Enter to complete it. Search restarts
after the colon. Backspace edits a plugin name normally; at an empty completed
prefix, one press removes the trailing space and the next clears the command.

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

## Install behavior

Installs run in the background by default and report their result in the
palette and a notification. The confirmation's `Run in Omarchy terminal`
switch streams native prompts instead. Both paths use the confirmed catalog
snapshot.

## Start and stop

```bash
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control start
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control start --tray-hidden
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control stop
```

`start` uses the configured tray default. `--tray-hidden` and
`--tray-visible` override it; `stop` disables the plugin. Omarchy does not add
plugin `bin` directories to `PATH`, so use the full path unless you add an
alias.

## Safety

Omarchy plugins run unsandboxed; marketplace validation is not a security
review. Plugin Control ignores remote command strings, validates repository
roots, uses separate process arguments, and serializes confirmed actions.

It refuses to remove itself, an unexpected checkout, or a checkout with local
changes.

## Settings

Ctrl+Shift+S opens Plugin settings, Keybindings, and Cancel. Use `j`/`k`,
arrows, mouse, or Enter; Escape returns to the plugin list.

```text
~/.config/omarchy/plugin-control/channels.yaml
~/.config/hypr/bindings.lua
```

```yaml
settings:
  tray-icon-hidden: false
```

Plugin Control never rewrites the user-owned Ctrl+P binding. Its other
shortcuts work only while the palette is focused. Tray visibility changes on
the next `start` unless a CLI flag overrides it.

Settings use strict schema 2. Invalid edits keep the last valid schema-2 file;
version 1 is not migrated.

## Dependencies

- Omarchy Quattro and its shell
- Bash, curl, Git, and jq
- Ruby with Psych
- util-linux (`flock` and `setsid`)
- GNU coreutils (`timeout`)
- `omarchy-launch-terminal` for terminal installs

Plugin Control installs no packages and requests no elevated privileges.

## Remove

```bash
omarchy plugin remove io.github.ilyazar.plugin-control
```

Remove the optional Ctrl+P binding separately. Native removal keeps:

- settings: `~/.config/omarchy/plugin-control/`
- cache: `~/.cache/omarchy/plugin-control/`
- action history: `~/.local/state/omarchy/plugin-control/`

## Development

```bash
tests/all.sh
shellcheck bin/plugin-control scripts/*.sh tests/*.sh
omarchy plugin validate .
```

## License

MIT. See [LICENSE](LICENSE).
