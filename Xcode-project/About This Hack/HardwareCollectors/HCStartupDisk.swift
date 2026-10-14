//
//  HCStartupDisk.swift
//  About This Hack
//

import Foundation

class HCStartupDisk {
    nonisolated(unsafe) static let shared = HCStartupDisk()
    private init() {}

    private lazy var startupDisk: String = {
        if let content = HardwareCollector.shared.getCachedFileContent(InitGlobVar.bootvolnameFilePath),
           let name = content.components(separatedBy: "\n")
           .first(where: { $0.contains("Volume Name") })?
           .components(separatedBy: ":")
           .last?
           .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return name
        }
        // Fallback: diskutil info / may fail on some Ventura/Hackintosh configurations
        // (e.g. file is empty or command outputs an error). Use Foundation URL resource
        // values to read the volume name directly — this always works.
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]),
           let name = values.volumeName, !name.isEmpty
        {
            print("HCStartupDisk: diskutil fallback — using Foundation volume name: \(name)")
            return name
        }
        print("Error: Failed to read startup disk name from both diskutil and Foundation")
        return ""
    }()

    func getStartupDisk() -> String {
        startupDisk
    }

    func getStartupDiskInfo() -> String {
        guard !startupDisk.isEmpty else { return "" }
        guard let content = HardwareCollector.shared.getCachedFileContent(InitGlobVar.storagedataFilePath) else {
            print("Error: Failed to read detailed startup disk info from HardwareCollector cache")
            return ""
        }

        return content.components(separatedBy: .newlines)
            .drop { !$0.contains(startupDisk) && !$0.contains("Mount Point: /") }
            .prefix { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
