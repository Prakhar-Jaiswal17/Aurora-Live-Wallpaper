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

        // 2. Initialize wallpaper engine
        WallpaperManager.shared.initializeWindows()

        // 3. Set up the menu bar interface
        statusBarController = StatusBarController()

        // 4. Restore last session if enabled
        if AuroraSettings.shared.restoreLastSession {
            WallpaperManager.shared.restoreLastSession()
        }

        // 5. Start wallpaper cycling if enabled
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
}
