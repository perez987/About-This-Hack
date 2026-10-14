//
//  LanguageSelectorWindowController.swift
//  About This Hack
//
//  Window controller for the language selector.
//

import Cocoa
import SwiftUI

class LanguageSelectorWindowController: NSWindowController, NSWindowDelegate {
    // MARK: - Constants

    private static let windowWidth: CGFloat = 280
    private static let windowHeight: CGFloat = 280

    // MARK: - State

    private var isSetupComplete = false

    // MARK: - Parent Window

    /// The window to center on. Set this before calling showWindow(_:).
    weak var parentWindow: NSWindow?

    // MARK: - Initialization

    convenience init() {
        let contentRect = NSRect(
            x: 0, y: 0,
            width: Self.windowWidth,
            height: Self.windowHeight
        )
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Language selector title", comment: "Language selector title")
        window.isReleasedWhenClosed = false

        // MARK: transparent window

//        window.isOpaque = false
//        window.backgroundColor = .clear
//        window.titlebarAppearsTransparent = true

        self.init(window: window)
        performSetupIfNeeded()
    }

    // MARK: - Lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()
        performSetupIfNeeded()
    }

    // MARK: - Setup

    private func performSetupIfNeeded() {
        guard !isSetupComplete else { return }
        setupWindowProperties()
        setupSwiftUIContent()
        isSetupComplete = true
    }

    private func setupWindowProperties() {
        let contentSize = NSSize(width: Self.windowWidth, height: Self.windowHeight)
        window?.setContentSize(contentSize)
        window?.delegate = self
        // Use the actual frame size (content area + title bar) for min/max constraints
        // so the window cannot be resized and the constraints match the real frame.
        let frameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable]
        ).size
        window?.minSize = frameSize
        window?.maxSize = frameSize
    }

    override func showWindow(_ sender: Any?) {
        centerWindowOnScreen()
        super.showWindow(sender)
    }

    func windowWillClose(_: Notification) {
        print("Language selector closed")
    }

    // MARK: - Window Management

    private func centerWindowOnScreen() {
        guard let win = window else { return }

        // Use the explicitly set parentWindow if available, otherwise search by title.
        let target = parentWindow ?? NSApplication.shared.windows.first { w in
            w != win && w.isVisible && w.title == "About This Hack"
        }

        // Compute the real frame size (content + title bar) from known constants so
        // centering is correct even before the window has been laid out on-screen.
        let frameSize = NSWindow.frameRect(
            forContentRect: NSRect(origin: .zero, size: NSSize(width: Self.windowWidth, height: Self.windowHeight)),
            styleMask: [.titled, .closable]
        ).size

        if let target {
            let mainFrame = target.frame
            let origin = NSPoint(
                x: mainFrame.midX - frameSize.width / 2,
                y: mainFrame.midY - frameSize.height / 2
            )
            win.setFrameOrigin(origin)
        } else {
            win.center()
        }
    }

    // MARK: - SwiftUI Content

    private func setupSwiftUIContent() {
        let view = LanguageSelectorView { [weak self] in
            self?.window?.close()
        }
        let hosting = NSHostingController(rootView: view)
        window?.contentViewController = hosting
    }
}
