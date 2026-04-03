// Aurora — PreviewPanel
// Floating NSPanel showing a scaled-down live video preview of a wallpaper
// before applying it. Includes display selector for multi-monitor setups.

import AppKit
import AVFoundation

/// Floating preview window for a wallpaper with Apply/Cancel controls.
final class PreviewPanel: NSWindowController {

    // MARK: - Properties

    private let wallpaper: Wallpaper
    private var videoEngine: VideoPlayerEngine?
    private var displayPopup: NSPopUpButton?

    // MARK: - Init

    init(wallpaper: Wallpaper) {
        self.wallpaper = wallpaper

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Preview — \(wallpaper.name)"
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        super.init(window: panel)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        videoEngine?.cleanup()
    }

    // MARK: - Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Video preview area
        let videoView = NSView(frame: NSRect(x: 20, y: 60, width: 600, height: 338))
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = NSColor.black.cgColor
        videoView.layer?.cornerRadius = 8
        videoView.layer?.masksToBounds = true
        contentView.addSubview(videoView)

        // Start video preview
        let engine = VideoPlayerEngine(settings: wallpaper.playbackSettings)
        self.videoEngine = engine
        let fileURL = URL(fileURLWithPath: wallpaper.filePath)

        engine.loadVideo(url: fileURL, into: videoView.layer!) { [weak engine] error in
            if error == nil {
                engine?.play()
            }
        }

        // Bottom control bar
        setupControls(in: contentView)
    }

    private func setupControls(in contentView: NSView) {
        // Display selector (for multi-monitor)
        let displayLabel = NSTextField(labelWithString: "Display:")
        displayLabel.frame = NSRect(x: 20, y: 20, width: 55, height: 24)
        displayLabel.font = .systemFont(ofSize: 13)
        contentView.addSubview(displayLabel)

        let popup = NSPopUpButton(frame: NSRect(x: 78, y: 18, width: 200, height: 28))
        for (index, screen) in NSScreen.screens.enumerated() {
            let displayID = screen.displayID
            let isMain = screen == NSScreen.main
            let title = "Display \(index + 1)\(isMain ? " (Main)" : "") — \(Int(screen.frame.width))×\(Int(screen.frame.height))"
            popup.addItem(withTitle: title)
            popup.lastItem?.tag = Int(displayID)
        }
        self.displayPopup = popup
        contentView.addSubview(popup)

        // Cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPreview))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: 460, y: 18, width: 75, height: 28)
        cancelButton.keyEquivalent = "\u{1b}"  // Escape key
        contentView.addSubview(cancelButton)

        // Apply button
        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyWallpaper))
        applyButton.bezelStyle = .rounded
        applyButton.frame = NSRect(x: 545, y: 18, width: 75, height: 28)
        applyButton.keyEquivalent = "\r"  // Return key
        applyButton.isHighlighted = true
        contentView.addSubview(applyButton)
    }

    // MARK: - Actions

    func showPreview() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func cancelPreview() {
        videoEngine?.cleanup()
        videoEngine = nil
        close()
    }

    @objc private func applyWallpaper() {
        videoEngine?.cleanup()
        videoEngine = nil

        // Get selected display
        let selectedDisplayID: CGDirectDisplayID
        if let popup = displayPopup, popup.indexOfSelectedItem >= 0 {
            selectedDisplayID = CGDirectDisplayID(popup.selectedItem?.tag ?? 0)
        } else {
            selectedDisplayID = NSScreen.main?.displayID ?? 0
        }

        // Apply the wallpaper
        WallpaperManager.shared.setWallpaper(wallpaper, for: selectedDisplayID)
        AuroraLogger.ui.info("Applied wallpaper '\(self.wallpaper.name, privacy: .public)' to display \(selectedDisplayID) from preview")

        close()
    }
}
