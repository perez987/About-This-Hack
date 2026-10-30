//
//  ContentView.swift
//  About This Hack
//
//  Main SwiftUI view: fake-sidebar navigation (custom HStack layout).
//  Uses a plain HStack with a fixed-width sidebar panel and a detail panel
//  instead of NavigationSplitView, which had persistent tap-event issues on
//  macOS Tahoe.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.overviewData != nil {
                FakeSidebarLayout()
            } else {
                LoadingView()
            }
        }
        .frame(minWidth: 680, minHeight: 420)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
            Text(
                NSLocalizedString(
                    "loading.data.message",
                    comment: "Loading data message"
                )
            )
            .font(.title3)
            .foregroundColor(.secondary)
        }
        .padding(32)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.95)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Fake Sidebar Layout

//
// Replaces NavigationSplitView with a plain HStack so that tap events on the
// sidebar rows are always processed reliably, regardless of macOS version.
// The sidebar rows directly write appState.selectedSection on tap; no Binding
// plumbing or task(id:) synchronisation is needed.

private struct FakeSidebarLayout: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // ── Sidebar ─────
            if appState.isSidebarVisible {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(
                        AppSection.allCases.filter {
                            appState.shouldShowAudioTab || $0 != .audio
                        }
                    ) { section in
                        SidebarRow(
                            section: section,
                            isSelected: appState.selectedSection == section
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.selectedSection = section
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
                .frame(width: 185)
                .frame(maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor)) // opaque window
                //                .background(.ultraThinMaterial)  // transparent window
                .transition(.move(edge: .leading))
                //                Divider()
                .transition(.opacity)
            }

            // ── Detail ─────
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(appState.selectedSection)
                .transition(.opacity)
        }
        //        .background(Color(NSColor.controlBackgroundColor)) // opaque window
        //        .background(.ultraThinMaterial)  // transparent window
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appState.isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help(
                    NSLocalizedString(
                        "toolbar.toggle_sidebar",
                        comment: "Toggle Sidebar"
                    )
                )
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedSection {
        case .overview, .none:
            OverviewView()
        case .displays:
            if appState.isDataLoaded {
                DisplaysView()
            } else {
                LoadingView()
            }
        case .storage:
            if appState.isDataLoaded {
                StorageView()
            } else {
                LoadingView()
            }
        case .audio:
            if !appState.isDataLoaded {
                LoadingView()
            } else if appState.shouldShowAudioTab {
                AudioView()
            } else {
                OverviewView()
            }
        case .support:
            SupportView()
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.systemImage)
                .font(
                    .system(size: 13, weight: isSelected ? .semibold : .regular)
                )
                .foregroundColor(
                    isSelected
                        ? .primary
                        : (isHovered ? Color.primary.opacity(0.85) : .secondary)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.18)
                                : (isHovered
                                    ? Color.primary.opacity(0.08) : Color.clear)
                        )
                )
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 2)
                        .opacity(isSelected ? 1 : 0)
                        .scaleEffect(
                            x: 1,
                            y: isSelected ? 1 : 0.3,
                            anchor: .center
                        )
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(section.tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
