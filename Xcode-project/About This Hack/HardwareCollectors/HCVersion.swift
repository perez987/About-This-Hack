//
//  HCVersion.swift
//  About This Hack
//

import Darwin
import Foundation

class HCVersion {
    nonisolated(unsafe) static let shared = HCVersion()
    private init() {}

    var osNumber: String = ""
    var osVersion: MacOSVersion = .unknown
    var osName: String = ""
    var osBuildNumber: String = ""
    var osPrefix: String = "macOS"
    var dataHasBeenSet: Bool = false

    func getVersion() {
        guard !dataHasBeenSet else { return }

        osPrefix = "macOS"
        osNumber = getOSNumber()
        osBuildNumber = getOSBuild()
        setOSVersion(osNumber: osNumber)
        osName = macOSVersionToString()
        dataHasBeenSet = true
    }

    private func getOSNumber() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        var versionString = ""
        if osVersion.patchVersion == 0 {
            versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        } else {
            versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        }
        return versionString
    }

    private func getOSBuild() -> String {
        getSysctlValueByKey(inputKey: "kern.osversion") ?? ""
    }

    private func setOSVersion(osNumber: String) {
        switch osNumber.prefix(2) {
        case "27": osVersion = .goldengate
        case "26": osVersion = .tahoe
        case "15": osVersion = .sequoia
        case "14": osVersion = .sonoma
        case "13": osVersion = .ventura
        case "12": osVersion = .monterey
        case "11": osVersion = .bigSur
        case "10": osVersion = osNumber.prefix(5) == "10.16" ? .bigSur : .unknown
        default: osVersion = .unknown
        }
    }

    private func macOSVersionToString() -> String {
        switch osVersion {
        case .bigSur: "Big Sur"
        case .monterey: "Monterey"
        case .ventura: "Ventura"
        case .sonoma: "Sonoma"
        case .sequoia: "Sequoia"
        case .tahoe: "Tahoe"
        case .goldengate: "Golden Gate"
        case .unknown: ""
        }
    }

    func getOSBuildInfo() -> String {
        let kernelVersion = getKernelVersion()
        let sipInfo = getSIPInfo()
        let oclpInfo = getOCLPInfo()

        return [kernelVersion, sipInfo, oclpInfo]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func getKernelVersion() -> String {
        var size = 0
        sysctlbyname("kern.version", nil, &size, nil, 0)
        var kernel = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.version", &kernel, &size, nil, 0)
        let trimmed = kernel.prefix(while: { $0 != 0 }).map(UInt8.init)
        return String(decoding: trimmed, as: UTF8.self)
    }

    private func getSIPInfo() -> String {
        let csrConfig = csrActiveConfig()
        let sipStatus = (csrConfig == 0) ? "Enabled" : "Disabled"

        // If Enabled, Apple Silicon may display only "Enabled", hex value is missing
        // If Disabled, both platforms Intel and Silicon display "sipStatus + hex value"
        var sipValue = ""

        if sipStatus == "Enabled" {
            sipValue = "System Integrity Protection: \(sipStatus) (0x00000000)"
        } else {
            sipValue = "System Integrity Protection: \(sipStatus) (0x\(String(format: "%08x", csrConfig)))"
        }
        return sipValue
    }

    private func csrActiveConfig() -> UInt32 {
        // libSystem.dylib is always loaded in every macOS process, so RTLD_DEFAULT
        // reliably resolves csr_get_active_config without needing an explicit dlopen.
        typealias CSRGetActiveConfig = @convention(c) (UnsafeMutablePointer<UInt32>) -> Int32
        guard let symbol = dlsym(RTLD_DEFAULT, "csr_get_active_config") else {
            return 0
        }

        var config: UInt32 = 0
        let status = unsafeBitCast(symbol, to: CSRGetActiveConfig.self)(&config)
        return status == 0 ? config : 0
    }

    func getOSImageName() -> String {
        switch osVersion {
        case .bigSur: "Big Sur"
        case .monterey: "Monterey"
        case .ventura: "Ventura"
        case .sonoma: "Sonoma"
        case .sequoia: "Sequoia"
        case .tahoe: "Tahoe"
        case .goldengate: "Golden Gate"
        case .unknown: "Unknown"
        }
    }

    private func getOCLPInfo() -> String {
        guard let xmlString = HardwareCollector.shared.getCachedFileContent(InitGlobVar.oclpXmlFilePath) else {
            return ""
        }

        let version = xmlString.captureGroup(for: "<key>OpenCore Legacy Patcher</key>\\s*<string>([^<]+)</string>") ?? ""
        let commit = xmlString.captureGroup(for: "<key>Commit URL</key>\\s*<string>[^/]+/([^<]+)</string>")?.split(separator: "/").last?.prefix(7) ?? ""
        let date = xmlString.captureGroup(for: "<key>Time Patched</key>\\s*<string>([^<]+)</string>")?.replacingOccurrences(of: "@", with: "") ?? ""

        if !version.isEmpty {
            return "OCLP \(version) (\(commit)) (\(date))"
        }

        return ""
    }
}

extension String {
    func captureGroup(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self)
        else {
            return nil
        }
        return String(self[range])
    }
}

enum MacOSVersion {
    case bigSur, monterey, ventura, sonoma, sequoia, tahoe, goldengate, unknown
}
