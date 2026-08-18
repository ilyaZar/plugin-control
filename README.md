# Plugin Control

Think of Sublime Text's classic Package Control or the VS Code Command Palette,
but for Omarchy Quattro plugins.

Press Ctrl+p (or click the tray icon), type a few letters to fuzzy-search, and
press Enter to add or toggle a plugin.

![Plugin Control command palette](preview.png)

Plugin Control keeps the full [@HANCORE-linux](https://github.com/HANCORE-linux)
[community marketplace](https://omarchyplugins.com/) and local plugin state in a
small cache, then filters it in process on every keypress.
Startup reads only that local cache. Press Ctrl+r when you want to refresh it
from the configured catalog sources.

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

Bare Ctrl+p is quick, but it replaces the usual application shortcut while the
binding is active. Change the first string if that disrupts your setup.

## Use

Start typing to search plugin names, IDs, descriptions, authors, and tags. Enter
opens the selected plugin's available action; Ctrl+i shows details without
changing anything.

Without a command prefix, Enter adds an available plugin or toggles a
switchable plugin between enabled and disabled. Removal stays behind the
explicit remove command.

Use these commands to narrow the action first:

- `plug-add:` shows plugins available through `omarchy plugin add`
- `plug-remove:` shows removable local plugins
- `plug-enable:` shows disabled switchable plugins
- `plug-disable:` shows enabled switchable plugins

In 0.1.7, `plug-add:` is the preferred spelling. `plug-install:` remains an
accepted alias for it.

Commands are not pinned. Type `add`, `remove`, `enable`, or `disable` to bring
one forward, then press Tab or Enter to complete it. Search restarts after the
colon. Backspace edits a plugin name normally; at an empty completed prefix,
one press removes the trailing space and the next clears the command.

Useful keys:

| Keys                                       | Action                                      |
| ------------------------------------------ | ------------------------------------------- |
| `Ctrl+p` or `Escape`                       | Close the palette from the plugin list      |
| `Up`, `Down`, `Page Up`, `Page Down`       | Move the selection                          |
| `Home` or `End`                            | Jump to the first or last result            |
| `Enter`                                    | Complete a command or confirm an action     |
| `Tab`                                      | Complete the selected command               |
| `Ctrl+Backspace`                           | Remove the previous word                    |
| `Ctrl+u`                                   | Clear the query                             |
| `Ctrl+r`                                   | Refresh the catalog                         |
| `Ctrl+i`                                   | Show details for the selected plugin        |
| `Ctrl+w`                                   | Open the plugin website                     |
| `Ctrl+g`                                   | Open the plugin source repository           |
| `Ctrl+s`                                   | Open settings; `Escape` returns to the list |

## Demo

Click either preview to play the video.

<table>
  <tr>
    <td width="50%" valign="top">
      <a href="https://ilyazar.github.io/plugin-control/demo/video_plugin_control_add_remove_enable_disable.mp4">
        <img
          src="demo/video_plugin_control_add_remove_enable_disable.png"
          alt="Add, remove, enable, and disable plugins"
        >
      </a>
      <p><strong>Add, remove, enable, and disable</strong></p>
      <p>
        Shows how quickly plugins can be added, removed, enabled, and disabled,
        using the
        <a href="https://github.com/ilyaZar/btop-quattro-plugin">btop plugin</a>
        as an example.
      </p>
    </td>
    <td width="50%" valign="top">
      <a href="https://ilyazar.github.io/plugin-control/demo/video_plugin_control_settings.mp4">
        <img
          src="demo/video_plugin_control_settings.png"
          alt="Refresh the catalog and configure Plugin Control"
        >
      </a>
      <p><strong>Refresh and settings</strong></p>
      <p>
        Shows how to refresh the cached plugin catalog and use Plugin Control
        settings, including enabling or disabling the tray icon and performing
        a clean uninstall and reinstall of the plugin.
      </p>
    </td>
  </tr>
</table>

## Start and stop

These commands enable or disable Plugin Control itself. The tray options only
control whether its icon appears after the plugin starts:

```bash
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control start
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control start --tray-hidden
~/.config/omarchy/plugins/io.github.ilyazar.plugin-control/bin/plugin-control stop
```

The helper belongs to the installed plugin checkout and is not added to
`PATH`. Run it with the full path above, or from the checkout root as
`bin/plugin-control`.

`start` uses the configured tray default. `--tray-hidden` and `--tray-visible`
override it. `stop` disables the whole plugin, not only its tray icon.

## Settings

Ctrl+s opens Plugin settings, Keybindings, clean removal, and Cancel / Back.
Use `j`/`k`, arrows, mouse, or Enter; Escape returns to the plugin list.

```text
~/.config/omarchy/ilyazar.plugin-control/channels.yaml
~/.config/hypr/bindings.lua
```

```yaml
settings:
  tray-icon-hidden: false
```

Plugin Control never rewrites the user-owned Ctrl+p binding. Its other shortcuts
work only while the palette is focused. Saving a valid tray setting updates the
live bar; a CLI flag overrides it until the YAML is saved again.

Settings use strict schema 2. A rejected field produces a short notification
with its value and admissible type or range. The plugin keeps the last valid
settings, or uses shipped defaults when a recoverable first-run typo has no
last-valid file. It never rewrites the invalid YAML. Version 1 is not migrated.

## Dependencies

- Omarchy Quattro and its shell
- Bash, curl, Git, and jq
- Ruby with Psych
- util-linux (`flock` and `setsid`)
- GNU coreutils (`timeout`)
- `omarchy-launch-terminal` for terminal adds

Plugin Control installs no packages and requests no elevated privileges.

## Remove

Select Plugin Control under `plug-remove:` for native removal, or open Settings
and select Cleanly remove Plugin Control and user data. The confirmation offers
three choices:

- Yes (preserve user data) uses native removal
- Yes (delete user data) removes namespaced state and the recognized Plugin
  Control keybinding before native removal
- No / abort makes no changes

The native command is:

```bash
omarchy plugin remove io.github.ilyazar.plugin-control
```

Native removal keeps:

- settings: `~/.config/omarchy/ilyazar.plugin-control/`
- cache: `~/.cache/omarchy/ilyazar.plugin-control/`
- action history: `~/.local/state/omarchy/ilyazar.plugin-control/`

Existing `omarchy/plugin-control` data is moved to the author-namespaced path
on first use when the destination does not already exist. Clean removal deletes
both the current and legacy paths.

## Development

```bash
tests/all.sh
shellcheck bin/plugin-control scripts/*.sh tests/*.sh
omarchy plugin validate .
```

## License

MIT. See [LICENSE](LICENSE).
