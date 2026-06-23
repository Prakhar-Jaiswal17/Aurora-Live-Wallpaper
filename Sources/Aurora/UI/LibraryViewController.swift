// Aurora — LibraryViewController
// NSCollectionView grid of wallpaper thumbnails with search, drag-drop import,
// an "Apply" button to set the selected wallpaper, and context menu.
// Uses Auto Layout to prevent overlap and clipping.

import AppKit
import AVFoundation

/// Displays the wallpaper library as a grid of thumbnails.
final class LibraryViewController: NSViewController {

    // MARK: - Properties

    private var topBar: NSView!
    private var bottomBar: NSView!
    private var scrollView: NSScrollView!
    private var collectionView: NSCollectionView!
    private var searchField: NSSearchField!
    private var importButton: NSButton!
    private var emptyStateView: NSView!
    private var applyButton: NSButton!
    private var setStaticButton: NSButton!
    private var previewButton: NSButton!
    private var deleteButton: NSButton!
    private var targetPopup: NSPopUpButton!
    private var displaysButton: NSButton!
    private var displaysPopover: NSPopover?
    private var selectedDisplayIDs: Set<CGDirectDisplayID> = []


    /// Retained reference to the preview panel (prevents ARC deallocation).
    private var previewPanel: PreviewPanel?

    /// Currently displayed wallpapers (may be filtered by search).
    private var displayedWallpapers: [Wallpaper] = []

    /// Currently selected wallpaper index.
    private var selectedIndex: Int? {
        didSet { updateButtonStates() }
    }

    // MARK: - Collection View Item Identifier

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("WallpaperCell")

    // MARK: - View Lifecycle

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 620))
        view.translatesAutoresizingMaskIntoConstraints = false

        // Initialize selected displays to all connected screens by default
        selectedDisplayIDs = Set(NSScreen.screens.map { $0.displayID })

        setupTopBar()
        setupCollectionView()
        setupBottomBar()
        setupEmptyState()
        setupDragDrop()
        setupLayoutConstraints()
        reloadData()
        updateDisplaysButtonTitle()
    }

    // MARK: - Setup

    private func setupTopBar() {
        // Container for search field and import button
        topBar = NSView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.wantsLayer = true
        view.addSubview(topBar)

        // Search field
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search wallpapers..."
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        topBar.addSubview(searchField)

        // Import button
        importButton = NSButton(title: "＋ Import...", target: self, action: #selector(importTapped))
        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.bezelStyle = .rounded
        importButton.controlSize = .regular
        importButton.contentTintColor = .controlAccentColor
        topBar.addSubview(importButton)

        // Top bar internal constraints
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            searchField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: importButton.leadingAnchor, constant: -12),

            importButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            importButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            importButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])
    }

    private func setupCollectionView() {
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = NSSize(width: 195, height: 155)
        flowLayout.minimumInteritemSpacing = 14
        flowLayout.minimumLineSpacing = 14
        flowLayout.sectionInset = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(WallpaperCollectionViewItem.self, forItemWithIdentifier: Self.itemIdentifier)
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        view.addSubview(scrollView)
    }

    private func setupBottomBar() {
        // Bottom action bar with Apply (live wallpaper), Set as Wallpaper (static), Preview, Delete
        bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        view.addSubview(bottomBar)

        // Separator line
        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        bottomBar.addSubview(separator)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Delete button (left side)
        deleteButton = NSButton(title: "", target: self, action: #selector(deleteSelectedWallpaper))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .rounded
        deleteButton.isEnabled = false
        deleteButton.contentTintColor = .systemRed
        deleteButton.toolTip = "Delete selected wallpaper"
        if let deleteImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") {
            deleteButton.image = deleteImage
            deleteButton.imagePosition = .imageOnly
        }
        bottomBar.addSubview(deleteButton)


        // Preview button
        previewButton = NSButton(title: "", target: self, action: #selector(previewSelectedWallpaper))
        previewButton.translatesAutoresizingMaskIntoConstraints = false
        previewButton.bezelStyle = .rounded
        previewButton.isEnabled = false
        previewButton.toolTip = "Preview wallpaper"
        if let previewImage = NSImage(systemSymbolName: "eye", accessibilityDescription: "Preview") {
            previewButton.image = previewImage
            previewButton.imagePosition = .imageOnly
        }
        bottomBar.addSubview(previewButton)

        // Set as Wallpaper button — extracts a frame and sets it as the macOS system wallpaper
        setStaticButton = NSButton(title: "Set as Wallpaper", target: self, action: #selector(setAsStaticWallpaper))
        setStaticButton.translatesAutoresizingMaskIntoConstraints = false
        setStaticButton.bezelStyle = .rounded
        setStaticButton.isEnabled = false
        setStaticButton.toolTip = "Set as static desktop wallpaper"
        if let photoImage = NSImage(systemSymbolName: "photo", accessibilityDescription: "Set as Wallpaper") {
            setStaticButton.image = photoImage
            setStaticButton.imagePosition = .imageLeading
        }
        bottomBar.addSubview(setStaticButton)

        // Wallpaper target popup — choose where to apply (Both / Desktop / Lock Screen)
        targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        targetPopup.translatesAutoresizingMaskIntoConstraints = false
        for target in WallpaperTarget.allCases {
            targetPopup.addItem(withTitle: target.description)
        }
        targetPopup.selectItem(at: 0)  // Default: Both (Desktop & Lock Screen)
        targetPopup.isEnabled = false
        targetPopup.controlSize = .regular
        bottomBar.addSubview(targetPopup)

        // Displays button
        displaysButton = NSButton(title: "Displays: All", target: self, action: #selector(showDisplaysPopover))
        displaysButton.translatesAutoresizingMaskIntoConstraints = false
        displaysButton.bezelStyle = .rounded
        displaysButton.isEnabled = false
        bottomBar.addSubview(displaysButton)

        // Apply button (primary action) — sets wallpaper with selected target
        applyButton = NSButton(title: "✦ Apply", target: self, action: #selector(applyLiveWallpaper))
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"  // Return key
        applyButton.isEnabled = false
        applyButton.contentTintColor = .controlAccentColor
        bottomBar.addSubview(applyButton)

        NSLayoutConstraint.activate([
            // Left group
            deleteButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            deleteButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            previewButton.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 8),
            previewButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            setStaticButton.leadingAnchor.constraint(equalTo: previewButton.trailingAnchor, constant: 8),
            setStaticButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            // Right group
            applyButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            applyButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            targetPopup.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),
            targetPopup.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            targetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),

            displaysButton.trailingAnchor.constraint(equalTo: targetPopup.leadingAnchor, constant: -8),
            displaysButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            // Prevent overlap between left and right groups
            displaysButton.leadingAnchor.constraint(greaterThanOrEqualTo: setStaticButton.trailingAnchor, constant: 16)
        ])
    }

    private func setupEmptyState() {
        emptyStateView = NSView()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        view.addSubview(emptyStateView)

        // Icon
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let icon = NSImage(systemSymbolName: "film.stack", accessibilityDescription: "No wallpapers") {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .ultraLight)
            iconView.image = icon.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .tertiaryLabelColor
        emptyStateView.addSubview(iconView)

        // Title
        let titleLabel = NSTextField(labelWithString: "No wallpapers yet")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        emptyStateView.addSubview(titleLabel)

        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Click \"＋ Import...\" or drag video files here to get started.")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.alignment = .center
        emptyStateView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyStateView.widthAnchor.constraint(equalToConstant: 400),
            emptyStateView.heightAnchor.constraint(equalToConstant: 140),

            iconView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            titleLabel.widthAnchor.constraint(equalTo: emptyStateView.widthAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: emptyStateView.widthAnchor),
        ])
    }

    private func setupDragDrop() {
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
    }

    private func setupLayoutConstraints() {

        NSLayoutConstraint.activate([
            // Top bar: pinned to top
            topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 40),

            // Scroll view: fills the space between top bar and bottom bar
            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            // Bottom bar: pinned to bottom
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    // MARK: - Data

    func reloadData() {
        let query = searchField?.stringValue ?? ""
        displayedWallpapers = WallpaperLibrary.shared.search(query: query)
        collectionView?.reloadData()
        emptyStateView?.isHidden = !displayedWallpapers.isEmpty
        selectedIndex = nil
    }

    // MARK: - Button State

    private func updateButtonStates() {
        let hasSelection = selectedIndex != nil
        applyButton?.isEnabled = hasSelection
        setStaticButton?.isEnabled = hasSelection
        previewButton?.isEnabled = hasSelection
        deleteButton?.isEnabled = hasSelection
        targetPopup?.isEnabled = hasSelection
        displaysButton?.isEnabled = hasSelection
    }

    private var selectedWallpaper: Wallpaper? {
        guard let index = selectedIndex, index < displayedWallpapers.count else { return nil }
        return displayedWallpapers[index]
    }

    // MARK: - Actions

    @objc private func searchChanged(_ sender: NSSearchField) {
        reloadData()
    }

    @objc private func importTapped() {
        ImportHandler.shared.importFromFilePicker { [weak self] _ in
            self?.reloadData()
        }
    }

    @objc private func applyLiveWallpaper() {
        guard let wallpaper = selectedWallpaper else { return }
        let target = selectedWallpaperTarget
        
        // Ensure at least one display is selected
        guard !selectedDisplayIDs.isEmpty else {
            AuroraLogger.ui.warning("Cannot apply wallpaper: no displays selected")
            return
        }

        // Apply to all selected displays
        for displayID in selectedDisplayIDs {
            WallpaperManager.shared.setWallpaper(wallpaper, for: displayID, target: target)
        }
        
        AuroraLogger.ui.info("Applied wallpaper '\(wallpaper.name, privacy: .public)' to \(self.selectedDisplayIDs.count) display(s) with target: \(target.description)")
        showApplyFeedback(on: applyButton, originalTitle: "✦ Apply")
    }

    /// Returns the currently selected wallpaper target from the popup.
    private var selectedWallpaperTarget: WallpaperTarget {
        let targets = WallpaperTarget.allCases
        let index = targetPopup?.indexOfSelectedItem ?? 0
        guard index >= 0 && index < targets.count else { return .both }
        return targets[index]
    }

    @objc private func setAsStaticWallpaper() {
        guard let wallpaper = selectedWallpaper else { return }
        WallpaperManager.shared.setStaticWallpaper(wallpaper)
        AuroraLogger.ui.info("Set static wallpaper '\(wallpaper.name, privacy: .public)' as macOS wallpaper")
        showApplyFeedback(on: setStaticButton, originalTitle: "Set as Wallpaper")
    }

    /// Shows brief "✓ Applied!" feedback on any apply button.
    private func showApplyFeedback(on button: NSButton, originalTitle: String) {
        button.title = "✓ Applied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak button] in
            button?.title = originalTitle
        }
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
        
        guard let popover = displaysPopover else { return }
        
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: displaysButton.bounds, of: displaysButton, preferredEdge: .minY)
        }
    }

    private func updateDisplaysButtonTitle() {
        let totalScreens = NSScreen.screens.count
        if selectedDisplayIDs.count == totalScreens && totalScreens > 0 {
            displaysButton.title = "Displays: All"
        } else if selectedDisplayIDs.isEmpty {
            displaysButton.title = "Displays: None"
        } else {
            displaysButton.title = "Displays: \(selectedDisplayIDs.count)"
        }
    }

    @objc private func previewSelectedWallpaper() {
        guard let wallpaper = selectedWallpaper else { return }
        // Retain the panel to prevent ARC deallocation
        let panel = PreviewPanel(wallpaper: wallpaper)
        self.previewPanel = panel
        panel.showPreview()
    }

    @objc private func deleteSelectedWallpaper() {
        guard let wallpaper = selectedWallpaper else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \"\(wallpaper.name)\"?"
        alert.informativeText = "The wallpaper file will be permanently removed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            WallpaperLibrary.shared.remove(id: wallpaper.id)
            reloadData()
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension LibraryViewController: NSCollectionViewDataSource {

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return displayedWallpapers.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.itemIdentifier, for: indexPath)

        if let cell = item as? WallpaperCollectionViewItem {
            let wallpaper = displayedWallpapers[indexPath.item]
            cell.configure(with: wallpaper)
        }

        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension LibraryViewController: NSCollectionViewDelegate {

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        if let indexPath = indexPaths.first {
            selectedIndex = indexPath.item
            AuroraLogger.ui.debug("Selected wallpaper at index \(indexPath.item)")
        }
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        if collectionView.selectionIndexPaths.isEmpty {
            selectedIndex = nil
        }
    }
}

// MARK: - DisplaySelectorDelegate

extension LibraryViewController: DisplaySelectorDelegate {
    func displaySelectionDidChange(selectedDisplayIDs: Set<CGDirectDisplayID>) {
        self.selectedDisplayIDs = selectedDisplayIDs
        updateDisplaysButtonTitle()
    }
}

// MARK: - WallpaperCollectionViewItem

/// A single cell in the wallpaper grid with improved styling.
final class WallpaperCollectionViewItem: NSCollectionViewItem {

    private var thumbnailImageView: NSImageView!
    private var nameLabel: NSTextField!
    private var metadataLabel: NSTextField!
    private var gradientLayer: CAGradientLayer!
    private var trackingArea: NSTrackingArea?

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 195, height: 155))
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor

        // Thumbnail image (fills most of the cell)
        thumbnailImageView = NSImageView(frame: NSRect(x: 0, y: 36, width: 195, height: 119))
        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.imageAlignment = .alignCenter
        view.addSubview(thumbnailImageView)

        // Gradient overlay for text readability at the bottom of the thumbnail
        gradientLayer = CAGradientLayer()
        gradientLayer.frame = NSRect(x: 0, y: 36, width: 195, height: 40)
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.4).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        view.layer?.addSublayer(gradientLayer)

        // Name label
        nameLabel = NSTextField(labelWithString: "")
        nameLabel.frame = NSRect(x: 8, y: 14, width: 179, height: 18)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.alignment = .left
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textColor = .labelColor
        view.addSubview(nameLabel)

        // Metadata label (resolution, duration)
        metadataLabel = NSTextField(labelWithString: "")
        metadataLabel.frame = NSRect(x: 8, y: 0, width: 179, height: 14)
        metadataLabel.font = .systemFont(ofSize: 10)
        metadataLabel.alignment = .left
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.textColor = .secondaryLabelColor
        view.addSubview(metadataLabel)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Update tracking area on layout
        if let existing = trackingArea {
            view.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    func configure(with wallpaper: Wallpaper) {
        nameLabel.stringValue = wallpaper.name

        // Build metadata string
        var meta: [String] = []
        if let resolution = wallpaper.resolution, resolution != "Unknown" {
            meta.append(resolution)
        }
        if let duration = wallpaper.duration, duration > 0 {
            let formatted = duration < 60
                ? String(format: "%.0fs", duration)
                : String(format: "%.0fm %02.0fs", (duration / 60).rounded(.down), duration.truncatingRemainder(dividingBy: 60))
            meta.append(formatted)
        }
        metadataLabel.stringValue = meta.joined(separator: " · ")

        // Load thumbnail
        if let thumbPath = wallpaper.thumbnailPath,
           let image = NSImage(contentsOfFile: thumbPath) {
            thumbnailImageView.image = image
        } else {
            // Placeholder icon if no thumbnail
            thumbnailImageView.image = NSImage(systemSymbolName: "film", accessibilityDescription: "Video")
        }
    }

    // MARK: - Selection / Hover

    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                view.animator().layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.4).cgColor
                view.animator().layer?.borderWidth = 1.5
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                view.animator().layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
                view.animator().layer?.borderWidth = 1
            }
        }
    }

    private func updateAppearance() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            if isSelected {
                view.animator().layer?.borderColor = NSColor.controlAccentColor.cgColor
                view.animator().layer?.borderWidth = 2.5
                view.animator().layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            } else {
                view.animator().layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
                view.animator().layer?.borderWidth = 1
                view.animator().layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailImageView.image = nil
        nameLabel.stringValue = ""
        metadataLabel.stringValue = ""
        updateAppearance()
    }
}
