#!/bin/bash
# Builds Shortcut Coach, installs it in ~/Applications and starts it now and at every login.
set -euo pipefail
cd "$(dirname "$0")/.."

label=local.shortcut-coach
app="$HOME/Applications/Shortcut Coach.app"
agent="$HOME/Library/LaunchAgents/$label.plist"

swift build -c release

launchctl bootout "gui/$UID/$label" 2>/dev/null || true
while launchctl print "gui/$UID/$label" &>/dev/null; do sleep 0.2; done  # bootout is asynchronous

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$HOME/Library/LaunchAgents"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp .build/release/ShortcutCoach "$app/Contents/MacOS/ShortcutCoach"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>$label</string>
    <key>CFBundleName</key><string>Shortcut Coach</string>
    <key>CFBundleExecutable</key><string>ShortcutCoach</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
EOF
codesign --force --sign - "$app"

cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key><array><string>$app/Contents/MacOS/ShortcutCoach</string></array>
    <key>RunAtLoad</key><true/>
    <!-- Without this launchd throttles the app's timers and the 30 Hz key poll runs at about 12 Hz. -->
    <key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF
launchctl bootstrap "gui/$UID" "$agent"
echo "Installed and running: $app"
