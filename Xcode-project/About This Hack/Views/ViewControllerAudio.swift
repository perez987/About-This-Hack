//
//  ViewControllerAudio.swift
//  About This Hack
//
//  SwiftUI Audio tab: motherboard audio codec information retrieved from the IORegistry.
//

import SwiftUI

// MARK: - Audio View

struct AudioView: View {
    @EnvironmentObject private var appState: AppState
    private let viewModel = AudioViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Image("Audio")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .padding(.bottom, 28)

                if viewModel.hasData {
                    specsSection
                } else {
                    Text(NSLocalizedString("audio.none", comment: "No audio codec info"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Specs Section

    private var specsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !viewModel.driver.isEmpty {
                AudioSpecRow(
                    label: (viewModel.driver == "USB" || viewModel.driver == "HDMI" || viewModel.driver == "DisplayPort")
                        ? NSLocalizedString("audio.spec.transport", comment: "Transport label")
                        : NSLocalizedString("audio.spec.driver", comment: "Driver label"),
                    value: viewModel.driver
                )
            }
            if !viewModel.codecName.isEmpty {
                AudioSpecRow(
                    label: (viewModel.driver == "USB" || viewModel.driver == "HDMI" || viewModel.driver == "DisplayPort")
                        ? NSLocalizedString("audio.spec.product", comment: "Product label")
                        : NSLocalizedString("audio.spec.codec", comment: "Codec label"),
                    value: viewModel.codecName,
                    tooltip: viewModel.codecTooltip
                )
            }
            if !viewModel.vendorName.isEmpty {
                AudioSpecRow(
                    label: (viewModel.driver == "HDMI" || viewModel.driver == "DisplayPort")
                        ? NSLocalizedString("audio.spec.graphics_card", comment: "Graphics card label")
                        : NSLocalizedString("audio.spec.vendor", comment: "Vendor label"),
                    value: viewModel.vendorName,
                    tooltip: viewModel.vendorTooltip
                )
            }
            if !viewModel.deviceName.isEmpty {
                AudioSpecRow(
                    label: NSLocalizedString("audio.spec.device_id", comment: "Device ID label"),
                    value: viewModel.deviceName,
                    tooltip: viewModel.deviceTooltip
                )
            }
            if !viewModel.layoutId.isEmpty {
                AudioSpecRow(
                    label: NSLocalizedString("audio.spec.layout_id", comment: "Layout ID label"),
                    value: viewModel.layoutId
                )
            }
        }
    }
}

// MARK: - Audio Spec Row

private struct AudioSpecRow: View {
    let label: String
    let value: String
    var tooltip: String = ""

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
                .frame(minWidth: labelWidth + 8, alignment: .leading)
                .help(tooltip)
        }
        .padding(.trailing, 50)
//        .border(.mint) // test
    }
}

// MARK: - View Model

struct AudioViewModel {
    let codecName: String
    let vendorName: String
    let deviceName: String
    let layoutId: String
    let driver: String
    let hasData: Bool
    let codecTooltip: String
    let vendorTooltip: String
    let deviceTooltip: String

    init() {
        let info = HCAudio.shared.getAudioInfo()
        codecName = info.codecName
        vendorName = info.vendorName
        deviceName = info.deviceName
        layoutId = info.layoutId
        driver = info.driver
        hasData = !info.vendorName.isEmpty || !info.codecName.isEmpty || !info.layoutId.isEmpty || !info.deviceName.isEmpty
        codecTooltip = info.codecHex
        vendorTooltip = info.vendorHex
        deviceTooltip = info.deviceHex
    }
}
