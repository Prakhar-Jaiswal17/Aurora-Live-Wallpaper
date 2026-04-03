#!/bin/bash
# Script to create a macOS .dmg file for Aurora
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Aurora"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
DMG_NAME="${APP_NAME}.dmg"

echo "🚀 Starting .dmg creation process..."

# Step 1: Ensure the .app is built
if [ ! -d "$APP_DIR" ]; then
    echo "⚠️  Aurora.app not found in the current directory."
    echo "⚙️  Running build_app.sh to generate it first..."
    sh "$SCRIPT_DIR/build_app.sh"
else
    echo "✅ Found existing $APP_NAME.app"
fi

# Step 2: Set up a staging directory
STAGING_DIR="/tmp/${APP_NAME}_staging"
echo "🗂️  Setting up staging folder at $STAGING_DIR..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Step 3: Copy the app into the staging folder
cp -R "$APP_DIR" "$STAGING_DIR/"

# Step 4: Create a convenient shortcut to the Applications folder
echo "🔗 Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

# Step 5: Convert the staging directory into a .dmg file using hdiutil
echo "💿 Generating the .dmg file..."
rm -f "$SCRIPT_DIR/$DMG_NAME"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$SCRIPT_DIR/$DMG_NAME"

# Step 6: Clean up the staging directory
rm -rf "$STAGING_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Suberb! $DMG_NAME created successfully!"
echo "📍 Location: $SCRIPT_DIR/$DMG_NAME"
echo ""
echo "You can now upload this .dmg to your GitHub Releases!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
