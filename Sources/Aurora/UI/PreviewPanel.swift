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
    private var displaysButton: NSButton?
    private var displaysPopover: NSPopover?
    private var selectedDisplayIDs: Set<CGDirectDisplayID> = []
    private var targetPopup: NSPopUpButton?

    // MARK: - Init

    init(wallpaper: Wallpaper) {
        self.wallpaper = wallpaper
        self.selectedDisplayIDs = Set(NSScreen.screens.map { $0.displayID })

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 450),
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
        let videoView = NSView(frame: NSRect(x: 20, y: 60, width: 760, height: 370))
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
        let displayLabel = NSTextField(labelWithString: "Displays:")
        displayLabel.frame = NSRect(x: 20, y: 20, width: 60, height: 24)
        displayLabel.font = .systemFont(ofSize: 13)
        contentView.addSubview(displayLabel)

        let dButton = NSButton(title: "All Screens", target: self, action: #selector(showDisplaysPopover))
        dButton.frame = NSRect(x: 82, y: 18, width: 150, height: 28)
        dButton.bezelStyle = .rounded
        self.displaysButton = dButton
        contentView.addSubview(dButton)
        updateDisplaysButtonTitle()

        // Wallpaper target selector (Both / Desktop Only / Lock Screen Only)
        let targetLabel = NSTextField(labelWithString: "Apply to:")
        targetLabel.frame = NSRect(x: 350, y: 20, width: 55, height: 24)
        targetLabel.font = .systemFont(ofSize: 13)
        contentView.addSubview(targetLabel)

        let tPopup = NSPopUpButton(frame: NSRect(x: 408, y: 18, width: 140, height: 28))
        for target in WallpaperTarget.allCases {
            tPopup.addItem(withTitle: target.description)
        }
        tPopup.selectItem(at: 0)  // Default: Both
        self.targetPopup = tPopup
        contentView.addSubview(tPopup)

        // Cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPreview))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: 610, y: 18, width: 80, height: 28)
        cancelButton.keyEquivalent = "\u{1b}"  // Escape key
        contentView.addSubview(cancelButton)

        // Apply button
        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyWallpaper))
        applyButton.bezelStyle = .rounded
        applyButton.frame = NSRect(x: 700, y: 18, width: 80, height: 28)
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

        // Get selected wallpaper target
        let target: WallpaperTarget
        let targets = WallpaperTarget.allCases
        if let tPopup = targetPopup, tPopup.indexOfSelectedItem >= 0 && tPopup.indexOfSelectedItem < targets.count {
            target = targets[tPopup.indexOfSelectedItem]
        } else {
            target = .both
        }

        // Apply the wallpaper to all selected displays
        if selectedDisplayIDs.isEmpty {
            AuroraLogger.ui.warning("Cannot apply preview wallpaper: no displays selected")
            close()
            return
        }

        for displayID in selectedDisplayIDs {
            WallpaperManager.shared.setWallpaper(wallpaper, for: displayID, target: target)
        }
        
        AuroraLogger.ui.info("Applied wallpaper '\(self.wallpaper.name, privacy: .public)' to \(self.selectedDisplayIDs.count) display(s) with target \(target.description) from preview")

        close()
    }

    // MARK: - Display Selection

    @objc private func showDisplaysPopover() {
        if displaysPopover == nil {
            let popover = NSPopover()
            let vc = DisplaySelectorViewController(selectedDisplayIDs: selectedDisplayIDs)
            vc.delegate = self
            popover.contentViewController = vc
            popover.behavior = .transient
            self.displaysPopover = popover
        }
        
        guard let popover = displaysPopover, let button = displaysButton else { return }
        
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateDisplaysButtonTitle() {
        let totalScreens = NSScreen.screens.count
        if selectedDisplayIDs.count == totalScreens && totalScreens > 0 {
            displaysButton?.title = "All Screens"
        } else if selectedDisplayIDs.isEmpty {
            displaysButton?.title = "None"
        } else {
            displaysButton?.title = "\(selectedDisplayIDs.count) Selected"
        }
    }
}

// MARK: - DisplaySelectorDelegate

extension PreviewPanel: DisplaySelectorDelegate {
    func displaySelectionDidChange(selectedDisplayIDs: Set<CGDirectDisplayID>) {
        self.selectedDisplayIDs = selectedDisplayIDs
        updateDisplaysButtonTitle()
    }
}
