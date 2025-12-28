#!/bin/bash

# Build script for MCPanel.app
# Usage: ./build-app.sh [--release]
#   Default: debug mode (faster builds)
#   --release: optimized release build

set -e
set -o pipefail

APP_NAME="MCPanel"
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Parse arguments
BUILD_CONFIG="debug"
BUILD_DIR=".build/debug"
if [[ "$1" == "--release" ]]; then
    BUILD_CONFIG="release"
    BUILD_DIR=".build/release"
    echo "🖥️  Building $APP_NAME in release mode (optimized)..."
    swift build -c release 2>&1 | { grep -v "found 1 file(s) which are unhandled" || true; }
else
    echo "🖥️  Building $APP_NAME in debug mode (fast)..."
    swift build 2>&1 | { grep -v "found 1 file(s) which are unhandled" || true; }
fi

echo "📦 Creating app bundle..."

# Remove old bundle if exists
rm -rf "$APP_BUNDLE"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy app icon
echo "🎨 Copying app icon..."
if [ -f "MCPanel.icns" ]; then
    cp "MCPanel.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "branding/AppIcon.icns" ]; then
    cp "branding/AppIcon.icns" "$RESOURCES_DIR/"
else
    echo "⚠️  No AppIcon.icns found."
fi

# Copy secrets file if exists (for development)
if [ -f ".secrets.json" ]; then
    cp ".secrets.json" "$RESOURCES_DIR/"
    echo "📋 Copied .secrets.json to bundle"
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>md.thomas.mcpanel</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MCPanel</string>
    <key>CFBundleDisplayName</key>
    <string>MCPanel</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "✅ App bundle created: $APP_BUNDLE"
echo ""
echo "🚀 Launching MCPanel..."

# Quit any running instance
osascript -e 'tell application "MCPanel" to quit' >/dev/null 2>&1 || true
pkill -x MCPanel >/dev/null 2>&1 || true
sleep 0.5

open "$APP_BUNDLE"
