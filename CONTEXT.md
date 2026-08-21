# Plugin Control

Plugin Control presents Omarchy plugin state and native plugin operations in a
fast command-palette interface. This glossary keeps product language consistent
across the UI, documentation, and implementation.

## Language

**Built-in plugin**:
An Omarchy-shipped plugin whose lifecycle and current state come from the
native plugin registry.
_Avoid_: First-party item, system plugin

**User plugin**:
A third-party plugin that a user can add to Omarchy.
_Avoid_: Community item, external plugin

**Available plugin**:
A user plugin that is known to Plugin Control but has not been added locally.
_Avoid_: Uninstalled plugin, remote plugin

**Added plugin**:
A user plugin present in the local Omarchy plugin directory.
_Avoid_: Installed plugin, downloaded plugin

**Update available**:
A checked added plugin whose upstream commit is a safe fast-forward from its
unchanged local commit.
_Avoid_: Outdated plugin, upgrade available

**Full bar**:
A complete Omarchy bar plugin that can replace the active bar rather than
occupy one widget position.
_Avoid_: Bar widget, panel
