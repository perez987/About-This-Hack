//
//  UpdateController.swift
//  About This Hack
//

import Sparkle

/// View model that publishes when checks for updates can be performed by the user
@MainActor
final class UpdaterController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        print("Checking for updates")
        updaterController.updater.checkForUpdates()
    }
}
