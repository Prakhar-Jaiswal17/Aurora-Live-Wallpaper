// Aurora — DisplaySelectorViewController
// A popover view controller that allows the user to select one or multiple displays
// to apply a wallpaper to. Includes an "All Screens" toggle.

import AppKit

protocol DisplaySelectorDelegate: AnyObject {
    /// Called when the user changes the display selection.
    func displaySelectionDidChange(selectedDisplayIDs: Set<CGDirectDisplayID>)
}

/// A view controller intended to be shown in an NSPopover to select target displays.
final class DisplaySelectorViewController: NSViewController {

    weak var delegate: DisplaySelectorDelegate?
    private(set) var selectedDisplayIDs: Set<CGDirectDisplayID> = []

    private let stackView = NSStackView()
    private var allScreensCheckbox: NSButton!
    private var screenCheckboxes: [NSButton] = []

    // MARK: - Init

    init(selectedDisplayIDs: Set<CGDirectDisplayID>) {
        self.selectedDisplayIDs = selectedDisplayIDs
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        self.view = NSView()
        
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        
        setupCheckboxes()
        updateAllScreensCheckboxState()
    }

    // MARK: - Setup

    private func setupCheckboxes() {
        let screens = NSScreen.screens
        
        // "All Screens" checkbox
        allScreensCheckbox = NSButton(checkboxWithTitle: "All Screens", target: self, action: #selector(allScreensToggled(_:)))
        allScreensCheckbox.allowsMixedState = true
        allScreensCheckbox.font = .systemFont(ofSize: 13, weight: .semibold)
        stackView.addArrangedSubview(allScreensCheckbox)
        
        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -32).isActive = true
        
        // Individual screen checkboxes
        for (index, screen) in screens.enumerated() {
            let displayID = screen.displayID
            let isMain = screen == NSScreen.main
            let title = "Display \(index + 1)\(isMain ? " (Main)" : "") — \(Int(screen.frame.width))×\(Int(screen.frame.height))"
            
            let checkbox = NSButton(checkboxWithTitle: title, target: self, action: #selector(screenToggled(_:)))
            checkbox.tag = Int(displayID)
            checkbox.font = .systemFont(ofSize: 13)
            
            // Check if it's selected (or default to selected if no initial selection was passed and we want everything selected)
            let isSelected = selectedDisplayIDs.contains(displayID)
            checkbox.state = isSelected ? .on : .off
            
            screenCheckboxes.append(checkbox)
            stackView.addArrangedSubview(checkbox)
        }
    }

    // MARK: - Actions

    @objc private func allScreensToggled(_ sender: NSButton) {
        // If mixed state is somehow hit manually, treat as turning everything on
        let targetState: NSControl.StateValue = (sender.state == .off) ? .off : .on
        sender.state = targetState
        
        selectedDisplayIDs.removeAll()
        
        for checkbox in screenCheckboxes {
            checkbox.state = targetState
            if targetState == .on {
                selectedDisplayIDs.insert(CGDirectDisplayID(checkbox.tag))
            }
        }
        
        delegate?.displaySelectionDidChange(selectedDisplayIDs: selectedDisplayIDs)
    }

    @objc private func screenToggled(_ sender: NSButton) {
        let displayID = CGDirectDisplayID(sender.tag)
        if sender.state == .on {
            selectedDisplayIDs.insert(displayID)
        } else {
            selectedDisplayIDs.remove(displayID)
        }
        
        updateAllScreensCheckboxState()
        delegate?.displaySelectionDidChange(selectedDisplayIDs: selectedDisplayIDs)
    }

    private func updateAllScreensCheckboxState() {
        let allSelected = screenCheckboxes.allSatisfy { $0.state == .on }
        let noneSelected = screenCheckboxes.allSatisfy { $0.state == .off }
        
        if allSelected {
            allScreensCheckbox.state = .on
        } else if noneSelected {
            allScreensCheckbox.state = .off
        } else {
            allScreensCheckbox.state = .mixed
        }
    }
}
