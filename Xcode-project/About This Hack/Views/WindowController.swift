//
//  WindowController.swift
//  About This Hack
//
//  Shared observable state for the SwiftUI-based main interface.
//

import Foundation
import SwiftUI

// MARK: - Navigation Sections

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case displays
    case storage
    case audio
    case support

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview: NSLocalizedString("segment.title.overview", comment: "Overview")
        case .displays: NSLocalizedString("segment.title.displays", comment: "Displays")
        case .storage: NSLocalizedString("segment.title.storage", comment: "Storage")
        case .audio: NSLocalizedString("segment.title.audio", comment: "Audio")
        case .support: NSLocalizedString("segment.title.support", comment: "Support")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "info.circle"
        case .displays: "display"
        case .storage: "internaldrive"
        case .audio: "waveform.circle"
        case .support: "questionmark.circle"
        }
    }

    var tooltip: String {
        switch self {
        case .overview: NSLocalizedString("segment.tooltip.overview", comment: "Overview tooltip")
        case .displays: NSLocalizedString("segment.tooltip.displays", comment: "Displays tooltip")
        case .storage: NSLocalizedString("segment.tooltip.storage", comment: "Storage tooltip")
        case .audio: NSLocalizedString("segment.tooltip.audio", comment: "Audio tooltip")
        case .support: NSLocalizedString("segment.tooltip.support", comment: "Support tooltip")
        }
    }
}

// MARK: - App State

/// Shared observable state used by both AppDelegate (menu actions) and ContentView (navigation).
class AppState: ObservableObject {
    nonisolated(unsafe) static let shared = AppState()
    static let hackintoshAudioDrivers: Set<String> = ["AppleALC", "SimpleHDA", "HDAUniversal", "VoodooHDA", "USB", "eqMac", "HDMI", "DisplayPort"]

    @Published var selectedSection: AppSection? = .overview {
        didSet {
            guard selectedSection != oldValue else { return }
            let tabName = switch selectedSection {
            case .overview: "Overview"
            case .displays: "Displays"
            case .storage: "Storage"
            case .audio: "Audio"
            case .support: "Support"
            case .none: "Unknown"
            }
            print("Switched to tab: \(tabName)")
        }
    }

    @Published var isDataLoaded = false {
        didSet {
            if isDataLoaded, !oldValue {
                print("Hardware data loaded")
                if selectedSection == .audio, !shouldShowAudioTab {
                    selectedSection = .overview
                }
            }
        }
    }

    @Published var isSidebarVisible: Bool = true
    @Published private(set) var overviewData: OverviewSnapshot?

    /// True when audio codec data is available. Evaluated lazily after data loads.
    /// Unavailable until audio detection has finished on the background thread.
    var hasAudioData: Bool {
        guard isDataLoaded else { return false }
        let info = HCAudio.shared.getAudioInfo()
        return !info.vendorName.isEmpty || !info.codecName.isEmpty || !info.layoutId.isEmpty
    }

    private nonisolated(unsafe) static var didPrintRealMac = false
    private static func printRealMacOnce() {
        guard !didPrintRealMac else { return }
        didPrintRealMac = true
        print("Mac: no audio tab")
    }

    /// True when running on a Hackintosh (OpenCore without OCLP, or Clover).
    /// Unavailable until bootloader and audio detection have finished.
    var isHackintosh: Bool {
        guard isDataLoaded else { return false }
        let bootloader = HCBootloader.shared.getBootloader().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBootloader = bootloader.lowercased()

        if normalizedBootloader.hasPrefix("clover") {
            return true
        }
        if normalizedBootloader.hasPrefix("opencore") {
            if FileManager.default.fileExists(atPath: InitGlobVar.oclpXmlFilePath) {
                let driver = HCAudio.shared.getAudioInfo().driver
                // OpenCore + OCLP can mean either a real Mac patched for newer macOS
                // compatibility, or a Hackintosh that uses OCLP for driver patches
                // (e.g. audio, WiFi on Sonoma).  Treat as Hackintosh when
                // AppleALC, SimpleHDA, HDAUniversal, VoodooHDA, USB, eqMac, HDMI, or DisplayPort audio is detected as the default output.
                return AppState.hackintoshAudioDrivers.contains(driver)
            }
            return true
        }

        // Fallback for OpenCore systems where bootloader string lookup failed:
        // Known Hackintosh audio drivers (AppleALC / SimpleHDA / HDAUniversal / VoodooHDA /
        // USB / eqMac / HDMI / DisplayPort) indicate this is not a stock Apple boot path.
        let driver = HCAudio.shared.getAudioInfo().driver
        if AppState.hackintoshAudioDrivers.contains(driver) {
            return true
        }

        // Apple iBoot (Apple Silicon) or Apple UEFI → real Mac
        if normalizedBootloader.hasPrefix("apple iboot") || normalizedBootloader.hasPrefix("apple uefi") {
            AppState.printRealMacOnce()
        }
        return false
    }

    /// True when the audio tab should be visible.
    /// Shown on Hackintoshes running AppleALC, SimpleHDA, HDAUniversal, VoodooHDA (with getdump available),
    /// or with a USB, eqMac, HDMI, or DisplayPort audio device set as the default output.
    /// Hidden on real Macs and on Hackintoshes where none of these are active
    /// (or when VoodooHDA is active but getdump is not installed).
    /// Provisionally shown for OpenCore/Clover using the Overview snapshot while
    /// background detection finishes; no collectors are accessed before they are ready.
    var shouldShowAudioTab: Bool {
        guard isDataLoaded else {
            let bootloader = overviewData?.bootloader
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return bootloader.hasPrefix("opencore") || bootloader.hasPrefix("clover")
        }
        guard isHackintosh else { return false }
        let driver = HCAudio.shared.getAudioInfo().driver
        return AppState.hackintoshAudioDrivers.contains(driver)
    }

    private let defaults = UserDefaults.standard
    private let windowFrameKey = "MainWindowFrame"
    private var didStartLoading = false
    private init() {}

    @MainActor
    func startLoading() {
        guard !didStartLoading else { return }
        didStartLoading = true
        let displaySummary = OverviewSnapshot.screenSummary()
        DispatchQueue.global(qos: .userInitiated).async {
            // Fast path, as upstream commit 064d609: Graphics and Display come from native
            // APIs and Memory only needs the quick SPMemoryDataType report, so the Overview
            // appears almost instantly with its final values (no preliminary values flash).
            let nativeGPU = DispatchGroup()
            DispatchQueue.global(qos: .userInitiated).async(group: nativeGPU) {
                _ = HCGPU.shared.getNativeGPU()
            }
            CreateDataFiles.createOverviewDataFiles()
            nativeGPU.wait()
            let initial = OverviewSnapshot.initial(displaySummary: displaySummary)
            let showInitial = HCGPU.shared.getNativeGPU() != nil
            if showInitial {
                DispatchQueue.main.async {
                    AppState.shared.overviewData = initial
                }
            }

            // Slow reports, tooltips, detail tabs and audio detection continue on this
            // worker. Overview rows keep their values; only tooltips are filled in.
            // GPUs absent from Metal or with blank/Unknown names need SPDisplaysDataType;
            // Overview waits for the detailed snapshot instead of showing a placeholder.
            CreateDataFiles.getInitDataFiles()
            HardwareCollector.shared.getAllData()
            let detailed = OverviewSnapshot.detailed(from: initial)
            DispatchQueue.main.async {
                AppState.shared.overviewData = detailed
                AppState.shared.isDataLoaded = true
            }
        }
    }

    // MARK: - Window Frame Persistence

    func savedWindowFrame(for size: NSSize) -> NSRect? {
        guard let saved = defaults.string(forKey: windowFrameKey) else { return nil }
        var frame = NSRectFromString(saved)
        frame.size = size
        return frame
    }

    func saveWindowFrame(_ frame: NSRect) {
        defaults.set(NSStringFromRect(frame), forKey: windowFrameKey)
    }
}
