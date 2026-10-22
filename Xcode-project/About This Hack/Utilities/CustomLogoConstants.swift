//
//  CustomLogoConstants.swift
//  About This Hack
//

import Foundation

// MARK: - Shared Constants

enum CustomLogoConstants {
    static let customLogoPathKey = "customLogoPath"

    /// File name used when the custom logo is copied into the app's Application Support folder.
    private static let savedLogoFileName = "customLogo.png"

    /// URL of the copy kept inside Application Support/<bundle-id>/
    /// Returns nil only if the system cannot locate the Application Support directory.
    static var savedLogoURL: URL? {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let bundleDir = appSupportURL.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "AboutThisHack"
        )
        return bundleDir.appendingPathComponent(savedLogoFileName)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let customLogoDidChange = Notification.Name("customLogoDidChange")
}
