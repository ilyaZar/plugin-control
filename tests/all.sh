#!/bin/bash

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
readonly ROOT

bash -n "$ROOT/bin/plugin-control" "$ROOT/lib/backend"/*.sh \
  "$ROOT/scripts/open-settings.sh" "$TEST_DIR"/*.sh
ruby -c "$ROOT/lib/channel_config.rb"
node "$TEST_DIR/model.test.js"
ruby "$TEST_DIR/channel_config.test.rb"
"$TEST_DIR/catalog.test.sh"
"$TEST_DIR/issues.test.sh"
"$TEST_DIR/backend.test.sh"
"$TEST_DIR/updates.test.sh"
"$TEST_DIR/helpers.test.sh"
"$TEST_DIR/qml.test.sh"

qmltestrunner_bin="$(command -v qmltestrunner)"
if [[ -x /usr/lib/qt6/bin/qmltestrunner ]]; then
  qmltestrunner_bin=/usr/lib/qt6/bin/qmltestrunner
fi
QT_QPA_PLATFORM=offscreen "$qmltestrunner_bin" \
  -input "$TEST_DIR/tst_models.qml" -import "$ROOT"
QT_QPA_PLATFORM=offscreen "$qmltestrunner_bin" \
  -input "$TEST_DIR/tst_palette_footer.qml" -import "$ROOT" \
  -import "$TEST_DIR/fixtures/qml-imports"
QT_QPA_PLATFORM=offscreen "$qmltestrunner_bin" \
  -input "$TEST_DIR/tst_action_dialog.qml" -import "$ROOT" \
  -import "$TEST_DIR/fixtures/qml-imports"
QT_QPA_PLATFORM=offscreen "$qmltestrunner_bin" \
  -input "$TEST_DIR/tst_self_removal_dialog.qml" -import "$ROOT" \
  -import "$TEST_DIR/fixtures/qml-imports"

printf 'ok - all Plugin Control tests\n'
