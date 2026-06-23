// Aurora — DisplayManager
// Multi-monitor detection and tracking with resolution, scaling, and refresh rate awareness.

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

    // MARK: - Init

    private init() {
        refreshDisplayList()
        setupObserver()
        AuroraLogger.system.info("DisplayManager initialized with \(self.displays.count) display(s)")
    }

    // MARK: - Observation

    /// Registers for screen configuration change notifications.
    private func setupObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        AuroraLogger.system.info("Screen parameters changed notification received — debouncing")

        // Cancel any pending debounce
        screenChangeDebounce?.cancel()

        // Schedule the actual processing after 0.5s to coalesce rapid notifications
        let workItem = DispatchWorkItem { [weak self] in
            self?.processScreenChange()
        }
        screenChangeDebounce = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// Processes screen change after debounce period has elapsed.
    private func processScreenChange() {
        AuroraLogger.system.info("Processing debounced screen change")

        let previousDisplayIDs = Set(displays.keys)
        refreshDisplayList()
        let currentDisplayIDs = Set(displays.keys)

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
}
