//
//  SettingsWindowController.swift
//  About This Hack
//

import Cocoa
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    // MARK: - Constants

    private static let windowWidth: CGFloat = 422
    /// Content height matches the SwiftUI view frame height
    private static let contentHeight: CGFloat = 330

    // MARK: - State

    private var isSetupComplete = false

    // MARK: - Initialization

    convenience init() {
        // Create the window programmatically
        // Use the content height to match the SwiftUI view's frame
        let contentRect = NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.contentHeight)
//        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable] // opaque window
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView] // transparent window
        let window = NSWindow(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)

        // Configure window properties
        window.title = NSLocalizedString("settings.title", comment: "Custom logo settings")
        window.isReleasedWhenClosed = false

        // TRANSPARENT WINDOW ------------------------

        // Enable transparent liquid-glass style (Tahoe): the SwiftUI content
        // supplies a material background (.regularMaterial), so the window
        // itself is kept transparent and non-opaque.
//        window.isOpaque = false
//        window.backgroundColor = .clear
//        window.titlebarAppearsTransparent = true

        // END ------------------------

        self.init(window: window)

        // For programmatically created windows, windowDidLoad() is not called automatically
        // We need to set up the content here
        performSetupIfNeeded()
    }

    // MARK: - Lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()

        // Ensure setup is performed (either here or from init)
        performSetupIfNeeded()
    }

    // MARK: - Setup Methods

    private func performSetupIfNeeded() {
        // Note: This is always called on the main thread (AppKit lifecycle guarantee)
        guard !isSetupComplete else { return }

        setupWindowProperties()
        setupSwiftUIContent()
        isSetupComplete = true
    }

    private func setupWindowProperties() {
        // Set window properties
        window?.styleMask.remove(.resizable)
        window?.delegate = self

        // Explicitly set the window size to ensure it's applied correctly
        setWindowSize()
    }

    func windowWillClose(_: Notification) {
        print("Settings window closed")
    }

    override func windowWillLoad() {
        super.windowWillLoad()
        // Prevent window cascading to ensure consistent positioning
        shouldCascadeWindows = false
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        // Reset window size every time it's shown to prevent any saved frame from being used
        setWindowSize()

        // Position window next to main window
        positionWindowNextToMainWindow()
    }

    // MARK: - Window Management

    private func setWindowSize() {
        let windowSize = NSSize(width: Self.windowWidth, height: Self.contentHeight)
        window?.setContentSize(windowSize)
        window?.minSize = windowSize
        window?.maxSize = windowSize
    }

    private func positionWindowNextToMainWindow() {
        guard let settingsWindow = window else {
            return
        }

        // Find the main application window by title (not the settings window itself)
        let mainWindow = NSApplication.shared.windows.first { window in
            window != settingsWindow &&
                window.isVisible &&
                window.title == "About This Hack"
        }

        guard let mainWindow else {
            // Fallback: center the settings window if main window not found
            settingsWindow.center()
            return
        }

        let mainFrame = mainWindow.frame
        let settingsFrame = settingsWindow.frame

        // Position to the right of main window with some spacing
        let spacing: CGFloat = 10
        var newOrigin = NSPoint(
            x: mainFrame.maxX + spacing,
            y: mainFrame.maxY - settingsFrame.height
        )

        // Check if the window would go off-screen to the right
        if let screen = mainWindow.screen {
            let screenFrame = screen.visibleFrame

            // If off-screen to the right, try positioning to the left
            if newOrigin.x + settingsFrame.width > screenFrame.maxX {
                newOrigin.x = mainFrame.minX - settingsFrame.width - spacing
            }

            // If still off-screen (now to the left), position below the main window
            if newOrigin.x < screenFrame.minX {
                newOrigin.x = mainFrame.minX
                newOrigin.y = mainFrame.minY - settingsFrame.height - spacing
            }

            // If off-screen below, position above the main window
            if newOrigin.y < screenFrame.minY {
                newOrigin.x = mainFrame.minX
                newOrigin.y = mainFrame.maxY + spacing
            }

            // Ensure the window is fully visible on screen
            if newOrigin.x < screenFrame.minX {
                newOrigin.x = screenFrame.minX
            }
            if newOrigin.y < screenFrame.minY {
                newOrigin.y = screenFrame.minY
            }
            if newOrigin.x + settingsFrame.width > screenFrame.maxX {
                newOrigin.x = screenFrame.maxX - settingsFrame.width
            }
            if newOrigin.y + settingsFrame.height > screenFrame.maxY {
                newOrigin.y = screenFrame.maxY - settingsFrame.height
            }
        }

        settingsWindow.setFrameOrigin(newOrigin)
    }

    // MARK: - Setup

    private func setupSwiftUIContent() {
        // Create SwiftUI view and wrap it in NSHostingController
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        // Set the hosting controller as the window's content view controller
        window?.contentViewController = hostingController
    }
}
