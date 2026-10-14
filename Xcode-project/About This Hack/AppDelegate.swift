//
//  AppDelegate.swift
//  About This Hack
//

import Cocoa
import Foundation
import Sparkle
import SwiftUI

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    // MARK: - App Entry Point (storyboard-free) -----------------------------------------

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // END: - App Entry Point (storyboard-free) -----------------------------------------

    // MARK: - Properties -----------------------------------------

    private var mainWindow: NSWindow?
    private var settingsWindowController: SettingsWindowController?
    private var languageSelectorWindowController: LanguageSelectorWindowController?
    private var updaterController: UpdaterController?

    // END: - Properties -----------------------------------------

    // MARK: - Application Lifecycle -----------------------------------------

    override init() {
        super.init()
        print("Application starting")
        updaterController = UpdaterController()
    }

    func applicationWillFinishLaunching(_: Notification) {
        NSApp.mainMenu = createMainMenu()
    }

    func applicationDidFinishLaunching(_: Notification) {
        AppState.shared.startLoading()
        createAndShowMainWindow()
        insertLanguageMenu()
    }

    func applicationWillTerminate(_: Notification) {
        print("Application terminating")
        try? FileManager.default.removeItem(atPath: InitGlobVar.athDirectory)
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    // END: - Application Lifecycle -----------------------------------------

    // MARK: - Main Window -----------------------------------------

    private func createAndShowMainWindow() {
        let defaultSize = NSSize(width: 760, height: 480)
        let contentRect = NSRect(origin: .zero, size: defaultSize)

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "About This Hack"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 420)

        // MARK: transparent window -----------------------------------------

        // Enable transparent liquid-glass style (Tahoe): the SwiftUI content
        // supplies material backgrounds (.regularMaterial / .ultraThinMaterial),
        // so the window itself is kept transparent and non-opaque.
//        window.isOpaque = false
//        window.backgroundColor = .clear
//        window.titlebarAppearsTransparent = true

        // END: transparent window -----------------------------------------

        // Restore saved position, or center the window.
        if let savedFrame = AppState.shared.savedWindowFrame(for: defaultSize) {
            window.setFrame(savedFrame, display: false)
        } else {
            window.center()
        }

        // Host the SwiftUI ContentView.
        let hosting = NSHostingController(rootView: ContentView().environmentObject(AppState.shared))
        window.contentViewController = hosting

        // Save frame on move / resize.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                if let f = window?.frame { AppState.shared.saveWindowFrame(f) }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                if let f = window?.frame { AppState.shared.saveWindowFrame(f) }
            }
        }

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // END: - Main Window -----------------------------------------

    // MARK: - Menu Actions (tab navigation) -----------------------------------------

    @IBAction func showOverview(_: Any) {
        AppState.shared.selectedSection = .overview
        bringMainWindowToFront()
    }

    @IBAction func showDisplays(_: Any) {
        AppState.shared.selectedSection = .displays
        bringMainWindowToFront()
    }

    @IBAction func showStorage(_: Any) {
        AppState.shared.selectedSection = .storage
        bringMainWindowToFront()
    }

    @IBAction func showAudio(_: Any) {
        AppState.shared.selectedSection = .audio
        bringMainWindowToFront()
    }

    @IBAction func showHelp(_: Any) {
        AppState.shared.selectedSection = .support
        bringMainWindowToFront()
    }

    private func bringMainWindowToFront() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // END: - Menu Actions (tab navigation) -----------------------------------------

    // MARK: - Settings Window -----------------------------------------

    @IBAction func showSettings(_: Any) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        print("Opening settings window")
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // END: - Settings Window -----------------------------------------

    // MARK: - Language Selector -----------------------------------------

    @IBAction func showLanguageSelector(_: Any) {
        if languageSelectorWindowController == nil {
            languageSelectorWindowController = LanguageSelectorWindowController()
        }
        languageSelectorWindowController?.parentWindow = mainWindow
        print("Opening language selector")
        languageSelectorWindowController?.showWindow(nil)
        languageSelectorWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // END: - Language Selector -----------------------------------------

    // MARK: - Sparkle Updates -----------------------------------------

    @IBAction func checkForUpdates(_: Any) {
        updaterController?.checkForUpdates()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) {
            return updaterController?.canCheckForUpdates ?? false
        }
        if menuItem.action == #selector(showAudio(_:)) {
            return AppState.shared.shouldShowAudioTab
        }
        return true
    }

    // END: - Sparkle Updates -----------------------------------------

    // MARK: - Main Menu -----------------------------------------

    private func createMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "")

        // Apple menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: NSLocalizedString("menu.app.title", comment: "App menu title"))

        appMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.app.about", comment: "About app"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(
            title: NSLocalizedString("Check for Updates...", comment: "Menu item to check for app updates"),
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: "u"
        )
        checkForUpdatesItem.target = self
        checkForUpdatesItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        appMenu.addItem(checkForUpdatesItem)
        appMenu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: NSLocalizedString("menu.app.preferences", comment: "Preferences"),
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(
            title: NSLocalizedString("menu.app.services", comment: "Services"),
            action: nil,
            keyEquivalent: ""
        )
        let servicesMenu = NSMenu(title: NSLocalizedString("menu.app.services", comment: "Services"))
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.app.hide", comment: "Hide app"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))

        let hideOthersItem = NSMenuItem(
            title: NSLocalizedString("menu.app.hide_others", comment: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.option, .command]
        appMenu.addItem(hideOthersItem)

        appMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.app.show_all", comment: "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.app.quit", comment: "Quit app"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = NSLocalizedString("menu.window.title", comment: "Window menu title")
        let windowMenu = NSMenu(title: NSLocalizedString("menu.window.title", comment: "Window menu title"))

        windowMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.window.minimize", comment: "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.window.close", comment: "Close"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        windowMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.window.zoom", comment: "Zoom"),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        ))

        let overviewItem = NSMenuItem(
            title: NSLocalizedString("menu.window.overview", comment: "Overview"),
            action: #selector(showOverview(_:)),
            keyEquivalent: "1"
        )
        overviewItem.target = self
        windowMenu.addItem(overviewItem)

        let displaysItem = NSMenuItem(
            title: NSLocalizedString("menu.window.displays", comment: "Displays"),
            action: #selector(showDisplays(_:)),
            keyEquivalent: "2"
        )
        displaysItem.target = self
        windowMenu.addItem(displaysItem)

        let storageItem = NSMenuItem(
            title: NSLocalizedString("menu.window.storage", comment: "Storage"),
            action: #selector(showStorage(_:)),
            keyEquivalent: "3"
        )
        storageItem.target = self
        windowMenu.addItem(storageItem)

        let audioItem = NSMenuItem(
            title: NSLocalizedString("menu.window.audio", comment: "Audio"),
            action: #selector(showAudio(_:)),
            keyEquivalent: "4"
        )
        audioItem.target = self
        windowMenu.addItem(audioItem)

        let supportItem = NSMenuItem(
            title: NSLocalizedString("menu.window.support", comment: "Support"),
            action: #selector(showHelp(_:)),
            keyEquivalent: "5"
        )
        supportItem.target = self
        windowMenu.addItem(supportItem)

        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.window.bring_all_to_front", comment: "Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        ))

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenuItem = NSMenuItem()
        helpMenuItem.title = NSLocalizedString("menu.help.title", comment: "Help menu title")
        let helpMenu = NSMenu(title: NSLocalizedString("menu.help.title", comment: "Help menu title"))

        helpMenu.addItem(NSMenuItem(
            title: NSLocalizedString("menu.help.ath_help", comment: "About This Hack Help"),
            action: #selector(NSApplication.showHelp(_:)),
            keyEquivalent: "?"
        ))

        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    // END Main menu -----------------------------------------

    // MARK: - Language Menu -----------------------------------------

    private func insertLanguageMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }

        // Build "Select Language…" submenu item with Cmd+L
        let selectItem = NSMenuItem(
            title: NSLocalizedString("Select Language menu item", comment: "Select Language menu item"),
            action: #selector(showLanguageSelector(_:)),
            keyEquivalent: "l"
        )
        selectItem.keyEquivalentModifierMask = .command
        selectItem.target = self

        // Build the Language submenu
        let languageSubmenu = NSMenu(
            title: NSLocalizedString("Language menu", comment: "Language menu title")
        )
        languageSubmenu.addItem(selectItem)

        // Build the top-level Language menu item
        let languageMenuItem = NSMenuItem()
        languageMenuItem.title = NSLocalizedString("Language menu", comment: "Language menu title")
        languageMenuItem.submenu = languageSubmenu

        // Insert between "About This Hack" (index 0) and "Window"
        let windowIndex = mainMenu.items.firstIndex { $0.title == "Window" } ?? 1
        mainMenu.insertItem(languageMenuItem, at: windowIndex)
    }

    // END Language menu -----------------------------------------
}
