// Aurora — WallpaperCycler
// Automatically cycles through wallpapers in the library at a configurable interval.
// Supports minutes, hours, and days as time units with decimal precision.

import AppKit

/// Manages automatic wallpaper cycling on a configurable timer.
final class WallpaperCycler {

    // MARK: - Singleton

    static let shared = WallpaperCycler()

    // MARK: - Properties

    /// The timer that triggers wallpaper changes.
    private var cycleTimer: Timer?

    /// Index of the last wallpaper applied (for sequential cycling).
    private var currentIndex: Int = -1

    /// Whether cycling is currently active.
    private(set) var isActive: Bool = false

    // MARK: - Init

    private init() {
        // Listen for settings changes to restart the timer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .cycleSettingsChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    // MARK: - Start / Stop

    /// Starts the wallpaper cycling timer based on current settings.
    /// If cycling is disabled in settings, this is a no-op.
    func start() {
        let settings = AuroraSettings.shared

        guard settings.cycleEnabled else {
            AuroraLogger.engine.info("Wallpaper cycling is disabled, not starting")
            stop()
            return
        }

        let intervalSeconds = settings.cycleIntervalSeconds

        guard intervalSeconds > 0 else {
            AuroraLogger.logFailure("Invalid cycle interval: \(intervalSeconds)s")
            return
        }

        // Stop any existing timer
        cycleTimer?.invalidate()

        // Find current wallpaper index so we continue from where we are
        syncCurrentIndex()

        // Create the repeating timer
        cycleTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.cycleToNext()
        }

        isActive = true

        let unit = settings.cycleUnit.displayName.lowercased()
        AuroraLogger.engine.info(
            "Wallpaper cycling started: every \(settings.cycleInterval) \(unit) (\(intervalSeconds)s)"
        )
    }

    /// Stops the wallpaper cycling timer.
    func stop() {
        cycleTimer?.invalidate()
        cycleTimer = nil
        isActive = false
        AuroraLogger.engine.info("Wallpaper cycling stopped")
    }

    // MARK: - Cycling Logic

    /// Cycles to the next wallpaper in the library.
    private func cycleToNext() {
        let library = WallpaperLibrary.shared.wallpapers

        guard !library.isEmpty else {
            AuroraLogger.engine.info("No wallpapers in library to cycle")
            return
        }

        // Advance to next index (wrap around)
        currentIndex = (currentIndex + 1) % library.count
        let nextWallpaper = library[currentIndex]

        // Apply to main display
        WallpaperManager.shared.setWallpaper(nextWallpaper)

        AuroraLogger.engine.info(
            "Cycled to wallpaper '\(nextWallpaper.name, privacy: .public)' (index \(self.currentIndex)/\(library.count))"
        )
    }

    /// Syncs the currentIndex to match whatever wallpaper is currently playing.
    private func syncCurrentIndex() {
        guard let mainDisplayID = NSScreen.main?.displayID else { return }
        let library = WallpaperLibrary.shared.wallpapers

        if let currentWPID = WallpaperManager.shared.currentWallpaperID(for: mainDisplayID),
           let index = library.firstIndex(where: { $0.id == currentWPID }) {
            currentIndex = index
        } else {
            currentIndex = -1  // Will start from 0 on next cycle
        }
    }

    // MARK: - Settings Observer

    @objc private func settingsDidChange() {
        let settings = AuroraSettings.shared

        if settings.cycleEnabled {
            // Restart with new interval
            start()
        } else {
            stop()
        }
    }
}
