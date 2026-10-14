//
//  HardwareCollector.swift
//  HardwareCollector
//

import AppKit
import Foundation

class HardwareCollector {
    nonisolated(unsafe) static let shared = HardwareCollector()
    private init() {}

    private struct DisplaySnapshot {
        let name: String
        let resolution: String
        let refreshRate: String
    }

    // File content cache
    private var fileContentCache: [String: String] = [:]
    private let cacheLock = NSLock()

    // Thread-safe flag for getAllData()
    private var _dataHasBeenSet = false
    private let dataInitLock = NSLock()
    var dataHasBeenSet: Bool {
        get {
            dataInitLock.lock()
            defer { dataInitLock.unlock() }
            return _dataHasBeenSet
        }
        set {
            dataInitLock.lock()
            defer { dataInitLock.unlock() }
            _dataHasBeenSet = newValue
        }
    }

    var numberOfDisplays = NSScreen.screens.count
    var displayRes: [String] = []
    var displayRefreshRates: [String] = []
    var displayNames: [String] = []
    var storageType = false
    var storageData = ""
    var storagePercent = 0.0
    var deviceLocation = ""
    var deviceProtocol = ""
    var hasBuiltInDisplay = false

    func getCachedFileContent(_ path: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = fileContentCache[path] {
            return cached
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty else {
            return nil
        }

        fileContentCache[path] = content
        return content
    }

    /// Store content directly into the file cache under the given path key.
    /// Used as a fallback to populate the cache from a freshly-run command
    /// when the corresponding on-disk file was not written in time.
    func storeCachedFileContent(_ path: String, content: String) {
        guard !content.isEmpty else { return }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        fileContentCache[path] = content
    }

    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        fileContentCache.removeAll()

        // Reset lazy properties in hardware collectors
        HCGPU.shared.reset()
        HCDisplay.shared.reset()
    }

    func getAllData() {
        guard !dataHasBeenSet else { return }

        // Clear cache to ensure we read fresh data files
        clearCache()

        // Prefetch commonly used files first
        let commonFiles = [
            InitGlobVar.hwFilePath,
            InitGlobVar.bootvolnameFilePath,
            InitGlobVar.storagedataFilePath,
            InitGlobVar.sysmemFilePath,
            InitGlobVar.bootvollistFilePath,
            InitGlobVar.oclpXmlFilePath,
        ]

        for path in commonFiles {
            _ = getCachedFileContent(path)
        }

        // Run system_profiler SPDisplaysDataType directly (no intermediate file) and
        // populate the cache so that all GPU/display lookups via getCachedFileContent
        // find the data without touching the file system.
        let scrContent = run("system_profiler SPDisplaysDataType 2>/dev/null")
        if !scrContent.isEmpty {
            storeCachedFileContent(InitGlobVar.scrFilePath, content: scrContent)
        }

        // Initialize all hardware collectors in a specific order
        HCVersion.shared.getVersion()
        HCMacModel.shared.getMacModel()
        _ = HCCPU.shared.getCPU()
        _ = HCRAM.shared.getRam()
        _ = HCStartupDisk.shared.getStartupDisk()
        _ = HCDisplay.shared.getDisp()
        _ = HCGPU.shared.getGPU()

        // Initialize display and storage info
        hasBuiltInDisplay = checkForBuiltInDisplay()
        displayRes = getDisplayRes()
        displayRefreshRates = getDisplayRefreshRates()
        displayNames = getDisplayNames()
        // Use whichever source reports more displays.  system_profiler is preferred
        // because it includes AirPlay / Sidecar displays that were not always present
        // in NSScreen.screens on older macOS releases, but on macOS 15+ NSScreen also
        // lists them.  Taking the max ensures neither source causes a display to be
        // silently dropped.
        numberOfDisplays = max(displayNames.isEmpty ? 0 : displayNames.count, NSScreen.screens.count)
        (storageType, storageData, storagePercent) = getStorageInfo()

        // Pre-warm HCSerialNumber on the background thread.  Its lazy var reads
        // hwFilePath from the cache; doing this here guarantees that the cache is
        // already populated and that the lazy var is never initialized from the main
        // thread where a cache miss would silently result in an empty serial number.
        _ = HCSerialNumber.shared.getSerialNumber()

        // Pre-warm HCBootloader lazy vars here on the background thread so that
        // their internal run() calls never execute on the main thread.  Without
        // this pre-warming, the lazy vars are initialized on first access inside
        // OverviewViewModel.init(), which is invoked during a SwiftUI body-
        // evaluation pass on the main thread.  run() calls task.waitUntilExit(),
        // which pumps the run loop, allowing a pending task(id:) continuation to
        // write @State while SwiftUI is still in its render pass, triggering
        // "precondition failure: setting value during update: 536" → SIGABRT.
        _ = HCBootloader.shared.getBootloader()
        _ = HCBootloader.shared.getBootargs()

        // Pre-warm HCAudio on the background thread for the same reasons.
        _ = HCAudio.shared.getAudioInfo()

        dataHasBeenSet = true
    }

    func refreshDisplayData() {
        let scrContent = run("system_profiler SPDisplaysDataType 2>/dev/null")
        guard !scrContent.isEmpty else { return }

        storeCachedFileContent(InitGlobVar.scrFilePath, content: scrContent)
        HCDisplay.shared.reset()
        HCGPU.shared.reset()

        hasBuiltInDisplay = checkForBuiltInDisplay()
        displayNames = getDisplayNames()
        displayRes = getDisplayRes()
        displayRefreshRates = getDisplayRefreshRates()
        numberOfDisplays = max(displayNames.isEmpty ? 0 : displayNames.count, NSScreen.screens.count)
    }

    /// Extracts the pixel-dimensions portion from a resolution field value string,
    /// stripping any trailing "(…)" parenthesised annotations and "@ XX Hz" refresh-rate suffix.
    private func extractDimensions(from fieldValue: String) -> String {
        var value = fieldValue
            .components(separatedBy: "(").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if let atRange = value.range(of: #"\s*@\s*[\d.]+ ?Hz"#, options: .regularExpression) {
            value = String(value[..<atRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    private func getDisplayRes() -> [String] {
        getDisplaySnapshots().map(\.resolution)
    }

    private func getDisplayRefreshRates() -> [String] {
        getDisplaySnapshots().map(\.refreshRate)
    }

    private func getDisplayNames() -> [String] {
        getDisplaySnapshots().map(\.name)
    }

    private func checkForBuiltInDisplay() -> Bool {
        guard let content = getCachedFileContent(InitGlobVar.scrFilePath) else { return false }
        let lower = content.lowercased()
        return lower.contains("connection type: internal") || lower.contains("display type: built-in")
    }

    private func getDisplaySnapshots() -> [DisplaySnapshot] {
        guard let content = getCachedFileContent(InitGlobVar.scrFilePath) else { return [] }

        let lines = content.components(separatedBy: .newlines)
        var snapshots: [DisplaySnapshot] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard trimmed == "Displays:" else {
                i += 1
                continue
            }

            let displaysIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            i += 1

            while i < lines.count {
                let displayLine = lines[i]
                let displayTrimmed = displayLine.trimmingCharacters(in: .whitespaces)

                if displayTrimmed.isEmpty {
                    i += 1
                    continue
                }

                let displayIndent = displayLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                if displayIndent <= displaysIndent {
                    break
                }

                if displayTrimmed.hasSuffix(":"), !displayTrimmed.contains(": ") {
                    let displayName = String(displayTrimmed.dropLast())
                    let blockIndent = displayIndent
                    var blockLines: [String] = []
                    i += 1

                    while i < lines.count {
                        let blockLine = lines[i]
                        let blockTrimmed = blockLine.trimmingCharacters(in: .whitespaces)

                        if blockTrimmed.isEmpty {
                            i += 1
                            continue
                        }

                        let indent = blockLine.prefix(while: { $0 == " " || $0 == "\t" }).count
                        if indent <= blockIndent {
                            break
                        }

                        blockLines.append(blockLine)
                        i += 1
                    }

                    snapshots.append(DisplaySnapshot(
                        name: displayName,
                        resolution: displayResolution(from: blockLines),
                        refreshRate: displayRefreshRate(from: blockLines)
                    ))
                    continue
                }

                i += 1
            }
        }

        return snapshots
    }

    private func displayResolution(from lines: [String]) -> String {
        var resolutionValue = ""
        var scaledResolution = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if resolutionValue.isEmpty,
               let resRange = trimmed.range(of: "Resolution:")
            {
                resolutionValue = extractDimensions(from: String(trimmed[resRange.upperBound...]))
                continue
            }

            if scaledResolution.isEmpty,
               let uiRange = trimmed.range(of: "UI Looks like:")
            {
                scaledResolution = extractDimensions(from: String(trimmed[uiRange.upperBound...]))
            }
        }

        return scaledResolution.isEmpty ? resolutionValue : scaledResolution
    }

    private func displayRefreshRate(from lines: [String]) -> String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            for label in ["Resolution:", "UI Looks like:"] {
                guard let range = trimmed.range(of: label) else { continue }
                let value = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if let match = value.range(of: #"@\s*[\d.]+ ?Hz"#, options: .regularExpression) {
                    let refreshRate = String(value[match])
                        .replacingOccurrences(of: "@", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: #"(\d)Hz"#, with: "$1 Hz", options: .regularExpression)
                    return normalizeRefreshRate(refreshRate)
                }
            }
        }

        return ""
    }

    private func normalizeRefreshRate(_ refreshRate: String) -> String {
        let numeric = refreshRate
            .replacingOccurrences(of: "Hz", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let hz = Double(numeric), hz > 0 else {
            return refreshRate
        }

        return "\(Int(hz.rounded())) Hz"
    }

    private func getStorageInfo() -> (Bool, String, Double) {
        var lines: [String] = []
        var contentStr = ""

        if let content = getCachedFileContent(InitGlobVar.bootvolnameFilePath) {
            contentStr = content
            lines = content.components(separatedBy: .newlines)
            deviceProtocol = lines.first { $0.contains("Protocol:") }?.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " fabric$", with: "", options: [.regularExpression, .caseInsensitive]) ?? "Unknown"
            deviceLocation = lines.first { $0.contains("Device Location:") }?.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
        }

        let isSSd = contentStr.contains("Solid State: Yes")
        let (sizeGB, availableGB) = parseStorageSize(lines)
        let percent = sizeGB > 0 ? availableGB / sizeGB : 0.0
        let percentFree = String(format: "%.2f", percent * 100)

        let storageInfo = """
        \(HCStartupDisk.shared.getStartupDisk()) (\(deviceLocation) \(deviceProtocol))
        \(String(format: "%.2f", sizeGB)) GB (\(String(format: "%.2f", availableGB)) GB \(NSLocalizedString("storage.available", comment: "Available storage label")) - \(percentFree)%)
        """

        return (isSSd, storageInfo, 1 - percent)
    }

    private func parseStorageSize(_ lines: [String]) -> (Double, Double) {
        // On APFS volumes `diskutil info /` reports "Total Space: N/A" and
        // "Free Space: N/A" before the real "Container Total Space:" and
        // "Container Free Space:" lines.  Skip any line whose value is "N/A"
        // so that we fall through to the Container* fields.
        let sizeLine = lines.first { $0.contains("Total Space:") && !$0.contains("N/A") }?.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0 B"
        let availableLine = lines.first { $0.contains("Free Space:") && !$0.contains("N/A") }?.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0 B"

        let (size, sizeUnit) = parseSize(sizeLine)
        let (available, availableUnit) = parseSize(availableLine)

        let sizeGB = convertToGB(size, unit: sizeUnit)
        let availableGB = convertToGB(available, unit: availableUnit)

        // Fallback: diskutil info / may fail on some Hackintosh configurations
        // (e.g. outputting "Could not find disk for /") leaving the parsed values
        // at zero. In that case, use Foundation URL resource values to read
        // disk capacity directly — this always works regardless of diskutil output.
        if sizeGB == 0 {
            return parseStorageSizeFromURL()
        }

        return (sizeGB, availableGB)
    }

    private func parseStorageSizeFromURL() -> (Double, Double) {
        let bytesPerGB: Double = 1_000_000_000
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let totalBytes = values.volumeTotalCapacity,
              totalBytes > 0
        else {
            return (0, 0)
        }
        let availableBytes = values.volumeAvailableCapacity ?? 0
        let sizeGB = Double(totalBytes) / bytesPerGB
        let availableGB = Double(availableBytes) / bytesPerGB
        return (sizeGB, availableGB)
    }

    private func parseSize(_ sizeString: String) -> (Double, String) {
        let components = sizeString.components(separatedBy: .whitespaces)
        guard components.count >= 2, let size = Double(components[0]) else { return (0, "B") }
        return (size, components[1])
    }

    private func convertToGB(_ size: Double, unit: String) -> Double {
        switch unit.uppercased() {
        case "B": size / 1_000_000_000
        case "KB": size / 1_000_000
        case "MB": size / 1000
        case "GB": size
        case "TB": size * 1000
        default: size
        }
    }
}
