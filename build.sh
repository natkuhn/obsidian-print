#!/bin/bash
# Builds "Save PDF to Obsidian.app" into build/. With --install, also puts
# it in ~/Library/PDF Services (replacing any earlier version, including the
# old script-only version).
set -euo pipefail
cd "$(dirname "$0")"

NAME="Save PDF to Obsidian"
APP="build/$NAME.app"

rm -rf "$APP"
mkdir -p build
osacompile -o "$APP" "$NAME.applescript"
cp obsidian_print.py "$APP/Contents/Resources/"
plutil -replace CFBundleIdentifier -string "com.natkuhn.save-pdf-to-obsidian" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"  # re-sign after adding files to the bundle
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
  DEST="$HOME/Library/PDF Services"
  mkdir -p "$DEST"
  rm -rf "$DEST/$NAME.app"
  rm -f "$DEST/$NAME"  # the old script-only version, which would duplicate the menu item
  cp -R "$APP" "$DEST/"
  echo "Installed to $DEST/$NAME.app"
fi
