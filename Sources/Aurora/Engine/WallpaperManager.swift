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
    private(set) var isPaused: Bool = false {
        didSet {
            if isPaused != oldValue {
                NotificationCenter.default.post(name: .wallpaperPauseStateChanged, object: nil)
            }
        }
    }

    /// Whether the pause was initiated by the user (vs. system/performance).
    /// System-initiated resumes should not override a user-initiated pause.
    private(set) var isUserPaused: Bool = false

    /// Whether audio is currently muted across all engines.
    private(set) var isMuted: Bool = true {
        didSet {
            if isMuted != oldValue {
                NotificationCenter.default.post(name: .wallpaperMuteStateChanged, object: nil)
            }
        }
    }

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
        // Use bounds-relative frame (origin 0,0) — screen.frame includes absolute offset
        let contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
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

    /// Sets a wallpaper on a specific display with a target scope.
    /// - Parameters:
    ///   - wallpaper: The wallpaper to display.
    ///   - displayID: The target display. If nil, applies to the main display.
    ///   - target: Where to apply: `.homeScreen` (live video), `.lockScreen` (screensaver), or `.both`.
    func setWallpaper(_ wallpaper: Wallpaper, for displayID: CGDirectDisplayID? = nil, target: WallpaperTarget = .homeScreen) {
        let targetID = displayID ?? NSScreen.main?.displayID ?? 0
        let fileURL = URL(fileURLWithPath: wallpaper.filePath)

        switch target {
        case .homeScreen:
            applyLiveWallpaper(wallpaper, fileURL: fileURL, displayID: targetID)

        case .lockScreen:
            applyLockScreenWallpaper(wallpaper, displayID: targetID)

        case .both:
            applyLiveWallpaper(wallpaper, fileURL: fileURL, displayID: targetID)
            applyLockScreenWallpaper(wallpaper, displayID: targetID)
        }

        // Persist assignment for state restoration
        WallpaperLibrary.shared.saveAssignment(wallpaperID: wallpaper.id, displayID: targetID)
    }

    /// Applies a live video wallpaper to the WallpaperWindow for a display.
    private func applyLiveWallpaper(_ wallpaper: Wallpaper, fileURL: URL, displayID: CGDirectDisplayID) {
        guard let window = windows[displayID] else {
            AuroraLogger.logFailure("No window found for display \(displayID)")
            return
        }

        guard let contentView = window.contentView, let layer = contentView.layer else {
            AuroraLogger.logFailure("No content layer for display \(displayID)")
            return
        }

        // Clean up existing engine for this display
        if let existingEngine = engines[displayID] {
            existingEngine.cleanup()
        }

        // Create new video engine
        let engine = VideoPlayerEngine(settings: wallpaper.playbackSettings)
        engines[displayID] = engine
        assignments[displayID] = wallpaper.id

        // Load the video (engine auto-plays on load)
        engine.loadVideo(url: fileURL, into: layer) { error in
            if let error = error {
                AuroraLogger.logFailure("Failed to load wallpaper '\(wallpaper.name)': \(error.localizedDescription)")
                return
            }
            AuroraLogger.engine.info("Wallpaper '\(wallpaper.name, privacy: .public)' playing on display \(displayID)")
        }

        // If globally paused, pause this new engine too
        if isPaused {
            engine.pause()
        }
    }

    /// Applies the lock screen wallpaper using a dual approach:
    /// 1. Sets a static frame as the system wallpaper (instant lock screen image)
    /// 2. Updates the companion screen saver config (animated idle screen)
    private func applyLockScreenWallpaper(_ wallpaper: Wallpaper, displayID: CGDirectDisplayID) {
        let fileURL = URL(fileURLWithPath: wallpaper.filePath)
        let settings = wallpaper.playbackSettings

        // 1. Update the companion screen saver config for idle-time animation
        ScreenSaverManager.shared.updateConfig(
            videoPath: wallpaper.filePath,
            isLooping: settings.isLooping,
            volume: settings.isMuted ? 0.0 : settings.volume,
            playbackSpeed: settings.playbackSpeed
        )

        // 2. Set a static frame as the system wallpaper for instant lock screen display
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let outputURL = self.dynamicWallpaperPath(for: wallpaper.name)

            do {
                // Try building an Apple-format dynamic HEIC wallpaper
                try DynamicWallpaperBuilder.createAppearanceWallpaper(
                    from: fileURL,
                    outputURL: outputURL
                )
                AuroraLogger.engine.info("Dynamic HEIC wallpaper built for '\(wallpaper.name, privacy: .public)'")
            } catch {
                AuroraLogger.logFailure("HEIC creation failed, falling back to JPEG: \(error.localizedDescription)")

                // Fallback: extract a single frame as JPEG
                let jpegURL = self.dynamicWallpaperPath(for: wallpaper.name, extension: "jpg")
                do {
                    try DynamicWallpaperBuilder.extractSingleFrame(from: fileURL, outputURL: jpegURL)
                } catch {
                    AuroraLogger.logFailure("Fallback JPEG extraction also failed: \(error.localizedDescription)")
                    return
                }

                DispatchQueue.main.async {
                    self.setSystemWallpaper(url: jpegURL, displayID: displayID, wallpaperName: wallpaper.name)
                }
                return
            }

            DispatchQueue.main.async {
                self.setSystemWallpaper(url: outputURL, displayID: displayID, wallpaperName: wallpaper.name)
            }
        }

        AuroraLogger.engine.info("Lock screen wallpaper updated for '\(wallpaper.name, privacy: .public)'")
    }

    /// Sets a static frame from a wallpaper video as the macOS system wallpaper.
    /// This changes the normal macOS desktop wallpaper without affecting the live overlay.
    /// - Parameters:
    ///   - wallpaper: The wallpaper to extract a frame from.
    ///   - displayID: The target display. If nil, applies to the main display.
    func setStaticWallpaper(_ wallpaper: Wallpaper, for displayID: CGDirectDisplayID? = nil) {
        let targetID = displayID ?? NSScreen.main?.displayID ?? 0
        let fileURL = URL(fileURLWithPath: wallpaper.filePath)

        AuroraLogger.engine.info("Setting static wallpaper from '\(wallpaper.name, privacy: .public)'")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Try to build a dynamic HEIC wallpaper first, fall back to JPEG
            let outputURL = self.dynamicWallpaperPath(for: wallpaper.name)

            do {
                try DynamicWallpaperBuilder.createAppearanceWallpaper(
                    from: fileURL,
                    outputURL: outputURL
                )
                AuroraLogger.engine.info("Static HEIC wallpaper built for '\(wallpaper.name, privacy: .public)'")
            } catch {
                AuroraLogger.logFailure("HEIC creation failed, falling back to JPEG: \(error.localizedDescription)")

                let jpegURL = self.dynamicWallpaperPath(for: wallpaper.name, extension: "jpg")
                do {
                    try DynamicWallpaperBuilder.extractSingleFrame(from: fileURL, outputURL: jpegURL)
                } catch {
                    AuroraLogger.logFailure("Fallback JPEG extraction also failed: \(error.localizedDescription)")
                    return
                }

                DispatchQueue.main.async {
                    self.setSystemWallpaper(url: jpegURL, displayID: targetID, wallpaperName: wallpaper.name)
                }
                return
            }

            DispatchQueue.main.async {
                self.setSystemWallpaper(url: outputURL, displayID: targetID, wallpaperName: wallpaper.name)
            }
        }
    }

    /// Sets the system wallpaper using NSWorkspace.
    /// AppleScript and Dock restart removed to prevent disrupting macOS native wallpaper system.
    private func setSystemWallpaper(url: URL, displayID: CGDirectDisplayID, wallpaperName: String) {
        // NSWorkspace API — the recommended approach on modern macOS
        for screen in NSScreen.screens {
            if screen.displayID == displayID || displayID == 0 {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                        .allowClipping: true
                    ])
                    AuroraLogger.engine.info("NSWorkspace: wallpaper set for display \(screen.displayID)")
                } catch {
                    AuroraLogger.logFailure("NSWorkspace failed for display \(screen.displayID): \(error.localizedDescription)")
                    // Fallback to AppleScript only if NSWorkspace fails
                    setWallpaperViaAppleScript(path: url.path)
                }
            }
        }

        AuroraLogger.engine.info("System wallpaper set for '\(wallpaperName, privacy: .public)'")
    }

    /// Sets the desktop wallpaper via AppleScript.
    private func setWallpaperViaAppleScript(path: String) {
        let script = """
        tell application "System Events"
            tell every desktop
                set picture to "\(path)"
            end tell
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                AuroraLogger.engine.info("AppleScript: wallpaper set successfully")
            } else {
                AuroraLogger.logFailure("AppleScript: exited with status \(process.terminationStatus)")
            }
        } catch {
            AuroraLogger.logFailure("AppleScript: failed to run — \(error.localizedDescription)")
        }
    }

    /// Restarts the Dock to force macOS to refresh its wallpaper cache.
    private func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]

        do {
            try process.run()
            process.waitUntilExit()
            AuroraLogger.engine.info("Dock restarted to refresh wallpaper cache")
        } catch {
            AuroraLogger.logFailure("Failed to restart Dock: \(error.localizedDescription)")
        }
    }

    /// Returns the file URL for saving a dynamic wallpaper.
    private func dynamicWallpaperPath(for wallpaperName: String, extension ext: String = "heic") -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let auroraDir = appSupport.appendingPathComponent("Aurora/DynamicWallpapers", isDirectory: true)

        try? FileManager.default.createDirectory(at: auroraDir, withIntermediateDirectories: true)

        let safeName = wallpaperName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return auroraDir.appendingPathComponent("\(safeName).\(ext)")
    }

    /// Returns the currently active wallpaper ID for a display.
    func currentWallpaperID(for displayID: CGDirectDisplayID) -> UUID? {
        return assignments[displayID]
    }

    // MARK: - Global Playback Control

    /// Pauses all wallpaper playback (user-initiated).
    func pauseAll() {
        isUserPaused = true
        isPaused = true
        for engine in engines.values {
            engine.pause()
        }
        AuroraLogger.engine.info("All wallpapers paused (user)")
    }

    /// Pauses all wallpaper playback (system-initiated, e.g., battery/fullscreen).
    /// Does not set isUserPaused so that system resumes work correctly.
    func systemPauseAll() {
        isPaused = true
        for engine in engines.values {
            engine.pause()
        }
        AuroraLogger.engine.info("All wallpapers paused (system)")
    }

    /// Resumes all wallpaper playback.
    /// If the user manually paused, system-initiated resumes are blocked.
    func resumeAll() {
        isUserPaused = false
        isPaused = false
        for engine in engines.values {
            engine.play()
        }
        AuroraLogger.engine.info("All wallpapers resumed")
    }

    /// Resumes all wallpaper playback (system-initiated).
    /// Respects user-initiated pause — if the user paused manually, this is a no-op.
    func systemResumeAll() {
        guard !isUserPaused else {
            AuroraLogger.engine.info("System resume blocked — user has manually paused")
            return
        }
        isPaused = false
        for engine in engines.values {
            engine.play()
        }
        AuroraLogger.engine.info("All wallpapers resumed (system)")
    }

    /// Toggles global playback (user-initiated).
    func toggleAll() {
        if isPaused {
            resumeAll()
        } else {
            pauseAll()
        }
    }

    // MARK: - Audio Control

    /// Mutes all wallpaper audio.
    func muteAll() {
        isMuted = true
        for engine in engines.values {
            engine.setMuted(true)
        }
        AuroraLogger.engine.info("All wallpapers muted")
    }

    /// Unmutes all wallpaper audio.
    func unmuteAll() {
        isMuted = false
        for engine in engines.values {
            engine.setMuted(false)
        }
        AuroraLogger.engine.info("All wallpapers unmuted")
    }

    /// Toggles mute state on all wallpapers.
    func toggleMuteAll() {
        if isMuted {
            unmuteAll()
        } else {
            muteAll()
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

    /// Validates all windows are correctly positioned and visible,
    /// AND validates that video engines are healthy (not stalled).
    private func performHealthCheck() {
        var allHealthy = true

        for (displayID, window) in windows {
            if !window.isHealthy {
                allHealthy = false
                AuroraLogger.logFailure("Unhealthy window detected for display \(displayID), attempting recovery")
                recoverWindow(for: displayID)
            }
        }

        // Check engine health: video player may have stalled after sleep/wake
        for (displayID, engine) in engines {
            if !isPaused && !engine.isEngineHealthy {
                allHealthy = false
                AuroraLogger.logFailure("Unhealthy engine detected for display \(displayID), rebuilding")
                recoverEngine(for: displayID)
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

    /// Recovers a stalled video engine for a display (e.g., after wake from sleep).
    /// Rebuilds the engine while keeping the window intact.
    private func recoverEngine(for displayID: CGDirectDisplayID) {
        guard let wallpaperID = assignments[displayID],
              let wallpaper = WallpaperLibrary.shared.wallpaper(withID: wallpaperID) else {
            AuroraLogger.logFailure("Cannot recover engine for display \(displayID): no wallpaper assigned")
            return
        }

        guard let window = windows[displayID],
              let contentView = window.contentView,
              let layer = contentView.layer else {
            AuroraLogger.logFailure("Cannot recover engine for display \(displayID): no window/layer")
            return
        }

        // Clean up the broken engine
        engines[displayID]?.cleanup()

        // Build a new engine
        let fileURL = URL(fileURLWithPath: wallpaper.filePath)
        let engine = VideoPlayerEngine(settings: wallpaper.playbackSettings)
        engines[displayID] = engine

        engine.loadVideo(url: fileURL, into: layer) { error in
            if let error = error {
                AuroraLogger.logFailure("Engine recovery failed for '\(wallpaper.name)': \(error.localizedDescription)")
                return
            }
            AuroraLogger.logRecovery("Engine recovered for '\(wallpaper.name)' on display \(displayID)")
        }

        // Apply current global mute state
        engine.setMuted(isMuted)
    }

    /// Recovers all engines (used after wake from sleep).
    /// Only rebuilds engines that are stalled/broken, not healthy ones.
    func recoverAllEngines() {
        AuroraLogger.logRecovery("Recovering all stalled engines after wake")

        for (displayID, engine) in engines {
            if !engine.isEngineHealthy {
                AuroraLogger.logRecovery("Engine stalled for display \(displayID), rebuilding")
                recoverEngine(for: displayID)
            } else {
                // Engine is healthy but may need a kick to resume playback
                if !isPaused && !engine.isPlaying {
                    engine.play()
                    AuroraLogger.logRecovery("Resumed stalled-but-healthy engine for display \(displayID)")
                }
            }
        }

        // If we have assignments but no engines (everything got cleaned up), rebuild
        for (displayID, wallpaperID) in assignments {
            if engines[displayID] == nil {
                if let wallpaper = WallpaperLibrary.shared.wallpaper(withID: wallpaperID) {
                    AuroraLogger.logRecovery("No engine for display \(displayID), rebuilding from assignment")
                    setWallpaper(wallpaper, for: displayID)
                }
            }
        }
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
        AuroraLogger.system.info("Screen configuration changed — \(NSScreen.screens.count) display(s)")

        // Remove windows for disconnected displays
        let connectedDisplayIDs = Set(NSScreen.screens.map { $0.displayID })
        let existingDisplayIDs = Set(windows.keys)
        let removedDisplayIDs = existingDisplayIDs.subtracting(connectedDisplayIDs)

        for displayID in removedDisplayIDs {
            AuroraLogger.system.info("Display \(displayID) disconnected, removing window")
            removeWindow(for: displayID)
        }

        // Process connected displays
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            if let existingWindow = windows[displayID] {
                // Display still connected — check if frame changed (resolution/position)
                let frameChanged = !existingWindow.frameMatchesScreen(screen)
                if frameChanged {
                    AuroraLogger.system.info("Display \(displayID) frame changed, recreating window")
                    let savedWallpaperID = assignments[displayID]

                    // Full teardown and recreate to avoid stale state
                    removeWindow(for: displayID)
                    createWindow(for: screen)

                    // Restore wallpaper assignment
                    if let wallpaperID = savedWallpaperID,
                       let wallpaper = WallpaperLibrary.shared.wallpaper(withID: wallpaperID) {
                        setWallpaper(wallpaper, for: displayID)
                    }
                } else {
                    // Frame matches — just ensure the window is correctly positioned
                    existingWindow.updateFrame()
                    if let engine = engines[displayID] {
                        engine.updateLayerFrame(CGRect(origin: .zero, size: screen.frame.size))
                    }
                }
            } else {
                // New display — create window
                AuroraLogger.system.info("New display \(displayID) detected, creating window")
                createWindow(for: screen)

                // Restore wallpaper if we had one assigned previously
                if let wallpaperID = assignments[displayID],
                   let wallpaper = WallpaperLibrary.shared.wallpaper(withID: wallpaperID) {
                    setWallpaper(wallpaper, for: displayID)
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
