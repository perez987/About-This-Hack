//
//  HCCPU.swift
//  About This Hack
//

import Foundation

final class HCCPU: @unchecked Sendable {
    static let shared = HCCPU()
    private init() {}

    private lazy var cpuInfo: (brand: String, coreCount: Int, isAppleSilicon: Bool) = {
        let brand = getSysctlValueByKey(inputKey: "machdep.cpu.brand_string")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown CPU"
        let isAppleSilicon = brand.hasPrefix("Apple")
        let coreCount = isAppleSilicon ? getAppleSiliconCoreCount() : getCPUCoreCount()
        return (brand, coreCount, isAppleSilicon)
    }()

    func getCPU() -> String {
        // Use cached core count from cpuInfo instead of calling getCPUCoreCount() again
        let cpuCoreCount = cpuInfo.coreCount
        let modifiedBrand = cpuInfo.brand.replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: "")
        let hasValidCoreCount = cpuCoreCount > 0

        if cpuInfo.isAppleSilicon, hasValidCoreCount {
            return "\(modifiedBrand) (\(cpuCoreCount) cores)"
        }

        if cpuCoreCount >= 2 {
            return "\(cpuCoreCount)x \(modifiedBrand)"
        } else {
            return modifiedBrand
        }
    }

    func getCPUInfo() -> String {
        getCPUDetails(isAppleSilicon: cpuInfo.isAppleSilicon, coreCount: cpuInfo.coreCount)
    }

    func getCPUCoreCount() -> Int {
        var count: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        let result = sysctlbyname("hw.packages", &count, &size, nil, 0)

        if result == 0, count > 0 {
            return Int(count)
        } else {
            print("Warning: Failed to get physical CPU count via hw.packages: \(String(cString: strerror(errno)))")
            // Core/thread counts are not socket counts; don't invent an Nx label.
            return 1
        }
    }

    private func getAppleSiliconCoreCount() -> Int {
        var count: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        if sysctlbyname("hw.physicalcpu", &count, &size, nil, 0) == 0 {
            return Int(count)
        }
        return getCPUCoreCount()
    }

    private func getCPUDetails(isAppleSilicon: Bool, coreCount: Int) -> String {
        if isAppleSilicon {
            return coreCount > 0 ? String(format: NSLocalizedString("cpu.total_cores", comment: ""), coreCount) : NSLocalizedString("cpu.total_cores_unknown", comment: "")
        }

        guard let content = HardwareCollector.shared.getCachedFileContent(InitGlobVar.hwFilePath) else {
            print("Error: Unable to read CPU details from \(InitGlobVar.hwFilePath)")
            return "Unable to read CPU details"
        }

        // Intel reports "Processor Name:"; Apple Silicon reports "Chip:".

        return content.components(separatedBy: .newlines)
            .drop { line in
                !line.contains("Processor Name:") && !line.contains("Chip:")
            }.prefix { !$0.contains("Memory:") }
            .joined(separator: "\n")
    }
}
