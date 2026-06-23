// Aurora — AppDelegate
// Application lifecycle management. Initializes all managers, sets up the
// menu bar, and coordinates state restoration on launch.

import AppKit

/// Main application delegate. Orchestrates initialization, lifecycle, and teardown.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// Status bar controller (menu bar app).
    private var statusBarController: StatusBarController?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AuroraLogger.engine.info("Aurora starting up...")

        // 1. Initialize system managers (order matters)
        _ = DisplayManager.shared       // Track connected displays
        _ = SpacesObserver.shared        // Observe Space changes
        _ = PowerManager.shared          // Start battery monitoring
        _ = PerformanceMonitor.shared    // Start fullscreen/CPU monitoring

        // 2. Install companion screen saver for lock screen live wallpaper
        ScreenSaverManager.shared.installIfNeeded()

        // 3. Initialize wallpaper engine
        WallpaperManager.shared.initializeWindows()

        // 4. Set up the menu bar interface
        statusBarController = StatusBarController()

        // 5. First-launch setup: auto-import default wallpaper and apply to all screens
        if !AuroraSettings.shared.hasCompletedFirstLaunch {
            performFirstLaunchSetup()
        }

        // 6. Restore last session if enabled (only if not first launch — first launch already applied)
        if AuroraSettings.shared.restoreLastSession && AuroraSettings.shared.hasCompletedFirstLaunch {
            WallpaperManager.shared.restoreLastSession()
        }

        // 7. Start wallpaper cycling if enabled
        WallpaperCycler.shared.start()

        AuroraLogger.engine.info("Aurora startup complete — \(NSScreen.screens.count) display(s) active")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AuroraLogger.engine.info("Aurora shutting down...")

        // Clean shutdown: stop monitoring, stop cycling, clean up engines, remove windows
        WallpaperCycler.shared.stop()
        PerformanceMonitor.shared.stopMonitoring()
        PowerManager.shared.stopMonitoring()
        WallpaperManager.shared.shutdown()

        AuroraLogger.engine.info("Aurora shutdown complete")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't terminate when the preferences window is closed — we're a menu bar app
        return false
    }

    /// Handle reopen (clicking the menu bar icon / Dock icon if visible).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Show the preferences window when reopened
        statusBarController?.showPreferences()
        return true
    }

    // MARK: - First Launch

    /// Performs first-launch setup: auto-imports the default wallpaper and applies
    /// it to all connected screens as both desktop and lock screen wallpaper.
    private func performFirstLaunchSetup() {
        AuroraLogger.engine.info("First launch detected — setting up default wallpaper")

        // Default wallpaper path: ~/Downloads/Aurora_Wall.mp4
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let defaultWallpaperURL = homeDir.appendingPathComponent("Downloads/Aurora_Wall.mp4")

        guard FileManager.default.fileExists(atPath: defaultWallpaperURL.path) else {
            AuroraLogger.engine.info("Default wallpaper not found at \(defaultWallpaperURL.path, privacy: .public) — skipping first-launch import")
            AuroraSettings.shared.hasCompletedFirstLaunch = true
            return
        }

        AuroraLogger.engine.info("Found default wallpaper at \(defaultWallpaperURL.path, privacy: .public) — importing")

        // Import the wallpaper file into the library
        ImportHandler.shared.importFile(at: defaultWallpaperURL) { wallpaper in
            guard let wallpaper = wallpaper else {
                AuroraLogger.logFailure("Failed to import default wallpaper")
                AuroraSettings.shared.hasCompletedFirstLaunch = true
                return
            }

            AuroraLogger.engine.info("Default wallpaper '\(wallpaper.name, privacy: .public)' imported — applying to all screens")

            // Apply to all connected screens with target .both (desktop + lock screen)
            for screen in NSScreen.screens {
                let displayID = screen.displayID
                WallpaperManager.shared.setWallpaper(wallpaper, for: displayID, target: .both)
                AuroraLogger.engine.info("Default wallpaper applied to display \(displayID)")
            }

            // Mark first launch as complete
            AuroraSettings.shared.hasCompletedFirstLaunch = true
            AuroraLogger.engine.info("First-launch setup complete")
        }
    }
}
