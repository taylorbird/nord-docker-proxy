#!/bin/zsh -f
# Builds "Nord Docker Proxy.app" (menu bar only, no Dock icon) into build/.
#   scripts/build-app.sh            build + sign
#   scripts/build-app.sh --install  also install into /Applications and point
#                                   `nord-docker-proxy` at the copy inside it
#
# The CLI, compose file and Docker files ship INSIDE the app, sealed by its
# signature; the app runs only that copy and verifies its own signature (and
# the publisher team below) before every command.
#
# Signing identity: NDP_SIGN_IDENTITY, default the first "Developer ID
# Application" identity in the keychain. Its team ID is written into
# Info.plist as NDPTeamID, the anchor for the app's self-check.
set -euo pipefail
REPO=${0:A:h:h}
cd "$REPO/app"

IDENTITY=${NDP_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}
[[ -n "$IDENTITY" ]] || { print -u2 "no Developer ID Application identity found; set NDP_SIGN_IDENTITY"; exit 1 }
TEAM=${${IDENTITY##*\(}%\)}
[[ "$TEAM" =~ '^[A-Z0-9]{10}$' ]] || { print -u2 "could not read a team ID from: $IDENTITY"; exit 1 }
VERSION=$(cat "$REPO/VERSION")

swift build -c release --product NordDockerProxy
BIN=$(swift build -c release --show-bin-path)/NordDockerProxy

APP="$REPO/build/Nord Docker Proxy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/nord-docker-proxy/bin"
cp "$BIN" "$APP/Contents/MacOS/NordDockerProxy"
cp "$REPO/bin/nord-docker-proxy" "$APP/Contents/Resources/nord-docker-proxy/bin/"
cp "$REPO/compose.yaml" "$APP/Contents/Resources/nord-docker-proxy/"
ditto "$REPO/docker" "$APP/Contents/Resources/nord-docker-proxy/docker"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Nord Docker Proxy</string>
  <key>CFBundleDisplayName</key><string>Nord Docker Proxy</string>
  <key>CFBundleIdentifier</key><string>com.tbird.norddockerproxy</string>
  <key>CFBundleExecutable</key><string>NordDockerProxy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Opens setup and logs in Terminal.</string>
  <key>NDPTeamID</key><string>$TEAM</string>
</dict>
</plist>
PLIST
# Developer ID + hardened runtime + secure timestamp (required for notarization).
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
print "Built $APP ($VERSION, team $TEAM)"

[[ "${1:-}" == --install ]] || exit 0
# /Applications, not ~/Applications: macOS 27 only handles menu bar items
# correctly for apps run from there.
pkill -x NordDockerProxy 2>/dev/null || true
rm -rf "/Applications/Nord Docker Proxy.app"
ditto "$APP" "/Applications/Nord Docker Proxy.app"
ln -sf "/Applications/Nord Docker Proxy.app/Contents/Resources/nord-docker-proxy/bin/nord-docker-proxy" \
  "$(brew --prefix)/bin/nord-docker-proxy"
print "Installed /Applications/Nord Docker Proxy.app; nord-docker-proxy → the copy inside it"
