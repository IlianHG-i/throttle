#!/bin/bash
# Builds RAMBrider.app, installs it to /Applications, and registers it as a
# login item (LaunchAgent) so it starts automatically at every login.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RAMBrider"
BUNDLE_ID="com.ilianhg.RAMBrider"
INSTALL_DIR="/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
PLIST_PATH="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

echo "==> Build"
"$ROOT_DIR/Scripts/build_app.sh"

echo "==> Installation dans $INSTALL_DIR"
rm -rf "$INSTALLED_APP"
cp -R "$ROOT_DIR/dist/$APP_NAME.app" "$INSTALLED_APP"

echo "==> Enregistrement comme item de demarrage (LaunchAgent)"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALLED_APP/Contents/MacOS/$APP_NAME</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
EOF

echo "==> Activation (sans attendre le prochain login)"
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "==> Installe: $INSTALLED_APP"
echo "==> Se lancera desormais automatiquement a chaque connexion"
echo "==> Pour desactiver: launchctl bootout gui/\$(id -u) \"$PLIST_PATH\" && rm \"$PLIST_PATH\""
