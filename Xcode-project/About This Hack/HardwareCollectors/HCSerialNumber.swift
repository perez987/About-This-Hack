//
//  HCSerialNumber.swift
//  About This Hack
//

import Foundation

class HCSerialNumber {
    nonisolated(unsafe) static let shared = HCSerialNumber()
    private init() {}

    private lazy var HardwareInfo: (serialNumber: String, details: String) = {
        // Use cached data from HardwareCollector; fall back to running the command
        // directly in case the temp file was not written or was empty at prefetch time.
        // IMPORTANT: this lazy var is pre-warmed by HardwareCollector.getAllData() on a
        // background thread before isDataLoaded is set to true, so the run() fallback
        // below always executes on the background thread.  Do not call getSerialNumber()
        // or getHardwareInfo() before getAllData() pre-warming completes.
        let content: String
        if let cached = HardwareCollector.shared.getCachedFileContent(InitGlobVar.hwFilePath) {
            content = cached
        } else {
            let direct = run("system_profiler SPHardwareDataType 2>/dev/null")
            guard !direct.isEmpty else {
                print("Error: No hardware info available from HardwareCollector for serial number")
                return ("", "")
            }
            // Populate the cache so subsequent callers (e.g. HCBootloader Clover check) benefit.
            HardwareCollector.shared.storeCachedFileContent(InitGlobVar.hwFilePath, content: direct)
            content = direct
        }

        let lines = content.components(separatedBy: .newlines)

        let serialNumber = lines.first { $0.contains("Serial") }?
            .components(separatedBy: .whitespaces)
            .last ?? ""

        let relevantKeys = [
            "System Firmware Version", "OS Loader Version", "SMC Version",
            "Apple ROM Info:", "Board-ID :", "Hardware UUID:", "Provisioning UDID:",
        ]

        let formattedDetails = lines
            .filter { line in relevantKeys.contains { line.contains($0) } }
            .map { "      " + $0.trimmingCharacters(in: .whitespaces) }
            .map { line in
                line.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .joined(separator: "\n")

        return (serialNumber, formattedDetails)
    }()

    func getSerialNumber() -> String {
        HardwareInfo.serialNumber
    }

    func getHardwareInfo() -> String {
        HardwareInfo.details
    }
}
