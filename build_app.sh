#!/bin/bash
# Aurora — Build & Package as macOS .app Bundle
# Usage: ./build_app.sh
# Output: Aurora.app (ready to double-click)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Aurora"
BUNDLE_ID="com.aurora.livewallpaper"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🌌 Building Aurora..."

# 1. Build the Swift binary (release mode for performance)
swift build -c release --package-path "$SCRIPT_DIR" 2>&1

BINARY="$BUILD_DIR/release/Aurora"
if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed — binary not found"
    exit 1
fi

echo "✅ Build succeeded"

# 2. Create .app bundle structure
echo "📦 Creating .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy the binary
cp "$BINARY" "$MACOS_DIR/$APP_NAME"

# 4. Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Aurora</string>
    <key>CFBundleDisplayName</key>
    <string>Aurora</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Aurora</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# 5. Create app icon from the source image
ICON_SOURCE="$SCRIPT_DIR/Sources/Aurora/Resources/AppIcon.jpg"
if [ -f "$ICON_SOURCE" ]; then
    echo "🎨 Creating app icon..."
    ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    # First convert source JPG to a PNG master
    PNG_MASTER="/tmp/aurora_icon_master.png"
    sips -s format png "$ICON_SOURCE" --out "$PNG_MASTER" >/dev/null 2>&1

    # Generate all required icon sizes from the PNG master
    sips -z 16 16     "$PNG_MASTER" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null 2>&1
    sips -z 32 32     "$PNG_MASTER" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null 2>&1
    sips -z 32 32     "$PNG_MASTER" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null 2>&1
    sips -z 64 64     "$PNG_MASTER" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null 2>&1
    sips -z 128 128   "$PNG_MASTER" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null 2>&1
    sips -z 256 256   "$PNG_MASTER" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   "$PNG_MASTER" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null 2>&1
    sips -z 512 512   "$PNG_MASTER" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   "$PNG_MASTER" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null 2>&1
    sips -z 1024 1024 "$PNG_MASTER" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1

    # Convert iconset to icns
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null

    # Clean up
    rm -rf "$ICONSET_DIR" "$PNG_MASTER"

    echo "✅ App icon created"
else
    echo "⚠️  No icon source found at $ICON_SOURCE — app will use default icon"
fi

# 6. Build companion AuroraScreenSaver.saver bundle
echo "🖥️  Building companion screen saver..."

SAVER_SRC="$SCRIPT_DIR/Sources/AuroraScreenSaver/AuroraScreenSaverView.swift"
SAVER_PLIST="$SCRIPT_DIR/Sources/AuroraScreenSaver/Info.plist"
SAVER_BUNDLE="$RESOURCES_DIR/AuroraScreenSaver.saver"
SAVER_CONTENTS="$SAVER_BUNDLE/Contents"
SAVER_MACOS="$SAVER_CONTENTS/MacOS"

if [ -f "$SAVER_SRC" ] && [ -f "$SAVER_PLIST" ]; then
    mkdir -p "$SAVER_MACOS"

    # Detect architecture for compilation
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        TARGET="arm64-apple-macos13.0"
    else
        TARGET="x86_64-apple-macos13.0"
    fi

    # Compile the screen saver as a loadable bundle (dynamic library)
    swiftc \
        -module-name AuroraScreenSaver \
        -emit-library \
        -target "$TARGET" \
        -framework ScreenSaver \
        -framework AVFoundation \
        -framework AppKit \
        -framework QuartzCore \
        -Xlinker -bundle \
        -Xlinker -rpath -Xlinker @loader_path/../Frameworks \
        -o "$SAVER_MACOS/AuroraScreenSaver" \
        "$SAVER_SRC" 2>&1

    if [ $? -eq 0 ]; then
        # Copy the Info.plist
        cp "$SAVER_PLIST" "$SAVER_CONTENTS/Info.plist"
        echo "✅ Screen saver built"
    else
        echo "⚠️  Screen saver build failed — lock screen live wallpaper will be unavailable"
    fi
else
    echo "⚠️  Screen saver source not found — skipping"
fi

# 7. Ad-hoc code sign (required for modern macOS)
echo "🔏 Code signing..."
xattr -cr "$APP_DIR" 2>/dev/null
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null && echo "✅ Code signed" || echo "⚠️  Code signing skipped"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Aurora.app created successfully!"
echo "📍 Location: $APP_DIR"
echo ""
echo "To launch:  open \"$APP_DIR\""
echo "To install: cp -R \"$APP_DIR\" /Applications/"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
