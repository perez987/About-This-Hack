//
//  ViewController.swift
//  About This Hack
//
//  SwiftUI Overview tab: macOS logo, version info, hardware specs, action buttons.
//

import AppKit
import IOKit
import SwiftUI

// MARK: - Overview View

struct OverviewView: View {
    @StateObject private var viewModel = OverviewViewModel()
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let sidebarVisible = appState.isSidebarVisible
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: sidebarVisible ? .leading : .center)

//            Divider()

            specsSection
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: sidebarVisible ? .leading : .center)

//            Divider()

            footerSection
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .customLogoDidChange)) { _ in
            viewModel.reloadLogo()
        }
        .onReceive(appState.$overviewData) { snapshot in
            if let snapshot {
                viewModel.snapshot = snapshot
            }
        }
    }

    // MARK: - Header (logo + OS info)

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: viewModel.logoImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.osFullName)
                    .font(.system(size: 22, weight: .semibold))
                Text(viewModel.systemVersion)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .help(viewModel.osVersionTooltip)
                Text(viewModel.macModel)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .help(viewModel.macModelTooltip)
            }
            .padding(.top, 8)

            if appState.isSidebarVisible {
                Spacer()
            }
        }
    }

    // MARK: - Specs Table

    private var specsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SpecRow(
                label: NSLocalizedString("spec.processor", comment: "Processor label"),
                value: viewModel.cpu,
                tooltip: viewModel.cpuTooltip
            )
            SpecRow(
                label: NSLocalizedString("spec.memory", comment: "Memory label"),
                value: viewModel.ram,
                tooltip: viewModel.ramTooltip
            )
            SpecRow(
                label: NSLocalizedString("spec.graphics", comment: "Graphics label"),
                value: viewModel.graphics,
                tooltip: viewModel.graphicsTooltip
            )
            SpecRow(
                label: NSLocalizedString("spec.display", comment: "Display label"),
                value: viewModel.display,
                tooltip: viewModel.displayTooltip
            )
            SpecRow(
                label: NSLocalizedString("spec.startup_disk", comment: "Startup Disk label"),
                value: viewModel.startupDisk,
                tooltip: viewModel.startupDiskTooltip
            )
            SerialRow(viewModel: viewModel)
            SpecRow(
                label: NSLocalizedString("spec.bootloader", comment: "Bootloader label"),
                value: viewModel.bootloader,
                tooltip: viewModel.bootloaderTooltip
            )
        }
    }

    // MARK: - Footer (buttons + credits)

    private var footerSection: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                Button(NSLocalizedString("button.system_report", comment: "System Report button")) {
                    viewModel.showSystemReport()
                }
                .buttonStyle(.bordered)
                .help(viewModel.systemReportButtonTooltip)
                Button(NSLocalizedString("button.software_update", comment: "Software Update button")) {
                    viewModel.showSoftwareUpdate()
                }
                .buttonStyle(.bordered)
                .help(viewModel.softwareUpdateButtonTooltip)
            }
            Spacer()
            Text(NSLocalizedString("credits.text", comment: "Credits text"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Spec Row

private struct SpecRow: View {
    let label: String
    let value: String
    let tooltip: String

    private let labelWidth: CGFloat = 154

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
                .padding(.trailing, 8)
            Text(value)
                .font(.system(size: 13))
                .help(tooltip)
        }
    }
}

// MARK: - Serial Row (with show/hide toggle)

private struct SerialRow: View {
    @ObservedObject var viewModel: OverviewViewModel

    private let labelWidth: CGFloat = 154

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(NSLocalizedString("spec.serial_number", comment: "Serial Number label"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
                .padding(.trailing, 8)

            if viewModel.isSerialHidden {
                Text(String(repeating: "•", count: 11))
                    .font(.system(size: 13))
            } else {
                Text(viewModel.serialNumber)
                    .font(.system(size: 13))
                    .help(viewModel.serialTooltip)
            }

            Button(action: { viewModel.isSerialHidden.toggle() }) {
                Image(systemName: viewModel.isSerialHidden ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .help(viewModel.serialTooltip)
        }
    }
}

// MARK: - View Model

/// Value-only snapshots keep SwiftUI away from collectors while background loading mutates them.
struct OverviewSnapshot {
    var osFullName = ""
    var systemVersion = ""
    var macModel = ""
    var cpu = ""
    var ram = ""
    var graphics = ""
    var display = ""
    var startupDisk = ""
    var serialNumber = ""
    var bootloader = ""
    var osVersionTooltip = ""
    var macModelTooltip = ""
    var cpuTooltip = ""
    var ramTooltip = ""
    var graphicsTooltip = ""
    var displayTooltip = ""
    var startupDiskTooltip = ""
    var serialTooltip = ""
    var bootloaderTooltip = ""
    var systemReportButtonTooltip = ""
    var softwareUpdateButtonTooltip = ""

    @MainActor
    static func screenSummary() -> String {
        guard let screen = NSScreen.screens.first else { return "⎯" }
        // Use logical dimensions, matching the existing "UI Looks like" preference.
        return "\(screen.localizedName) (\(Int(screen.frame.width)) x \(Int(screen.frame.height)))"
    }

    static func initial(displaySummary: String) -> OverviewSnapshot {
        HCVersion.shared.getVersion()
        HCMacModel.shared.getMacModel()

        var snapshot = OverviewSnapshot()
        snapshot.osFullName = "\(HCVersion.shared.osPrefix) \(HCVersion.shared.osName)"
        snapshot.systemVersion = "\(HCVersion.shared.osNumber) (\(HCVersion.shared.osBuildNumber))"
        let name = HCMacModel.shared.macName
        let fullModel = "\(name) - \(HCMacModel.shared.getModelIdentifier())"
        snapshot.macModel = fullModel.count > 60 ? name : fullModel
        snapshot.cpu = HCCPU.shared.getCPU()
        // Memory needs only the fast SPMemoryDataType report (created before this call).
        // Graphics and Display come from native APIs, as upstream. These are the final
        // values, so the rows never change after first appearance.
        snapshot.ram = HCRAM.shared.getRam()
        snapshot.graphics = HCGPU.shared.getNativeGPU() ?? "⎯"
        snapshot.display = displaySummary
        let volume = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey])
        snapshot.startupDisk = volume?.volumeName?.nilIfEmpty ?? "⎯"
        let platform = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { if platform != 0 { IOObjectRelease(platform) } }
        snapshot.serialNumber = HCSerialNumber.shared.getSerialNumber().nilIfEmpty
            ?? registryString(platform, kIOPlatformSerialNumberKey) ?? ""
        // The SPHardwareDataType report (needed for Clover) exists before this call.
        snapshot.bootloader = HCBootloader.shared.getBootloader()
        snapshot.systemReportButtonTooltip = Tooltips.shared.btSysInfotoolTip
        snapshot.softwareUpdateButtonTooltip = Tooltips.shared.btSoftUpdtoolTip
        return snapshot
    }

    static func detailed(from initial: OverviewSnapshot) -> OverviewSnapshot {
        var snapshot = initial
        // Memory, Graphics and Display keep their first-paint values. system_profiler
        // is only used for GPUs that Metal does not expose.
        if HCGPU.shared.getNativeGPU() == nil {
            snapshot.graphics = HCGPU.shared.getGPU().nilIfEmpty ?? initial.graphics
        }
        snapshot.startupDisk = HCStartupDisk.shared.getStartupDisk().nilIfEmpty ?? initial.startupDisk

        let t = Tooltips.shared
        snapshot.osVersionTooltip = t.osVersiontoolTip
        snapshot.macModelTooltip = t.macModeltoolTip
        snapshot.cpuTooltip = t.cputoolTip
        snapshot.ramTooltip = t.ramtoolTip
        snapshot.graphicsTooltip = t.graphicstoolTip
        snapshot.displayTooltip = t.displaytoolTip
        snapshot.startupDiskTooltip = t.startupDisktoolTip
        snapshot.serialTooltip = t.serialToggletoolTip
        snapshot.bootloaderTooltip = t.blVersiontoolTip
        return snapshot
    }
}

class OverviewViewModel: ObservableObject {
    @Published var logoImage: NSImage = .init()
    @Published var isSerialHidden: Bool = true
    @Published var snapshot: OverviewSnapshot

    var osFullName: String {
        snapshot.osFullName
    }

    var systemVersion: String {
        snapshot.systemVersion
    }

    var macModel: String {
        snapshot.macModel
    }

    var cpu: String {
        snapshot.cpu
    }

    var ram: String {
        snapshot.ram
    }

    var graphics: String {
        snapshot.graphics
    }

    var display: String {
        snapshot.display
    }

    var startupDisk: String {
        snapshot.startupDisk
    }

    var serialNumber: String {
        snapshot.serialNumber
    }

    var bootloader: String {
        snapshot.bootloader
    }

    var osVersionTooltip: String {
        snapshot.osVersionTooltip
    }

    var macModelTooltip: String {
        snapshot.macModelTooltip
    }

    var cpuTooltip: String {
        snapshot.cpuTooltip
    }

    var ramTooltip: String {
        snapshot.ramTooltip
    }

    var graphicsTooltip: String {
        snapshot.graphicsTooltip
    }

    var displayTooltip: String {
        snapshot.displayTooltip
    }

    var startupDiskTooltip: String {
        snapshot.startupDiskTooltip
    }

    var serialTooltip: String {
        snapshot.serialTooltip
    }

    var bootloaderTooltip: String {
        snapshot.bootloaderTooltip
    }

    var systemReportButtonTooltip: String {
        snapshot.systemReportButtonTooltip
    }

    var softwareUpdateButtonTooltip: String {
        snapshot.softwareUpdateButtonTooltip
    }

    private let defaults = UserDefaults.standard

    init() {
        snapshot = AppState.shared.overviewData ?? OverviewSnapshot()
        reloadLogo()
    }

    func reloadLogo() {
        if let path = defaults.string(forKey: CustomLogoConstants.customLogoPathKey),
           let image = NSImage(contentsOfFile: path)
        {
            logoImage = image
        } else {
            logoImage = NSImage(named: HCVersion.shared.getOSImageName()) ?? NSImage()
        }
    }

    func showSystemReport() {
        NSWorkspace.shared.open(URL(fileURLWithPath: InitGlobVar.systemReportSP))
    }

    func showSoftwareUpdate() {
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if majorVersion >= 13, let url = URL(string: InitGlobVar.softwareUpdateURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
