// Aurora — DisplayManager
// Multi-monitor detection and tracking with resolution, scaling, and refresh rate awareness.
// Uses a triple-layer detection strategy for reliable external display hotplug:
//   1. CGDisplayRegisterReconfigurationCallback (CoreGraphics-level, most reliable)
//   2. NSApplication.didChangeScreenParametersNotification (AppKit-level)
//   3. Polling safety net (catches edge cases after wake/sleep)

import AppKit

/// Monitors connected displays and notifies WallpaperManager of changes.
/// Tracks per-display: resolution, backingScaleFactor, refresh rate.
final class DisplayManager {

    // MARK: - Singleton

    static let shared = DisplayManager()

    // MARK: - Properties

    /// Info about each tracked display.
    struct DisplayInfo {
        let displayID: CGDirectDisplayID
        let frame: NSRect
        let backingScaleFactor: CGFloat
        let refreshRate: Double
        let isBuiltIn: Bool

        var description: String {
            let res = "\(Int(frame.width))x\(Int(frame.height))"
            return "Display \(displayID): \(res) @\(backingScaleFactor)x, \(Int(refreshRate))Hz\(isBuiltIn ? " (built-in)" : "")"
        }
    }

    /// Currently tracked displays.
    private(set) var displays: [CGDirectDisplayID: DisplayInfo] = [:]

    /// Debounce work item for screen change notifications.
    /// macOS fires multiple rapid notifications during display plug/unplug;
    /// debouncing ensures we only process the final stable configuration.
    private var screenChangeDebounce: DispatchWorkItem?

    /// Last known screen count for the polling safety net.
    private var lastKnownScreenCount: Int = 0

    /// Polling timer for the safety net.
    private var pollingTimer: Timer?

    /// Tracks whether the CG callback has been registered (for cleanup).
    private var cgCallbackRegistered: Bool = false

    // MARK: - Init

    private init() {
        lastKnownScreenCount = NSScreen.screens.count
        refreshDisplayList()
        setupCGDisplayCallback()
        setupNotificationObserver()
        startPollingTimer()
        AuroraLogger.system.info("DisplayManager initialized with \(self.displays.count) display(s)")
    }

    deinit {
        cleanup()
    }

    // MARK: - Detection Layer 1: CoreGraphics Callback (Most Reliable)

    /// Registers a CoreGraphics display reconfiguration callback.
    /// This fires directly from the display subsystem, regardless of app activation policy.
    /// It is the most reliable mechanism for detecting external display hotplug events.
    private func setupCGDisplayCallback() {
        let result = CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())

        if result == .success {
            cgCallbackRegistered = true
            AuroraLogger.system.info("CoreGraphics display reconfiguration callback registered")
        } else {
            AuroraLogger.logFailure("Failed to register CoreGraphics display callback (error: \(result.rawValue))")
        }
    }

    // MARK: - Detection Layer 2: NSNotification (AppKit-level)

    /// Registers for screen configuration change notifications.
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        AuroraLogger.system.info("NSApplication screen parameters observer registered")
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        AuroraLogger.system.info("Screen change detected via NSNotification — debouncing")
        scheduleScreenChangeProcessing(source: "NSNotification")
    }

    // MARK: - Detection Layer 3: Polling Safety Net

    /// Starts a periodic timer that checks the screen count as a last-resort fallback.
    /// Catches edge cases where both callback mechanisms fail (e.g., after wake with a new display).
    private func startPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollForScreenChanges()
        }
        AuroraLogger.system.info("Display polling safety net started (interval: 5s)")
    }

    /// Checks if the number of connected screens has changed since last poll.
    private func pollForScreenChanges() {
        let currentCount = NSScreen.screens.count
        if currentCount != lastKnownScreenCount {
            AuroraLogger.system.info("Screen change detected via polling (was \(self.lastKnownScreenCount), now \(currentCount)) — processing")
            lastKnownScreenCount = currentCount
            scheduleScreenChangeProcessing(source: "Polling")
        }
    }

    // MARK: - Unified Processing

    /// Schedules the screen change processing with debouncing.
    /// Multiple detection layers may fire simultaneously; debouncing coalesces them.
    fileprivate func scheduleScreenChangeProcessing(source: String) {
        // Cancel any pending debounce
        screenChangeDebounce?.cancel()

        // Schedule the actual processing after 0.5s to coalesce rapid notifications
        let workItem = DispatchWorkItem { [weak self] in
            self?.processScreenChange(triggeredBy: source)
        }
        screenChangeDebounce = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// Processes screen change after debounce period has elapsed.
    private func processScreenChange(triggeredBy source: String) {
        AuroraLogger.system.info("Processing debounced screen change (triggered by: \(source, privacy: .public))")

        let previousDisplayIDs = Set(displays.keys)
        refreshDisplayList()
        let currentDisplayIDs = Set(displays.keys)

        // Update last known count for the polling safety net
        lastKnownScreenCount = NSScreen.screens.count

        // Log changes
        let added = currentDisplayIDs.subtracting(previousDisplayIDs)
        let removed = previousDisplayIDs.subtracting(currentDisplayIDs)

        for id in added {
            if let info = displays[id] {
                AuroraLogger.system.info("Display connected: \(info.description, privacy: .public)")
            }
        }
        for id in removed {
            AuroraLogger.system.info("Display disconnected: \(id)")
        }

        if added.isEmpty && removed.isEmpty {
            AuroraLogger.system.debug("Screen parameters changed but display set unchanged (resolution/position update)")
        }

        // Notify WallpaperManager
        WallpaperManager.shared.handleScreenChange()
    }

    // MARK: - Display Discovery

    /// Refreshes the list of connected displays.
    func refreshDisplayList() {
        displays.removeAll()

        for screen in NSScreen.screens {
            let displayID = screen.displayID
            let info = DisplayInfo(
                displayID: displayID,
                frame: screen.frame,
                backingScaleFactor: screen.backingScaleFactor,
                refreshRate: refreshRate(for: displayID),
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
            )
            displays[displayID] = info
            AuroraLogger.system.debug("Tracked: \(info.description, privacy: .public)")
        }
    }

    /// Gets the refresh rate for a display.
    private func refreshRate(for displayID: CGDirectDisplayID) -> Double {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return 60.0 }
        let rate = mode.refreshRate
        return rate > 0 ? rate : 60.0  // Default to 60Hz if unknown
    }

    /// Returns the DisplayInfo for a given display ID.
    func info(for displayID: CGDirectDisplayID) -> DisplayInfo? {
        return displays[displayID]
    }

    /// Returns whether the given display is the built-in (laptop) display.
    func isBuiltIn(_ displayID: CGDirectDisplayID) -> Bool {
        return displays[displayID]?.isBuiltIn ?? false
    }

    // MARK: - Cleanup

    /// Removes all observers and callbacks. Called on deinit.
    func cleanup() {
        pollingTimer?.invalidate()
        pollingTimer = nil

        if cgCallbackRegistered {
            CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
            cgCallbackRegistered = false
            AuroraLogger.system.info("CoreGraphics display callback removed")
        }

        NotificationCenter.default.removeObserver(self)
        AuroraLogger.system.info("DisplayManager cleaned up")
    }
}

// MARK: - CoreGraphics Callback (Global Function)

/// Global C-function-pointer callback required by CGDisplayRegisterReconfigurationCallback.
/// Swift closures cannot be used here — only global/static functions with @convention(c) are allowed.
/// The `userInfo` pointer carries the DisplayManager instance via Unmanaged.
private func displayReconfigurationCallback(
    _ displayID: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    // Only process when the reconfiguration is complete (not the "begin" phase)
    guard flags.contains(.beginConfigurationFlag) == false else { return }

    // Check for meaningful changes: display added, removed, or enabled/disabled
    let isRelevant = flags.contains(.addFlag) ||
                     flags.contains(.removeFlag) ||
                     flags.contains(.enabledFlag) ||
                     flags.contains(.disabledFlag) ||
                     flags.contains(.desktopShapeChangedFlag)

    guard isRelevant else { return }

    // Recover the DisplayManager instance from the raw pointer
    guard let userInfo = userInfo else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(userInfo).takeUnretainedValue()

    // Must dispatch to main thread — CG callback fires on an arbitrary thread
    DispatchQueue.main.async {
        var reasons: [String] = []
        if flags.contains(.addFlag) { reasons.append("added") }
        if flags.contains(.removeFlag) { reasons.append("removed") }
        if flags.contains(.enabledFlag) { reasons.append("enabled") }
        if flags.contains(.disabledFlag) { reasons.append("disabled") }
        if flags.contains(.desktopShapeChangedFlag) { reasons.append("shape-changed") }

        AuroraLogger.system.info("Screen change detected via CGDisplay callback (display \(displayID): \(reasons.joined(separator: ", "), privacy: .public))")
        manager.scheduleScreenChangeProcessing(source: "CGDisplayCallback")
    }
}
