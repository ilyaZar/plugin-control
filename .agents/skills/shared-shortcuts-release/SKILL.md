---
name: shared-shortcuts-release
description: >
  Synchronize and validate the shared shortcut helpers vendored into the btop,
  keyboard-layout, and plugin-control Omarchy plugins. Use when changing
  shortcut formatting, Hyprland binding tracking, XKB option translation, or
  before validating, committing, or releasing any consumer plugin.
---

# Shared Shortcuts Release

Treat `../oma-plug-dev-shared-shortcuts/shortcuts/` as the source of truth when
working from a consumer plugin root. Never edit `lib/shortcuts/` directly.

After changing a canonical helper or this skill, run:

```bash
../oma-plug-dev-shared-shortcuts/shortcuts/sync.sh --sync
../oma-plug-dev-shared-shortcuts/shortcuts/sync.sh --check
```

Review each consumer diff, then test the shared formatter:

```bash
QT_QPA_PLATFORM=offscreen \
  qml ../oma-plug-dev-shared-shortcuts/shortcuts/tests/verify.qml
```

Validate each affected plugin from its repository root:

```bash
omarchy plugin validate .
```

Do not commit or release stale vendored copies.
