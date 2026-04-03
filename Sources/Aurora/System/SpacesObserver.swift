// Aurora — SpacesObserver
// Handles macOS Spaces and Mission Control transitions.

import AppKit

/// Observes Space changes and ensures wallpaper windows persist correctly.
final class SpacesObserver {

    // MARK: - Singleton

    static let shared = SpacesObserver()

    // MARK: - Init

    private init() {
        setupObservers()
        AuroraLogger.system.info("SpacesObserver initialized")
    }

    // MARK: - Observation

    private func setupObservers() {
        // Observe active space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        AuroraLogger.system.info("Spaces and Mission Control observers registered")
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        AuroraLogger.system.debug("Active space changed")

        // WallpaperWindows use .canJoinAllSpaces, so they persist across spaces automatically.
        // However, we log this event for debugging and trigger a health check
        // in case the system moved our windows during the transition.

        // Brief delay to let the transition animation complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Verify windows are still healthy after space transition
            let allWindows = NSApplication.shared.windows.compactMap { $0 as? WallpaperWindow }
            for window in allWindows {
                if !window.isHealthy {
                    AuroraLogger.logFailure("Window unhealthy after space change for display \(window.displayID)")
                    // WallpaperManager's health check will handle recovery
                }
            }
        }
    }
}
