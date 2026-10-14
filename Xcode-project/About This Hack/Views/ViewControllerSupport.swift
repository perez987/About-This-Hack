//
//  ViewControllerSupport.swift
//  About This Hack
//
//  SwiftUI Support tab: quick-access links to macOS and Hackintosh resources.
//

import SwiftUI

// MARK: - Support View

struct SupportView: View {
    private let links: [(title: String, url: String)] = [
        (NSLocalizedString("support.macos_user_guide", comment: "macOS User Guide"), InitGlobVar.macOSUserGuideURL),
        (NSLocalizedString("support.whats_new", comment: "What's New in macOS"), InitGlobVar.whatsNewInMacOSURL),
        (NSLocalizedString("support.apple_support", comment: "Apple Support"), InitGlobVar.AppleSupportURL),
        (NSLocalizedString("support.hackintosh_guide", comment: "Hackintosh Guide"), InitGlobVar.HackintoshInstallURL),
        (NSLocalizedString("support.mac_basics", comment: "Mac Basics"), InitGlobVar.MacBasicsURL),
        (NSLocalizedString("support.mac_user_guide", comment: "Mac User Guide"), InitGlobVar.MacUserGuideURL),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                ForEach(links, id: \.title) { link in
                    SupportLinkButton(title: link.title, urlString: link.url)
                }
            }
            .padding(.horizontal, 40)
            Spacer()
            Text(NSLocalizedString("support.credits", comment: "Support credits"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Support Link Button

private struct SupportLinkButton: View {
    let title: String
    let urlString: String

    @State private var isHovered = false

    var body: some View {
        Button(action: openURL) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(isHovered ? .accentColor : .secondary)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered
                        ? Color.accentColor.opacity(0.3)
//                        : Color(NSColor.controlBackgroundColor))
                        : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 360)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private func openURL() {
        guard let url = URL(string: urlString) else { return }
        if NSWorkspace.shared.open(url) {
            // URL opened successfully
        } else {
            print("Error: Failed to open URL: \(urlString)")
        }
    }
}
