//
//  ViewControllerStorage.swift
//  About This Hack
//
//  SwiftUI Storage tab: startup disk icon, capacity info, and usage progress bar.
//

import AppKit
import SwiftUI

// MARK: - Storage View

struct StorageView: View {
    private let info = StorageViewModel()

    private var tintColor: Color {
        if info.storagePercent >= 0.9 { return .red }
        if info.storagePercent >= 0.75 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(nsImage: info.diskImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .help(info.diskImageTooltip)

                Text(info.storageData)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .help(info.storageValueTooltip)

                VStack(spacing: 4) {
                    ProgressView(value: info.storagePercent, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(tintColor)
                        .frame(maxWidth: 260)
                        .help(info.storageValueTooltip)
                    HStack {
                        Spacer()
                        Text(String(format: "%.0f%%", min(info.storagePercent * 100, 100)))
                            .font(.system(size: 14, weight: .regular))
//                            .foregroundColor(tintColor)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: 260)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Model

struct StorageViewModel {
    let diskImage: NSImage
    let storageData: String
    let storagePercent: Double
    let diskImageTooltip: String
    let storageValueTooltip: String

    init() {
        let hc = HardwareCollector.shared
        let t = Tooltips.shared

        // Resolve disk image (OS-specific name first, then generic SSD/HDD)
        let imageShortName = "\(HCVersion.shared.osName) \(hc.deviceLocation)"
        let storageType = hc.storageType ? "SSD" : "HDD"
        if let img = NSImage(named: "\(imageShortName) \(storageType)") {
            diskImage = img
        } else {
            diskImage = NSImage(named: storageType) ?? NSImage()
        }

        storageData = hc.storageData
        storagePercent = hc.storagePercent

        diskImageTooltip = t.startupDiskImagetoolTip
        storageValueTooltip = t.storageValuetoolTip
    }
}
