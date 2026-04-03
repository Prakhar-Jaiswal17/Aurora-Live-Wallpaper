# Aurora — macOS Live Wallpaper Engine

A native macOS application that renders live video wallpapers behind desktop icons, optimized for Apple Silicon.

## The Story

I watched an Instagram reel sharing tips and tricks to keep a PC running smoothly. In that reel, the creator had a very good-looking live wallpaper running on their Windows PC. I wanted to have a similar live wallpaper on my MacBook's home screen, but I soon encountered a problem: macOS doesn't let you set custom live wallpapers natively like Windows does. To make matters worse, macOS lacks free software that allows users to set a custom live wallpaper—the apps I found were either paid, left a watermark, or significantly reduced the quality of the wallpaper.

I was about to give up on the idea of having a live wallpaper on my MacBook, but then I realized I could just build one myself! So I used Antigravity and Claude to create this app, which allows me to set high-quality live wallpapers on my MacBook for free.

## Features

- **Live wallpapers** — Play MP4/MOV videos as desktop backgrounds
- **Behind desktop icons** — True wallpaper-layer rendering, not a fullscreen window
- **Multi-display support** — Independent wallpapers per monitor
- **Smart power management** — 3-tier battery modes (Aggressive/Balanced/Permissive)
- **Fullscreen detection** — Auto-pauses when a fullscreen app is active (debounced dual-heuristic)
- **Finder restart recovery** — Auto-recovers wallpaper windows if Finder crashes
- **State restoration** — Restores last session on app launch
- **Menu bar app** — Quick controls from the status bar (no Dock icon)
- **Wallpaper library** — Import, preview, search, and manage wallpapers
- **macOS Spaces compatible** — Wallpapers persist across all Spaces

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (for building)
- Apple Silicon recommended (M1/M2/M3/M4)

## Installation

### Option 1: Quick Download (No terminal needed)*
1. Go to the [Releases page](#) on this GitHub repository. *(Don't forget to link this once published!)*
2. Download the latest `Aurora.dmg` file.
3. Open the downloaded `.dmg` file.
4. Drag and drop the **Aurora** app into the **Applications** folder.
5. Double-click **Aurora** in your Applications folder to launch it.
6. **Note on first launch:** You may get a warning saying that Apple can't recognize this app. 
   - Click **Done** on the warning dialog.
   - Go to **System Settings** > **Privacy & Security**.
   - Scroll to the bottom and click **Open Anyway** next to Aurora.

### Option 2: Build From Source (Using build script)
If you prefer to compile it yourself, you can use the provided build script:

1. Open Terminal and navigate to the project directory.
2. Run the build script:
   ```bash
   ./build_app.sh
   ```
3. The script will generate an `Aurora.app` file in the project directory.
4. Move `Aurora.app` to your Applications folder:
   ```bash
   cp -R Aurora.app /Applications/
   ```
5. Double-click **Aurora** in your Applications folder to launch it. 

*(Note: On first launch, macOS may request Screen Recording permission to manage the wallpaper properly).*

## Building for Development

### Option 1: Swift Package Manager (Terminal)

```bash
cd Aurora
swift build
```

Run the app:
```bash
.build/debug/Aurora
```

### Option 2: Xcode

1. Open `Aurora/Package.swift` in Xcode (double-click or `xed Aurora/Package.swift`)
2. Select the **Aurora** scheme
3. Set the deployment target to **macOS 13.0**
4. Press **Cmd+R** to build and run

## Usage

1. **Launch Aurora** — A sparkle ✦ icon appears in the menu bar
2. **Import a wallpaper** — Click the menu bar icon → "Import Wallpaper..." → Select an MP4 or MOV file
3. **Preview** — Right-click a wallpaper in the library → "Preview"
4. **Apply** — Right-click → "Apply to Desktop" or use the Preview panel's "Apply" button
5. **Configure** — Menu bar → "Preferences..." for battery, performance, and general settings

## How It Works

Aurora creates a borderless `NSWindow` positioned at `CGWindowLevelForKey(.desktopWindow) - 1`, which places it:

```
Normal Windows (Safari, Xcode, etc.)    ← Highest
Finder Desktop Icons
★ Aurora WallpaperWindow ★               ← Our window
macOS Desktop Background                 ← Lowest
```

This ensures the video plays behind desktop icons while remaining above the static desktop background. The window uses `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]` to persist across Spaces and hide from Mission Control.

## Architecture

```
Sources/Aurora/
├── Engine/         — Core video rendering (AVPlayer, window management)
├── System/         — macOS integration (displays, power, performance, spaces)
├── UI/             — User interface (menu bar, preferences, library, preview)
├── Models/         — Data models and persistence
├── AppDelegate     — App lifecycle
└── main.swift      — Entry point
```

## Performance

- Hardware-accelerated video decoding via AVFoundation (native on Apple Silicon)
- Adaptive health checks (2s on failure → 10s when stable)
- CPU monitoring with 5-sample rolling average to prevent noisy throttling
- Fullscreen detection with 1-second debounce to prevent false positives

## Notes

- Aurora runs as an **accessory app** (`LSUIElement = true`) — no Dock icon
- On first launch, macOS may request Screen Recording permission
- Wallpaper files are stored in `~/Library/Application Support/Aurora/Wallpapers/`
- Library catalog is at `~/Library/Application Support/Aurora/library.json`

## License

This project is licensed under the [Apache License 2.0](LICENSE). This means you are free to use, modify, and distribute the software, but anyone who does must include the original copyright notice, explicitly state any changes they make to the files, and fully credit you as the original author.
