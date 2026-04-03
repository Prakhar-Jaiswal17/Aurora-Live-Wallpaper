// Aurora — WallpaperManager
// Singleton orchestrator: manages WallpaperWindow per display, handles Finder
// restart detection, adaptive health checks, state restoration, and power state responses.

import AppKit
import AVFoundation

/// Central manager for all wallpaper windows across connected displays.
/// Handles lifecycle, Finder restart recovery, and health monitoring.
final class WallpaperManager {

    // MARK: - Singleton

    static let shared = WallpaperManager()

    // MARK: - Properties

    /// Active wallpaper windows keyed by display ID.
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]

    /// Active video engines keyed by display ID.
    private var engines: [CGDirectDisplayID: VideoPlayerEngine] = [:]

    /// Per-display wallpaper assignments (display ID → wallpaper ID).
    private var assignments: [CGDirectDisplayID: UUID] = [:]

    /// Health check timer.
    private var healthCheckTimer: Timer?

    /// Current health check interval (adaptive: 2s on failure, 10s when stable).
    private var healthCheckInterval: TimeInterval = 10.0

    /// Number of consecutive successful health checks (for adaptive timing).
    private var consecutiveHealthyChecks: Int = 0

    /// Whether playback is paused globally (by user or system).
    private(set) var isPaused: Bool = false

    /// Whether playback is throttled (battery mode).
    private(set) var isThrottled: Bool = false

    // MARK: - Init

    private init() {
        setupFinderRestartObserver()
        startHealthCheckTimer()
        AuroraLogger.engine.info("WallpaperManager initialized")
    }

    // MARK: - Window Management

    /// Creates wallpaper windows for all connected displays.
    func initializeWindows() {
        AuroraLogger.engine.info("Initializing wallpaper windows for \(NSScreen.screens.count) display(s)")

        for screen in NSScreen.screens {
            let displayID = screen.displayID
            guard windows[displayID] == nil else {
                AuroraLogger.engine.debug("Window already exists for display \(displayID), skipping")
                continue
            }
            createWindow(for: screen)
        }
    }

    /// Creates a wallpaper window for a specific screen.
    private func createWindow(for screen: NSScreen) {
        let displayID = screen.displayID
        let window = WallpaperWindow(for: screen)

        // Make the window's content view layer-backed for AVPlayerLayer
        let contentView = NSView(frame: screen.frame)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = contentView

        windows[displayID] = window
        window.showWithFadeIn()

        AuroraLogger.logWindowState("Window created and shown for display \(displayID)")
    }

    /// Removes and cleans up the wallpaper window for a display.
    func removeWindow(for displayID: CGDirectDisplayID) {
        // Clean up engine first (memory leak prevention)
        if let engine = engines[displayID] {
            engine.cleanup()
            engines.removeValue(forKey: displayID)
        }

        // Clean up window
        if let window = windows[displayID] {
            window.cleanup()
            windows.removeValue(forKey: displayID)
        }

        assignments.removeValue(forKey: displayID)
        AuroraLogger.logWindowState("Removed window and engine for display \(displayID)")
    }

    /// Removes all wallpaper windows.
    func removeAllWindows() {
        AuroraLogger.engine.info("Removing all wallpaper windows")
        let displayIDs = Array(windows.keys)
        for displayID in displayIDs {
            removeWindow(for: displayID)
        }
    }

    /// Reinitializes all windows (used after Finder restart).
    func reinitializeWindows() {
        AuroraLogger.logRecovery("Reinitializing all wallpaper windows")

        // Store current assignments before teardown
        let savedAssignments = assignments

        // Tear down everything
        removeAllWindows()

        // Small delay to let Finder settle after restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            // Recreate windows
            self.initializeWindows()

            // Restore wallpaper assignments
            for (displayID, wallpaperID) in savedAssignments {
                if let wallpaper = WallpaperLibrary.shared.wallpaper(withID: wallpaperID) {
                    self.setWallpaper(wallpaper, for: displayID)
                }
            }

            AuroraLogger.logRecovery("Window reinitialization complete")
        }
    }

    // MARK: - Wallpaper Assignment

    /// Sets a wallpaper on a specific display.
    /// - Parameters:
    ///   - wallpaper: The wallpaper to display.
    ///   - displayID: The target display. If nil, applies to the main display.
    func setWallpaper(_ wallpaper: Wallpaper, for displayID: CGDirectDisplayID? = nil) {
        let targetID = displayID ?? NSScreen.main?.displayID ?? 0

        guard let window = windows[targetID] else {
            AuroraLogger.logFailure("No window found for display \(targetID)")
            return
        }

        guard let contentView = window.contentView, let layer = contentView.layer else {
            AuroraLogger.logFailure("No content layer for display \(targetID)")
            return
        }

        // Clean up existing engine for this display
        if let existingEngine = engines[targetID] {
            existingEngine.cleanup()
        }

        // Create new video engine
        let engine = VideoPlayerEngine(settings: wallpaper.playbackSettings)
        engines[targetID] = engine
        assignments[targetID] = wallpaper.id

        // Load the video (engine auto-plays on load)
        let fileURL = URL(fileURLWithPath: wallpaper.filePath)
        engine.loadVideo(url: fileURL, into: layer) { error in
            if let error = error {
                AuroraLogger.logFailure("Failed to load wallpaper '\(wallpaper.name)': \(error.localizedDescription)")
                return
            }
            AuroraLogger.engine.info("Wallpaper '\(wallpaper.name, privacy: .public)' playing on display \(targetID)")
        }

        // If globally paused, pause this new engine too
        if isPaused {
            engine.pause()
        }

        // Persist assignment for state restoration
        WallpaperLibrary.shared.saveAssignment(wallpaperID: wallpaper.id, displayID: targetID)
    }

    /// Returns the currently active wallpaper ID for a display.
    func currentWallpaperID(for displayID: CGDirectDisplayID) -> UUID? {
        return assignments[displayID]
    }

    // MARK: - Global Playback Control

    /// Pauses all wallpaper playback.
    func pauseAll() {
        isPaused = true
        for engine in engines.values {
            engine.pause()
        }
        AuroraLogger.engine.info("All wallpapers paused")
    }

    /// Resumes all wallpaper playback.
    func resumeAll() {
        isPaused = false
        for engine in engines.values {
            engine.play()
        }
        AuroraLogger.engine.info("All wallpapers resumed")
    }

    /// Toggles global playback.
    func toggleAll() {
        if isPaused {
            resumeAll()
        } else {
            pauseAll()
        }
    }

    // MARK: - Throttling (Battery/Performance)

    /// Throttles all playback to the given rate (e.g., 0.5 for battery saving).
    func throttleAll(rate: Float) {
        isThrottled = true
        for engine in engines.values {
            engine.setThrottledRate(rate)
        }
        AuroraLogger.logPerformanceAction("All wallpapers throttled to rate \(rate)")
    }

    /// Restores normal playback rate on all engines.
    func unthrottleAll() {
        isThrottled = false
        for engine in engines.values {
            engine.restoreNormalRate()
        }
        AuroraLogger.logPerformanceAction("All wallpapers restored to normal rate")
    }

    /// Set a framerate target on all engines (or nil to remove limit).
    func setFramerateTargetAll(_ fps: Int?) {
        for engine in engines.values {
            engine.setFramerateTarget(fps)
        }
        if let fps = fps {
            AuroraLogger.logPerformanceAction("All wallpapers throttled to \(fps) FPS")
        } else {
            AuroraLogger.logPerformanceAction("All wallpapers restored to normal framerate")
        }
    }

    // MARK: - Finder Restart Detection

    /// Observes Finder relaunch to recover wallpaper windows.
    private func setupFinderRestartObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "com.apple.finder" {
                AuroraLogger.logRecovery("Finder relaunched — reinitializing wallpaper windows")
                self.reinitializeWindows()
            }
        }

        AuroraLogger.system.info("Finder restart observer registered")
    }

    // MARK: - Adaptive Health Checks

    /// Starts the periodic health check timer.
    private func startHealthCheckTimer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
        AuroraLogger.engine.info("Health check timer started (interval: \(self.healthCheckInterval)s)")
    }

    /// Validates all windows are correctly positioned and visible.
    private func performHealthCheck() {
        var allHealthy = true

        for (displayID, window) in windows {
            if !window.isHealthy {
                allHealthy = false
                AuroraLogger.logFailure("Unhealthy window detected for display \(displayID), attempting recovery")
                recoverWindow(for: displayID)
            }
        }

        // Also check if we're missing windows for any connected screen
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            if windows[displayID] == nil {
                allHealthy = false
                AuroraLogger.logFailure("Missing window for display \(displayID), creating")
                createWindow(for: screen)

                // Restore wallpaper if we had one
                if let wallpaperID = assignments[displayID],
                   let wallpaper = WallpaperLibrary.shared.wallpaper(withID: wallpaperID) {
                    setWallpaper(wallpaper, for: displayID)
                }
            }
        }

        // Adaptive timing: speed up after failure, slow down when stable
        if allHealthy {
            consecutiveHealthyChecks += 1
            if consecutiveHealthyChecks >= 3 && healthCheckInterval < 10.0 {
                // Stable for 3 checks → relax to 10s
                healthCheckInterval = 10.0
                startHealthCheckTimer()
                AuroraLogger.engine.debug("Health check interval relaxed to 10s (stable)")
            }
        } else {
            consecutiveHealthyChecks = 0
            if healthCheckInterval > 2.0 {
                // Failure detected → ramp up to 2s
                healthCheckInterval = 2.0
                startHealthCheckTimer()
                AuroraLogger.engine.info("Health check interval tightened to 2s (failure detected)")
            }
        }
    }

    /// Attempts to recover a single unhealthy window.
    private func recoverWindow(for displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            AuroraLogger.logFailure("Cannot recover window for display \(displayID): screen not found")
            removeWindow(for: displayID)
            return
        }

        let savedWallpaperID = assignments[displayID]

        // Tear down the broken window
        removeWindow(for: displayID)

        // Recreate
        createWindow(for: screen)

        // Restore wallpaper
        if let wallpaperID = savedWallpaperID,
           let wallpaper = WallpaperLibrary.shared.wallpaper(withID: wallpaperID) {
            setWallpaper(wallpaper, for: displayID)
        }

        AuroraLogger.logRecovery("Window recovered for display \(displayID)")
    }

    // MARK: - State Restoration

    /// Restores wallpapers from the last session on app launch.
    func restoreLastSession() {
        let savedAssignments = WallpaperLibrary.shared.loadAssignments()

        guard !savedAssignments.isEmpty else {
            AuroraLogger.engine.info("No previous session to restore")
            return
        }

        AuroraLogger.engine.info("Restoring \(savedAssignments.count) wallpaper assignment(s) from last session")

        for (displayIDValue, wallpaperID) in savedAssignments {
            let displayID = CGDirectDisplayID(displayIDValue)
            if let wallpaper = WallpaperLibrary.shared.wallpaper(withID: wallpaperID) {
                setWallpaper(wallpaper, for: displayID)
            }
        }
    }

    // MARK: - Display Change Handling

    /// Called by DisplayManager when screens change.
    func handleScreenChange() {
        AuroraLogger.system.info("Screen configuration changed")

        // Remove windows for disconnected displays
        let connectedDisplayIDs = Set(NSScreen.screens.map { $0.displayID })
        let existingDisplayIDs = Set(windows.keys)
        let removedDisplayIDs = existingDisplayIDs.subtracting(connectedDisplayIDs)

        for displayID in removedDisplayIDs {
            AuroraLogger.system.info("Display \(displayID) disconnected, removing window")
            removeWindow(for: displayID)
        }

        // Add windows for newly connected displays
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            if windows[displayID] == nil {
                AuroraLogger.system.info("New display \(displayID) detected, creating window")
                createWindow(for: screen)
            } else {
                // Update frame for existing windows (resolution may have changed)
                windows[displayID]?.updateFrame()
                if let engine = engines[displayID] {
                    engine.updateLayerFrame(screen.frame)
                }
            }
        }
    }

    // MARK: - Cleanup

    /// Full cleanup on app termination.
    func shutdown() {
        AuroraLogger.engine.info("WallpaperManager shutting down")
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        removeAllWindows()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
