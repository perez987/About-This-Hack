//
//  HCDisplay.swift
//  About This Hack
//

import Foundation

final class HCDisplay: @unchecked Sendable {
    static let shared = HCDisplay()
    private init() {}

    private var _displayInfo: (mainDisplay: String, allDisplays: String)?
    private let displayLock = NSLock()

    private var displayInfo: (mainDisplay: String, allDisplays: String) {
        displayLock.lock()
        defer { displayLock.unlock() }

        if let cached = _displayInfo {
            return cached
        }

        let computed = computeDisplayInfo()
        _displayInfo = computed
        return computed
    }

    func reset() {
        displayLock.lock()
        defer { displayLock.unlock() }
        _displayInfo = nil
    }

    private func computeDisplayInfo() -> (mainDisplay: String, allDisplays: String) {
        // Use cached data from HardwareCollector instead of file I/O
        guard let content = HardwareCollector.shared.getCachedFileContent(InitGlobVar.scrFilePath) else {
            print("Error: No display data available from HardwareCollector")
            return ("Unknown Display", "No display information available")
        }

        let lines = content.components(separatedBy: .newlines)

        // Collect display lines from ALL "Displays:" sections so that AirPlay and
        // Sidecar entries (which appear under their own virtual-GPU section in
        // system_profiler output) are included alongside the built-in display.
        var allDisplayLines: [String] = []
        var firstDisplayLines: [String] = []
        var firstSectionDone = false
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "Displays:" {
                // Record the indentation of this "Displays:" line so we know where
                // the block ends, regardless of how deeply it is nested.
                let displaysIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                i += 1

                var sectionLines: [String] = []
                while i < lines.count {
                    let inner = lines[i]
                    let innerTrimmed = inner.trimmingCharacters(in: .whitespaces)

                    if innerTrimmed.isEmpty {
                        i += 1
                        continue
                    }

                    let indent = inner.prefix(while: { $0 == " " || $0 == "\t" }).count
                    if indent <= displaysIndent {
                        break
                    }

                    sectionLines.append(inner)
                    i += 1
                }

                if !sectionLines.isEmpty {
                    allDisplayLines.append(contentsOf: sectionLines)
                    if !firstSectionDone {
                        firstDisplayLines = sectionLines
                        firstSectionDone = true
                    }
                }
                continue
            }

            i += 1
        }

        guard !firstDisplayLines.isEmpty else {
            print("Error: Displays section not found in cached data")
            return ("Unknown Display", "No display information available")
        }

        let mainDisplay = getMainDisplayInfo(from: firstDisplayLines)
        let allDisplays = getAllDisplaysInfo(from: allDisplayLines)

        return (mainDisplay, allDisplays)
    }

    func getDisp() -> String {
        displayInfo.mainDisplay
    }

    func getDispInfo() -> String {
        displayInfo.allDisplays
    }

    private func cleanLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }

    private func extractDimensions(from fieldValue: String) -> String {
        var value = fieldValue
            .components(separatedBy: "(").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if let atRange = value.range(of: #"\s*@\s*[\d.]+ ?Hz"#, options: .regularExpression) {
            value = String(value[..<atRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    private func getMainDisplayInfo(from lines: [String]) -> String {
        var displayName = "Unknown Display"
        var resolution = "Unknown Resolution"

        guard let firstDisplayIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(":") && !trimmed.contains(": ")
        }) else {
            return "\(displayName) (\(resolution))"
        }

        displayName = String(lines[firstDisplayIndex].trimmingCharacters(in: .whitespaces).dropLast())

        for i in (firstDisplayIndex + 1) ..< lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":"), !trimmed.contains("Resolution:") {
                break
            }
            if trimmed.contains("Resolution:"), let resRange = trimmed.range(of: "Resolution:") {
                let resValue = extractDimensions(from: String(trimmed[resRange.upperBound...]))
                var scaledResolution: String?
                let maxResolutionLookAhead = 6 // The "UI Looks like:" field is expected within 6 lines after "Resolution:" in the same display block.
                for lookAheadIndex in (i + 1) ..< min(i + maxResolutionLookAhead, lines.count) {
                    let nextTrimmed = lines[lookAheadIndex].trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.contains("Resolution:") || nextTrimmed.hasSuffix(":"),
                       !nextTrimmed.contains("UI Looks like:")
                    {
                        break
                    }
                    if nextTrimmed.contains("UI Looks like:"),
                       let uiRange = nextTrimmed.range(of: "UI Looks like:")
                    {
                        let uiValue = extractDimensions(from: String(nextTrimmed[uiRange.upperBound...]))
                        if !uiValue.isEmpty {
                            scaledResolution = uiValue
                        }
                        break
                    }
                }
                let finalResolution = scaledResolution ?? resValue
                if !finalResolution.isEmpty {
                    resolution = finalResolution
                }
                break
            }
        }

        return "\(displayName) (\(resolution))"
    }

    private func getAllDisplaysInfo(from lines: [String]) -> String {
        var result = ""
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasSuffix(":") {
                if !currentSection.isEmpty {
                    result += currentSection + "\n"
                }
                currentSection = "\n" + line
            } else if !trimmed.isEmpty {
                currentSection += "\n" + line
            }
        }

        if !currentSection.isEmpty {
            result += currentSection
        }

        return result.trimmingCharacters(in: .newlines)
    }
}
