#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT

qmllint_bin="$(command -v qmllint)"
if [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  qmllint_bin=/usr/lib/qt6/bin/qmllint
fi
"$qmllint_bin" -I /usr/share/omarchy/shell \
  "$ROOT/Service.qml" "$ROOT/PluginControl.qml" "$ROOT/ActionDialog.qml" \
  "$ROOT/PluginControlBar.qml" "$ROOT/SelfRemovalDialog.qml" \
  "$ROOT/PaletteResultRow.qml" "$ROOT/PaletteFooter.qml" \
  "$ROOT/lib/shortcuts/HyprlandBinding.qml"
printf 'ok - QML lint\n'

rg -q 'function open\(payloadJson\)' "$ROOT/PluginControl.qml"
rg -q 'function close\(\)' "$ROOT/PluginControl.qml"
rg -q 'function toggle\(\)' "$ROOT/PluginControl.qml"
rg -q 'TextInput \{' "$ROOT/PluginControl.qml"
rg -q 'Qt.Key_P' "$ROOT/PluginControl.qml"
rg -q 'Qt.Key_Escape' "$ROOT/PluginControl.qml"
rg -Fq '{ keyLabel: "[Ctrl+i]", label: "Info" }' \
  "$ROOT/PaletteFooter.qml"
rg -Fq '{ keyLabel: "[Ctrl+w]",' \
  "$ROOT/PaletteFooter.qml"
rg -Fq '{ keyLabel: "[Ctrl+g]", label: "GitHub source" }' \
  "$ROOT/PaletteFooter.qml"
rg -Fq '{ keyLabel: "[Ctrl+r]", label: "Refresh" }' \
  "$ROOT/PaletteFooter.qml"
rg -Fq '{ keyLabel: "[Ctrl+s]", label: "Settings" }' \
  "$ROOT/PaletteFooter.qml"
if rg -q 'Ctrl\+Shift|isContextShortcut' "$ROOT/PluginControl.qml"; then
  printf 'not ok - shifted palette shortcuts remain\n' >&2
  exit 1
fi
rg -Fq 'sourcePath("scripts/open-settings.sh")' "$ROOT/PluginControl.qml"
rg -Fq 'openMarketplaceShortcut()' "$ROOT/PluginControl.qml"
rg -Fq 'openGithubShortcut()' "$ROOT/PluginControl.qml"
rg -q 'ListView \{' "$ROOT/PluginControl.qml"
rg -q 'textFormat: Text.PlainText' "$ROOT/PluginControl.qml"
rg -q 'queryInput.forceActiveFocus\(\)' "$ROOT/PluginControl.qml"
rg -q 'service.recordFocusReady\(\)' "$ROOT/PluginControl.qml"
rg -q 'service.recordSurfaceVisible\(\)' "$ROOT/PluginControl.qml"
rg -q 'cacheAgeSeconds' "$ROOT/PluginControl.qml"
rg -q '\[omarchyPath \+ "/bin/omarchy", "launch",' \
  "$ROOT/PluginControl.qml"
rg -q '"browser", url\]' "$ROOT/PluginControl.qml"
rg -q 'Qt.Key_Up' "$ROOT/PluginControl.qml"
rg -q 'Qt.Key_PageDown' "$ROOT/PluginControl.qml"
rg -q 'activateIndex\(selectedIndex\)' "$ROOT/PluginControl.qml"
rg -q 'Qt.Key_Tab' "$ROOT/PluginControl.qml"
rg -q 'commandCompletion' "$ROOT/PluginControl.qml"
rg -q 'function clearCompletedCommandPrefix()' "$ROOT/PluginControl.qml"
rg -Fq 'repository: String(value.repository' "$ROOT/PaletteViewModel.js"
rg -Fq 'font.pixelSize: Style.font.caption' "$ROOT/PaletteResultRow.qml"
rg -q 'pendingSnapshotId = pendingOperation === "browse"' \
  "$ROOT/PluginControl.qml"
rg -q 'String\(selectedRecord.id || ""\), pendingSnapshotId' \
  "$ROOT/PluginControl.qml"
rg -Fq '["add", "remove", "enable", "disable"]' \
  "$ROOT/ActionDialog.qml"
rg -Fq 'return "omarchy plugin enable "' "$ROOT/ActionDialog.qml"
rg -Fq 'return "omarchy plugin disable "' "$ROOT/ActionDialog.qml"
if rg -q 'add-bar|omarchy bar put' "$ROOT/PluginControl.qml" \
    "$ROOT/ActionDialog.qml" "$ROOT/Service.qml"; then
  printf 'not ok - obsolete bar placement action remains\n' >&2
  exit 1
fi
if rg -q 'horizontalAlignment: Text.AlignHCenter' "$ROOT/PluginControl.qml"; then
  printf 'not ok - result text must not be centered\n' >&2
  exit 1
fi
printf 'ok - overlay lifecycle input shortcuts and left-aligned rows\n'

rg -Fq 'BarIconButton {' "$ROOT/PluginControlBar.qml"
rg -Fq 'text: "󰏖"' "$ROOT/PluginControlBar.qml"
rg -Fq 'Qt.LeftButton' "$ROOT/PluginControlBar.qml"
rg -Fq 'root.bar.shell.toggle' "$ROOT/PluginControlBar.qml"
rg -Fq 'Qt.RightButton' "$ROOT/PluginControlBar.qml"
rg -Fq 'text: "Settings"' "$ROOT/PluginControlBar.qml"
rg -Fq "root.bar.shell.toggle(root.moduleName, '{\"settings\":true}')" \
  "$ROOT/PluginControlBar.qml"
if rg -q 'Remove Plugin Control|removePluginControl' \
  "$ROOT/PluginControlBar.qml"; then
  printf 'not ok - destructive action remains in the bar popup\n' >&2
  exit 1
fi
rg -Fq 'setting("trayIconHidden", false) === true' \
  "$ROOT/PluginControlBar.qml"
printf 'ok - bar launcher uses the native package button and settings menu\n'

rg -Fq 'color: root.shortcutColor' "$ROOT/PaletteFooter.qml"
rg -Fq 'color: Util.alpha(root.foreground, 0.16)' \
  "$ROOT/PaletteFooter.qml"
rg -q 'sourceLabel:' "$ROOT/PaletteViewModel.js"
rg -q 'service.actionRunning' "$ROOT/PluginControl.qml"
rg -Fq 'actionNoticeDurationMs: 10000' "$ROOT/Service.qml"
rg -Fq 'refreshSuccessDurationMs: 10000' "$ROOT/Service.qml"
if rg -q 'startupRefreshPending|requestRefresh\(false\)' "$ROOT/Service.qml"; then
  printf 'not ok - service automatically refreshes the catalog at startup\n' >&2
  exit 1
fi
rg -Fq 'finishedUnacknowledged && isNewNotice' "$ROOT/Service.qml"
rg -Fq 'onTriggered: root.acknowledgeAction()' "$ROOT/Service.qml"
rg -Fq 'pluginRegistry.setBarWidget(' "$ROOT/Service.qml"
rg -Fq 'moduleName, "trayIconHidden", value, {}' "$ROOT/Service.qml"
rg -Fq 'configSyncProcess.command = [helperPath, "config-status", sourceDir]' \
  "$ROOT/Service.qml"
rg -Fq 'root.configChangeRevision++' "$ROOT/Service.qml"
rg -Fq 'id: channelConfigFile' "$ROOT/Service.qml"
rg -Fq 'channelConfigFile.reload()' "$ROOT/Service.qml"
rg -Fq 'omarchy-notification-send' "$ROOT/Service.qml"
rg -Fq 'root.notifyConfigProblem(output, revision)' "$ROOT/Service.qml"
rg -q 'actionDialog.openDialog\(\)' "$ROOT/PluginControl.qml"
rg -q 'function openSelectedInfo\(\)' "$ROOT/PluginControl.qml"
rg -q 'function showSettingsMenu\(\)' "$ROOT/PluginControl.qml"
rg -Fq 'name: "Cleanly remove Plugin Control and user data"' \
  "$ROOT/PaletteViewModel.js"
rg -Fq 'separatorBefore: true' "$ROOT/PaletteViewModel.js"
rg -q 'function openSelfRemovalDialog\(\)' "$ROOT/PluginControl.qml"
rg -Fq '"remove-purge"' "$ROOT/PluginControl.qml"
rg -Fq 'text: "Sure to remove Plugin Control?"' \
  "$ROOT/SelfRemovalDialog.qml"
rg -Fq '"Yes (preserve user data)"' "$ROOT/SelfRemovalDialog.qml"
rg -Fq '"Yes (delete user data)"' "$ROOT/SelfRemovalDialog.qml"
rg -Fq '"No / abort"' "$ROOT/SelfRemovalDialog.qml"
if rg -q 'removeSelf|tryOpenSelfRemoval|selfRemovalRequested' \
  "$ROOT/PluginControl.qml"; then
  printf 'not ok - obsolete self-removal payload remains\n' >&2
  exit 1
fi
rg -q 'Qt.Key_J' "$ROOT/PluginControl.qml"
rg -q 'Qt.Key_K' "$ROOT/PluginControl.qml"
rg -Fq 'readOnly: root.settingsMenuOpen' "$ROOT/PluginControl.qml"
rg -Fq 'name: "Cancel / Back"' "$ROOT/PaletteViewModel.js"
rg -Fq 'visible: root.paletteChromeVisible' "$ROOT/PluginControl.qml"
rg -Fq 'height: root.activeHeaderHeight' "$ROOT/PluginControl.qml"
rg -Fq 'height: root.activeFooterHeight' "$ROOT/PluginControl.qml"
rg -Fq 'focus: root.settingsMenuOpen' "$ROOT/PluginControl.qml"
rg -Fq 'if (pendingOperation === "browse") return' \
  "$ROOT/PluginControl.qml"
rg -q 'installInTerminal' "$ROOT/PluginControl.qml"
rg -q 'omarchy-launch-terminal' "$ROOT/lib/backend/actions.sh"
rg -q 'signal confirmed' "$ROOT/ActionDialog.qml"
rg -Fq 'return "Remove Plugin Control itself?"' "$ROOT/ActionDialog.qml"
rg -Fq 'if (selfRemoval) return "Yes, remove"' "$ROOT/ActionDialog.qml"
rg -Fq 'readonly property string cancelLabel: selfRemoval ? "No"' \
  "$ROOT/ActionDialog.qml"
rg -Fq 'plugin.commit || plugin.listingValidatedCommit' \
  "$ROOT/ActionDialog.qml"
rg -q 'ToggleSwitch \{' "$ROOT/ActionDialog.qml"
rg -q 'Run in Omarchy terminal' "$ROOT/ActionDialog.qml"
rg -q 'selectedChoice' "$ROOT/ActionDialog.qml"
rg -q 'applyBootstrap' "$ROOT/Service.qml"
rg -Fq 'return time + "  -  " + date' "$ROOT/PluginControl.qml"
rg -Fq 'color: root.statusColor' "$ROOT/PluginControl.qml"
rg -Fq 'opacity: root.statusOpacity' "$ROOT/PluginControl.qml"
printf 'ok - footer source confirmation busy and bootstrap states\n'

open_body="$(sed -n '/function open(payloadJson)/,/^  }/p' \
  "$ROOT/PluginControl.qml")"
if grep -Eq 'curl|git|requestRefresh' <<<"$open_body"; then
  printf 'not ok - open path performs network or Git work\n' >&2
  exit 1
fi
printf 'ok - overlay open path has no network or Git action\n'

shared_shortcuts="$ROOT/../_shared/shortcuts"
if [[ -d $shared_shortcuts ]]; then
  cmp -s "$ROOT/lib/shortcuts/ShortcutFormat.js" \
    "$shared_shortcuts/ShortcutFormat.js"
  cmp -s "$ROOT/lib/shortcuts/HyprlandBinding.qml" \
    "$shared_shortcuts/HyprlandBinding.qml"
  printf 'ok - shared shortcut library copies are current\n'
else
  printf 'ok - shared shortcut comparison skipped outside the monorepo\n'
fi

runtime_root="$(mktemp -d /tmp/plugin-control-qml-load.XXXXXX)"
trap 'rm -rf -- "$runtime_root"' EXIT
mkdir -p "$runtime_root/config" "$runtime_root/home"
cp "$TEST_DIR/fixtures/qml-entrypoints/shell.qml" \
  "$runtime_root/config/shell.qml"
ln -s /usr/share/omarchy/shell/Commons "$runtime_root/config/Commons"
ln -s /usr/share/omarchy/shell/Ui "$runtime_root/config/Ui"
if ! env QT_QPA_PLATFORM=wayland HOME="$runtime_root/home" \
  OMARCHY_PATH=/usr/share/omarchy PLUGIN_CONTROL_SOURCE_DIR="$ROOT" \
  QML2_IMPORT_PATH=/usr/share/omarchy/shell \
  QML_IMPORT_PATH=/usr/share/omarchy/shell \
  timeout 20 quickshell -p "$runtime_root/config" --no-color \
  >"$runtime_root/quickshell.log" 2>&1; then
  sed -n '1,240p' "$runtime_root/quickshell.log" >&2
  exit 1
fi
grep -Fq 'PLUGIN_CONTROL_LOAD_OK service' "$runtime_root/quickshell.log"
grep -Fq 'PLUGIN_CONTROL_LOAD_OK overlay' "$runtime_root/quickshell.log"
grep -Fq 'PLUGIN_CONTROL_LOAD_OK bar-widget' "$runtime_root/quickshell.log"
grep -Fq 'PLUGIN_CONTROL_INTERACTION_OK palette interactions' \
  "$runtime_root/quickshell.log"
if grep -Fq 'PLUGIN_CONTROL_LOAD_ERROR' "$runtime_root/quickshell.log"; then
  sed -n '1,240p' "$runtime_root/quickshell.log" >&2
  exit 1
fi
printf 'ok - service overlay and bar widget instantiate in Quickshell\n'
