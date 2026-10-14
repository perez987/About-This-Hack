//
//  ViewControllerDisplays.swift
//  About This Hack
//
//  SwiftUI Displays tab: shows connected displays with icons, names and resolutions
//

import AppKit
import SwiftUI

// MARK: - Displays View

struct DisplaysView: View {
    @State private var displays: [DisplayInfo] = DisplaysViewModel.buildDisplayList()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            displayRow
                .padding(.bottom, 12)
            // Divider()
            HStack {
                Spacer()
                Button(NSLocalizedString("displays.preferences", comment: "Display Preferences button")) {
                    openDisplayPreferences()
                }
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            displays = await DisplaysViewModel.refreshDisplayList()
        }
        // Re-fetch display list whenever the screen configuration changes (e.g.
        // AirPlay or Sidecar connects / disconnects while the tab is already open).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            Task {
                displays = await DisplaysViewModel.refreshDisplayList()
            }
        }
    }

    // MARK: - Displays Row

    @ViewBuilder
    private var displayRow: some View {
        if displays.isEmpty {
            Text(NSLocalizedString("displays.none", comment: "No displays found"))
                .foregroundColor(.secondary)
        } else {
            GeometryReader { geometry in
                if displays.count >= 2 {
                    HorizontalScrollViewRepresentable(minWidth: geometry.size.width) {
                        HStack(alignment: .top, spacing: 32) {
                            ForEach(displays) { info in
                                DisplayCard(info: info)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 38)
                        .frame(minWidth: geometry.size.width, alignment: .center)
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 32) {
                            ForEach(displays) { info in
                                DisplayCard(info: info)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 38)
                        .frame(minWidth: geometry.size.width, alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(height: 310)
        }
    }

    private func openDisplayPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.displays") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Horizontal Scroll View (NSScrollView wrapper for always-visible scrollbar)

private struct HorizontalScrollViewRepresentable<Content: View>: NSViewRepresentable {
    let minWidth: CGFloat
    @ViewBuilder let content: () -> Content

    func makeNSView(context _: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.drawsBackground = false // Glass effect
        scrollView.borderType = .noBorder // Glass effect

        let hostingView = NSHostingView(rootView: AnyView(content()))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
        ])

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context _: Context) {
        if let hostingView = nsView.documentView as? NSHostingView<AnyView> {
            hostingView.rootView = AnyView(content())
        }
    }
}

// MARK: - Display Card

private struct DisplayCard: View {
    let info: DisplayInfo

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: info.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200)

            Text(info.name)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 120)
            Text(info.resolution)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 120)

            if !info.refreshRate.isEmpty {
                Text(info.refreshRate)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Display Info Model

struct DisplayInfo: Identifiable {
    let id: UUID
    let name: String
    let resolution: String
    let refreshRate: String
    let image: NSImage

    init(
        id: UUID = UUID(),
        name: String,
        resolution: String,
        refreshRate: String,
        image: NSImage
    ) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.image = image
    }
}

// MARK: - View Model

enum DisplaysViewModel {
    static func buildDisplayList() -> [DisplayInfo] {
        let collector = HardwareCollector.shared
        let screens = NSScreen.screens
        // Recompute the count at call-time rather than relying on the stored
        // numberOfDisplays (which is fixed at startup).  This ensures that an
        // AirPlay or Sidecar display that was connected AFTER app launch but
        // BEFORE the async refresh completes is still reflected in the initial
        // synchronous render, because NSScreen.screens already includes it.
        let count = max(
            collector.displayNames.isEmpty ? 0 : collector.displayNames.count,
            screens.count
        )
        guard count > 0 else { return [] }
        var result: [DisplayInfo] = []

        for i in 0 ..< count {
            // Prefer system_profiler data; fall back to NSScreen for displays that
            // appear in NSScreen but were not reported by system_profiler (e.g., when
            // the AirPlay/Sidecar section uses shallower indentation than expected and
            // the parser couldn't pick it up, or on future macOS versions that change
            // the output format).
            let rawName: String = if collector.displayNames.indices.contains(i) {
                collector.displayNames[i]
            } else if screens.indices.contains(i) {
                screens[i].localizedName
            } else {
                "Display \(i + 1)"
            }

            let rawRes: String
            if collector.displayRes.indices.contains(i) {
                rawRes = collector.displayRes[i]
            } else if screens.indices.contains(i) {
                let f = screens[i].frame
                rawRes = "\(Int(f.width)) x \(Int(f.height))"
            } else {
                rawRes = ""
            }

            let rawRefreshRate: String
            if collector.displayRefreshRates.indices.contains(i) {
                rawRefreshRate = collector.displayRefreshRates[i]
            } else if screens.indices.contains(i) {
                let hz = Int(screens[i].maximumFramesPerSecond)
                rawRefreshRate = hz > 0 ? "\(hz) Hz" : ""
            } else {
                rawRefreshRate = ""
            }

            let trimName = trimDisplayName(rawName)
            let trimRes = removeParentheses(rawRes)
            let image = displayImage(for: trimName, rawName: rawName, index: i, hasBuiltIn: collector.hasBuiltInDisplay)

            let display = DisplayInfo(
                name: trimName,
                resolution: trimRes,
                refreshRate: rawRefreshRate,
                image: image
            )
            result.append(display)
        }
        return result
    }

    static func refreshDisplayList() async -> [DisplayInfo] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                HardwareCollector.shared.refreshDisplayData()
                let displays = buildDisplayList()
                continuation.resume(returning: displays)
            }
        }
    }
}

// MARK: - Helpers

extension DisplaysViewModel {
    private static func trimDisplayName(_ name: String) -> String {
        let cleanName = removeParentheses(name)

        // Removed .anchored to search for a word in any part of the string
        if let range = cleanName.range(of: "display", options: [.caseInsensitive]) {
            // A substring from the beginning to the end of the word "display" inclusive
            let substring = cleanName[..<range.upperBound]
            return String(substring).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleanName
    }

    private static func removeParentheses(_ text: String) -> String {
        // Regular expressions in ReplacingOccurrences are recompiled for each call.
        // For a couple of screens this is not critical, but for optimization it is better to clear the spaces at the end.
        text.replacingOccurrences(of: "\\([^)]+\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayImage(for name: String, rawName: String, index: Int, hasBuiltIn: Bool) -> NSImage {
        let lowerName = name.lowercased()
        let lowerRawName = rawName.lowercased()

        // System icon in case the asset is not found in the bundle
        let fallbackImage = NSImage(systemSymbolName: "display", accessibilityDescription: nil) ?? NSImage()

        // The first display is built-in: iMac or MacBook
        if index == 0 && hasBuiltIn {
            let imageName = lowerName.contains("imac")
                ? genericImacImageNameForCurrentOS()
                : genericMacBookImageNameForCurrentOS()

            return NSImage(named: imageName) ?? fallbackImage
        }

        // External displays or Sidecar/AirPlay (iPad) — check both trimmed and raw name
        // because "AirPlay" / "Sidecar" may appear only inside parentheses in the raw name
        // and removeParentheses() strips them before displayImage receives the trimmed name.
        if lowerName.contains("sidecar") || lowerRawName.contains("sidecar") {
            return NSImage(named: "iPad") ?? fallbackImage
        }

        if lowerName.contains("airplay") || lowerRawName.contains("airplay") {
            return NSImage(named: "iPad") ?? fallbackImage
        }

        return NSImage(named: genericLCDImageNameForCurrentOS()) ?? fallbackImage
    }

    // MARK: - OS Version Mapping

    // Commented out since it enlarges the app build too much

    private static func genericImacImageNameForCurrentOS() -> String {
//        switch HCVersion.shared.osVersion {
//        case .bigSur:
//            return "genericImacBigSur"
//        case .monterey:
//            return "genericImacMonterey"
//        case .ventura:
//            return "genericImacVentura"
//        case .sonoma:
//            return "genericImacSonoma"
//        case .sequoia:
//            return "genericImacSequoia"
//        case .tahoe:
//            return "genericImacTahoe"
//        case .goldengate:
//            return "genericImacGoldenGate"
//        case .unknown:
//            return "genericImac"
//        }
        "genericImac"
    }

    private static func genericLCDImageNameForCurrentOS() -> String {
//        switch HCVersion.shared.osVersion {
//        case .bigSur:
//            return "genericLCDBigSur"
//        case .monterey:
//            return "genericLCDMonterey"
//        case .ventura:
//            return "genericLCDVentura"
//        case .sonoma:
//            return "genericLCDSonoma"
//        case .sequoia:
//            return "genericLCDSequoia"
//        case .tahoe:
//            return "genericLCDTahoe"
//        case .goldengate:
//            return "genericLCDGoldenGate"
//        case .unknown:
//            return "genericLCD"
//        }
        "genericLCD"
    }

    private static func genericMacBookImageNameForCurrentOS() -> String {
//        switch HCVersion.shared.osVersion {
//        case .bigSur:
//            return "genericMacBookBigSur"
//        case .monterey:
//            return "genericMacBookMonterey"
//        case .ventura:
//            return "genericMacBookVentura"
//        case .sonoma:
//            return "genericMacBookSonoma"
//        case .sequoia:
//            return "genericMacBookSequoia"
//        case .tahoe:
//            return "genericMacBookTahoe"
//        case .goldengate:
//            return "genericMacBookGoldenGate"
//        case .unknown:
//            return "genericMacBook"
//        }
        "genericMacBook"
    }
}
