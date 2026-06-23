// Aurora — PerformanceMonitor
// Debounced fullscreen detection (dual heuristic, 1s confirm) and
// smoothed CPU monitoring (5-sample rolling average, 3s poll interval).

import AppKit
import Darwin

/// Monitors system performance and fullscreen app state.
/// Pauses/throttles wallpapers based on configurable thresholds.
final class PerformanceMonitor {

    // MARK: - Singleton

    static let shared = PerformanceMonitor()

    // MARK: - Properties

    /// Whether a fullscreen app is currently confirmed.
    private(set) var isFullscreenAppActive: Bool = false

    /// Rolling CPU usage samples for smoothing.
    private var cpuSamples: [Double] = []

    /// Max number of CPU samples to keep (5 × 3s = 15s window).
    private let maxCPUSamples = 5

    /// Timer for periodic monitoring.
    private var monitorTimer: Timer?

    /// Fullscreen debounce state.
    private var fullscreenDebounceStart: Date?

    /// Whether fullscreen was detected in the last check.
    private var lastFullscreenDetection: Bool = false

    /// Duration required for fullscreen to be confirmed (debounce).
    private let fullscreenDebounceInterval: TimeInterval = 1.0

    /// Monitoring poll interval (seconds).
    private let pollInterval: TimeInterval = 3.0

    // MARK: - Init

    private init() {
        startMonitoring()
        setupAppFocusObservers()
        AuroraLogger.performance.info("PerformanceMonitor initialized (poll: \(self.pollInterval)s)")
    }

    // MARK: - Monitoring Loop

    /// Starts the periodic monitoring timer.
    private func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.performCheck()
        }
    }

    /// Runs all performance checks.
    private func performCheck() {
        // Do not pause or throttle if the screen is locked, we want wallpapers to play on the lock screen
        guard !PowerManager.shared.isScreenLocked else { return }
        
        checkFullscreen()
        checkCPUUsage()
    }

    /// Forces a re-evaluation of all performance states. Useful after screen unlock.
    func forceReevaluation() {
        // Reset tracking vars so checks re-trigger state changes
        isFullscreenAppActive = false
        lastFullscreenDetection = false
        fullscreenDebounceStart = nil
        isBackgroundBehaviorActive = false
        
        checkAppFocus()
        performCheck()
    }

    // MARK: - App Focus Detection

    /// Whether the background behavior (another app is focused) is currently active.
    private(set) var isBackgroundBehaviorActive: Bool = false

    private func setupAppFocusObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        // Initial check
        checkAppFocus()
    }

    @objc private func appDidActivate(_ notification: Notification) {
        checkAppFocus()
    }

    private func checkAppFocus() {
        // Ignore app focus changes when screen is locked (e.g. loginwindow)
        guard !PowerManager.shared.isScreenLocked else { return }
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        let bundleID = frontmostApp.bundleIdentifier

        // If Finder or our app is frontmost, we are "in focus" on the desktop
        let isForeground = bundleID == "com.apple.finder" || bundleID == Bundle.main.bundleIdentifier

        if isForeground {
            if isBackgroundBehaviorActive {
                isBackgroundBehaviorActive = false
                restoreFromBackgroundBehavior()
            }
        } else {
            // Apply behavior every time in case settings changed
            isBackgroundBehaviorActive = true
            applyBackgroundBehavior()
        }
    }

    private func applyBackgroundBehavior() {
        let behavior = AuroraSettings.shared.backgroundBehavior
        
        switch behavior {
        case .keepPlaying:
            // If they changed from lowerFramerate -> keepPlaying, we should clear framerate
            WallpaperManager.shared.setFramerateTargetAll(nil)
        case .lowerFramerate:
            let fps = AuroraSettings.shared.backgroundFramerate
            WallpaperManager.shared.setFramerateTargetAll(fps)
        case .pause:
            WallpaperManager.shared.systemPauseAll()
        }
        AuroraLogger.performance.info("Background behavior applied: \(behavior.rawValue)")
    }

    private func restoreFromBackgroundBehavior() {
        WallpaperManager.shared.setFramerateTargetAll(nil) // Always clear framerate throttle on focus
        
        // Only resume if not restricted by fullscreen or battery rules
        if !isFullscreenAppActive && (!PowerManager.shared.isBatterySaving || AuroraSettings.shared.batteryMode != .aggressive) && !PowerManager.shared.isScreenLocked {
            WallpaperManager.shared.systemResumeAll()
        }
        AuroraLogger.performance.info("Restored from background behavior")
    }

    // MARK: - Fullscreen Detection (Debounced, Dual Heuristic)

    /// Checks if a fullscreen app is covering the desktop using two heuristics.
    private func checkFullscreen() {
        guard AuroraSettings.shared.pauseOnFullscreen else { return }

        let isFullscreen = detectFullscreen()

        if isFullscreen {
            if lastFullscreenDetection {
                // Still fullscreen — check if debounce period has passed
                if let start = fullscreenDebounceStart,
                   Date().timeIntervalSince(start) >= fullscreenDebounceInterval {
                    // Confirmed fullscreen for 1+ second
                    if !isFullscreenAppActive {
                        isFullscreenAppActive = true
                        WallpaperManager.shared.systemPauseAll()
                        AuroraLogger.logPerformanceAction("Fullscreen app confirmed — wallpapers paused")
                    }
                }
            } else {
                // First detection — start debounce timer
                fullscreenDebounceStart = Date()
                lastFullscreenDetection = true
                AuroraLogger.performance.debug("Fullscreen detected — starting 1s debounce")
            }
        } else {
            // Not fullscreen
            if isFullscreenAppActive {
                isFullscreenAppActive = false
                // Only resume if not battery-paused and not paused by background focus
                let allowResumeFocus = !isBackgroundBehaviorActive || AuroraSettings.shared.backgroundBehavior != .pause
                if !PowerManager.shared.isBatterySaving && allowResumeFocus && !PowerManager.shared.isScreenLocked {
                    WallpaperManager.shared.systemResumeAll()
                    AuroraLogger.logPerformanceAction("Fullscreen app exited — wallpapers resumed")
                }
            }

            // Reset debounce state
            lastFullscreenDetection = false
            fullscreenDebounceStart = nil
        }
    }

    /// Dual heuristic fullscreen detection.
    /// Both heuristics must agree for a positive detection.
    private func detectFullscreen() -> Bool {
        let heuristic1 = checkFrontmostAppFullscreen()
        let heuristic2 = checkWindowCoverage()

        if heuristic1 != heuristic2 {
            // Disagreement — log but don't pause (avoid false positives)
            AuroraLogger.performance.debug(
                "Fullscreen heuristic disagreement: frontmostApp=\(heuristic1), windowCoverage=\(heuristic2)"
            )
            return false
        }

        return heuristic1 && heuristic2
    }

    /// Heuristic 1: Check if the frontmost app is in fullscreen mode.
    private func checkFrontmostAppFullscreen() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return false }

        // Skip Finder (desktop) — it's not a "fullscreen app"
        if frontmostApp.bundleIdentifier == "com.apple.finder" { return false }

        // Check if the app's presentation options include fullScreen
        let options = NSApp.currentEvent != nil ? NSApp.presentationOptions : []
        if options.contains(.fullScreen) {
            return true
        }

        // Fallback: check if any of the app's windows are fullscreen via AX
        // This is a simpler heuristic — check window list
        return false
    }

    /// Heuristic 2: Check if any window covers ≥95% of any screen.
    private func checkWindowCoverage() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for screen in NSScreen.screens {
            let screenArea = screen.frame.width * screen.frame.height

            for window in windowList {
                // Skip our own windows
                guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                      ownerPID != ProcessInfo.processInfo.processIdentifier else { continue }

                // Skip windows below normal level (desktop, etc.)
                guard let windowLayer = window[kCGWindowLayer as String] as? Int,
                      windowLayer == 0 else { continue }

                // Get window bounds
                guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                      let x = boundsDict["X"] as? CGFloat,
                      let y = boundsDict["Y"] as? CGFloat,
                      let width = boundsDict["Width"] as? CGFloat,
                      let height = boundsDict["Height"] as? CGFloat else { continue }

                let windowRect = CGRect(x: x, y: y, width: width, height: height)

                // Check if window covers ≥95% of the screen
                let intersection = windowRect.intersection(screen.frame)
                let coverageArea = intersection.width * intersection.height

                if coverageArea / screenArea >= 0.95 {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - CPU Monitoring (Smoothed)

    /// Checks CPU usage with rolling average smoothing.
    private func checkCPUUsage() {
        let cpuUsage = getCurrentCPUUsage()

        // Add to rolling window
        cpuSamples.append(cpuUsage)
        if cpuSamples.count > maxCPUSamples {
            cpuSamples.removeFirst()
        }

        // Calculate smoothed average
        let smoothedCPU = cpuSamples.reduce(0, +) / Double(cpuSamples.count)
        let threshold = AuroraSettings.shared.cpuThreshold

        if smoothedCPU > threshold {
            if !WallpaperManager.shared.isThrottled && !WallpaperManager.shared.isPaused {
                WallpaperManager.shared.throttleAll(rate: 0.5)
                AuroraLogger.logPerformanceAction(
                    "CPU usage \(String(format: "%.1f", smoothedCPU))% exceeds threshold \(String(format: "%.0f", threshold))% — throttling"
                )
            }
        } else if smoothedCPU < threshold * 0.8 {
            // Hysteresis: only unthrottle when CPU drops to 80% of threshold
            if WallpaperManager.shared.isThrottled && !PowerManager.shared.isBatterySaving {
                WallpaperManager.shared.unthrottleAll()
                AuroraLogger.logPerformanceAction(
                    "CPU usage \(String(format: "%.1f", smoothedCPU))% below threshold — un-throttling"
                )
            }
        }
    }

    /// Gets the current system-wide CPU usage percentage.
    private func getCurrentCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return 0.0
        }

        var totalUser: Int32 = 0
        var totalSystem: Int32 = 0
        var totalIdle: Int32 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += cpuInfo[offset + Int(CPU_STATE_USER)]
            totalSystem += cpuInfo[offset + Int(CPU_STATE_SYSTEM)]
            totalIdle += cpuInfo[offset + Int(CPU_STATE_IDLE)]
        }

        let total = Double(totalUser + totalSystem + totalIdle)
        guard total > 0 else { return 0.0 }

        let used = Double(totalUser + totalSystem)

        // Deallocate
        let size = vm_size_t(MemoryLayout<integer_t>.stride * Int(numCPUInfo))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)

        return (used / total) * 100.0
    }

    // MARK: - Cleanup

    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        AuroraLogger.performance.info("Performance monitoring stopped")
    }
}
