// Aurora — WallpaperWindow
// Borderless NSWindow positioned at the desktop level, behind Finder icons.
// Includes fade-in animation to prevent visual flicker on creation/recreation.

import AppKit
import QuartzCore

/// A borderless, click-through window that sits behind Finder's desktop icons.
///
/// Window stack (top to bottom):
///   Normal windows → Finder desktop icons → ★ WallpaperWindow ★ → macOS desktop bg
///
final class WallpaperWindow: NSWindow {

    // MARK: - Properties

    /// Unique display identifier for this window's screen.
    /// We store the ID (immutable) rather than the NSScreen reference
    /// because NSScreen objects change when displays are reconnected.
    let displayID: CGDirectDisplayID

    /// Returns the live NSScreen for this window's display, or nil if disconnected.
    var currentScreen: NSScreen? {
        return NSScreen.screens.first(where: { $0.displayID == displayID })
    }

    // MARK: - Init

    /// Creates a wallpaper window for the given screen.
    /// - Parameter screen: The NSScreen to cover with this wallpaper window.
    init(for screen: NSScreen) {
        self.displayID = screen.displayID

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        configureWindow()
        AuroraLogger.logWindowState("Created wallpaper window for display \(displayID) at \(screen.frame)")
    }

    // MARK: - Configuration

    private func configureWindow() {
        // Place window at the desktop level (behind Finder icons, on top of desktop background)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // Behavior: appear on all Spaces & desktops, stationary in Mission Control, hidden from Cmd+Tab
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        // Click-through: all mouse events pass to desktop/Finder
        ignoresMouseEvents = true

        // No shadow, no opacity initially (for fade-in)
        hasShadow = false
        alphaValue = 0.0

        // Make the window background transparent
        backgroundColor = .clear
        isOpaque = false

        // Prevent the window from being released when closed
        isReleasedWhenClosed = false

        // Show on lock screen / login window
        canBecomeVisibleWithoutLogin = true

        // Prevent the window server from hiding this window during
        // screen sharing or display transitions (helps lock screen persistence)
        sharingType = .none

        // Window cannot become key or main — it's just a display surface
        // (handled by override below)
    }

    // MARK: - Key/Main Prevention

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Display

    /// Shows the window with a fade-in animation to prevent flicker.
    /// - Parameter duration: Fade-in duration in seconds. Default: 0.3s.
    func showWithFadeIn(duration: TimeInterval = 0.3) {
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 1.0
        }

        AuroraLogger.logWindowState("Showing wallpaper window for display \(displayID) with fade-in")
    }

    /// Hides the window with a fade-out animation.
    /// - Parameter duration: Fade-out duration in seconds. Default: 0.2s.
    func hideWithFadeOut(duration: TimeInterval = 0.2, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            completion?()
        })

        AuroraLogger.logWindowState("Hiding wallpaper window for display \(displayID) with fade-out")
    }

    /// Updates the window frame to match the screen's current frame.
    /// Called when screen resolution or position changes.
    func updateFrame() {
        guard let screen = currentScreen else {
            AuroraLogger.logFailure("Cannot update frame for display \(displayID): screen not found")
            return
        }
        setFrame(screen.frame, display: true)
        // Also update the content view frame to match
        contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        AuroraLogger.logWindowState("Updated frame for display \(displayID) to \(screen.frame)")
    }

    // MARK: - Validation

    /// Checks if this window is still correctly positioned in the window stack.
    /// Returns false if the window has been detached or moved out of the correct level.
    var isHealthy: Bool {
        guard let screen = currentScreen else {
            // Screen no longer connected — not healthy
            AuroraLogger.logFailure("Health check failed for display \(displayID): screen disconnected")
            return false
        }

        let correctLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        let isVisible = isVisible && alphaValue > 0
        let isCorrectLevel = level == correctLevel

        // Use a tolerance for frame comparison to handle rounding during display transitions
        let isCorrectFrame = frameMatchesScreen(screen)

        if !isVisible || !isCorrectLevel || !isCorrectFrame {
            AuroraLogger.logFailure(
                "Health check failed for display \(displayID): " +
                "visible=\(isVisible), correctLevel=\(isCorrectLevel), correctFrame=\(isCorrectFrame)"
            )
            return false
        }
        return true
    }

    /// Compares the window frame to the live screen frame with a small tolerance
    /// to avoid false negatives during display transition rounding.
    func frameMatchesScreen(_ screen: NSScreen) -> Bool {
        let screenFrame = screen.frame
        let tolerance: CGFloat = 2.0
        return abs(frame.origin.x - screenFrame.origin.x) <= tolerance &&
               abs(frame.origin.y - screenFrame.origin.y) <= tolerance &&
               abs(frame.width - screenFrame.width) <= tolerance &&
               abs(frame.height - screenFrame.height) <= tolerance
    }

    // MARK: - Cleanup

    /// Properly cleans up the window before deallocation.
    func cleanup() {
        AuroraLogger.logWindowState("Cleaning up wallpaper window for display \(displayID)")
        contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        orderOut(nil)
    }
}

// MARK: - NSScreen Extension

extension NSScreen {
    /// Returns the CGDirectDisplayID for this screen.
    var displayID: CGDirectDisplayID {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return screenNumber.uint32Value
    }
}
