#!/bin/bash
# build.sh — compile the Linker menu bar app.
#   ./build.sh              → build/Linker.app
#   ./build.sh --install    → also copy to /Applications and launch it
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: the native app requires macOS. From the project root, preview it with: python3 macos/preview.py" >&2
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install the Xcode Command Line Tools:  xcode-select --install" >&2
  exit 1
fi

APP="build/Linker.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx13.0" \
  LinkerApp.swift LinkerViews.swift -o "$APP/Contents/MacOS/Linker"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Linker</string>
  <key>CFBundleDisplayName</key><string>Linker</string>
  <key>CFBundleIdentifier</key><string>dev.arjun.linker</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleExecutable</key><string>Linker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# ad-hoc sign so Gatekeeper is happy with a locally built app
codesign --force --sign - "$APP" 2>/dev/null || true
echo "✓ built $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/Linker.app
  cp -R "$APP" /Applications/
  echo "✓ installed to /Applications/Linker.app"
  open /Applications/Linker.app
fi
