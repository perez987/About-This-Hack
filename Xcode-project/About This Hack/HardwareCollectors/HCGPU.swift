//
//  HCGPU.swift
//  About This Hack
//

import Foundation
import IOKit
import Metal

final class HCGPU: @unchecked Sendable {
    static let shared = HCGPU()
    private init() {}

    private var _gpuInfo: String?
    private let gpuLock = NSLock()

    private var gpuInfo: String {
        gpuLock.lock()
        defer { gpuLock.unlock() }

        if let cached = _gpuInfo {
            return cached
        }

        let computed = computeGPUInfo()
        _gpuInfo = computed
        return computed
    }

    func reset() {
        gpuLock.lock()
        defer { gpuLock.unlock() }
        _gpuInfo = nil
    }

    private func computeGPUInfo() -> String {
        // Use cached data from HardwareCollector instead of file I/O
        guard let content = HardwareCollector.shared.getCachedFileContent(InitGlobVar.scrFilePath) else {
            print("No GPU data available from HardwareCollector")
            return ""
        }

        _ = getNativeGPU()
        nativeGPULock.lock()
        let identity = selectedGPUIdentity
        nativeGPULock.unlock()
        return Self.profilerSummary(content, selectedIdentity: identity)
    }

    struct PCIIdentity: Equatable {
        let vendorID: Int
        let deviceID: Int
    }

    /// Keep adapter properties separate; display properties and other GPUs must not supply VRAM.
    static func profilerSummary(_ content: String, selectedIdentity: PCIIdentity?) -> String {
        var sections: [(header: String, fields: [String: String])] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("    "), !line.hasPrefix("     "),
               trimmed.hasSuffix(":"), trimmed.count > 1 {
                sections.append((String(trimmed.dropLast()), [:]))
            } else if !sections.isEmpty,
                      line.hasPrefix("      "), !line.hasPrefix("       "),
                      let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon])
                let value = String(trimmed[trimmed.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    sections[sections.count - 1].fields[key] = value
                }
            }
        }

        func hexID(_ value: String?) -> Int? {
            guard let value, let prefix = value.range(of: "0x", options: .caseInsensitive) else { return nil }
            let digits = value[prefix.upperBound...].prefix { $0.isHexDigit }
            return Int(digits, radix: 16)
        }

        func summary(_ section: (header: String, fields: [String: String])) -> String {
            let fields = section.fields
            var result = (fields["Chipset Model"] ?? section.header)
                .replacingOccurrences(of: "Intel ", with: "")
                .replacingOccurrences(of: "NVIDIA ", with: "")
                .replacingOccurrences(of: "AMD ", with: "")
            if let key = fields.keys.sorted().first(where: { $0.hasPrefix("VRAM") }),
               let vram = fields[key] {
                result += " \(vram)"
            }
            if let metal = fields["Metal Support"] {
                result += " (\(metal))"
            }
            return result.trimmingCharacters(in: .whitespaces)
        }

        if let selectedIdentity {
            let matches = sections.filter {
                hexID($0.fields["Vendor"]) == selectedIdentity.vendorID &&
                    hexID($0.fields["Device ID"]) == selectedIdentity.deviceID
            }
            if matches.count == 1 {
                return summary(matches[0])
            }
        }
        // Without a unique PCI match, don't imply the first adapter is Metal's selected GPU.
        return sections.map(summary).filter { !$0.isEmpty }.joined(separator: "; ")
    }

    func getGPU() -> String {
        gpuInfo
    }

    // MARK: - Native summary (adapted from upstream commit 064d609)

    private var _nativeGPU: String??
    private var selectedGPUIdentity: PCIIdentity?
    private let nativeGPULock = NSLock()

    /// Primary GPU from Metal and the I/O Registry, e.g. "Apple M4 Pro (20-Core, Metal 4)"
    /// or "AMD Radeon RX 580 (8 GB, Metal 3)". Available instantly, so the Overview
    /// shows its final value without waiting for `system_profiler SPDisplaysDataType`.
    /// Returns cached nil when Metal reports no GPU or a blank/Unknown name;
    /// callers then wait for `system_profiler` and fall back to `getGPU()`.
    func getNativeGPU() -> String? {
        nativeGPULock.lock()
        defer { nativeGPULock.unlock() }

        if let cached = _nativeGPU {
            return cached
        }

        // High-performance internal GPUs first, then eGPUs, then integrated ones.
        // MTLCopyAllDevices does not force a GPU switch on dual-GPU MacBook Pros.
        let rank: (any MTLDevice) -> Int = { $0.isLowPower ? 2 : ($0.isRemovable ? 1 : 0) }
        let device = MTLCopyAllDevices()
            .sorted { rank($0) < rank($1) }
            .first
        let computed = device.flatMap { (device: any MTLDevice) -> String? in
            guard Self.nativeSummary(name: device.name, details: []) != nil else {
                if let vendorID = registryInt("vendor-id", registryID: device.registryID),
                   let deviceID = registryInt("device-id", registryID: device.registryID) {
                    selectedGPUIdentity = PCIIdentity(vendorID: vendorID, deviceID: deviceID)
                }
                return nil
            }
            let vram = device.hasUnifiedMemory ? "" : dedicatedMemory(of: device)
            let cores = registryInt("gpu-core-count", registryID: device.registryID).map { "\($0)-Core" } ?? ""
            return Self.nativeSummary(name: device.name, details: [vram, cores, metalVersion(of: device)])
        }
        _nativeGPU = .some(computed)
        return computed
    }

    static func nativeSummary(name: String?, details: [String]) -> String? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.range(of: "Unknown", options: .caseInsensitive) == nil else { return nil }
        let details = details.filter { !$0.isEmpty }
        return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
    }

    private func metalVersion(of device: any MTLDevice) -> String {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *), device.supportsFamily(.metal4) {
                return "Metal 4"
            }
        #endif
        if device.supportsFamily(.metal3) {
            return "Metal 3"
        }
        return device.supportsFamily(.mac2) ? "Metal 2" : "Metal"
    }

    /// Exact VRAM from the GPU's registry entry, falling back to Metal's working-set estimate.
    private func dedicatedMemory(of device: any MTLDevice) -> String {
        if let megabytes = registryInt("VRAM,totalMB", registryID: device.registryID), megabytes > 0 {
            return formatMegabytes(megabytes)
        }
        let bytes = device.recommendedMaxWorkingSetSize
        return bytes > 0 ? formatMegabytes(Int(bytes / 1_048_576)) : ""
    }

    private func registryInt(_ key: String, registryID: UInt64) -> Int? {
        guard let matching = IORegistryEntryIDMatching(registryID) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        let value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault, options)
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let data = value as? Data, data.count <= 8 {
            return data.reversed().reduce(0) { $0 << 8 | Int($1) }
        }
        return nil
    }

    private func formatMegabytes(_ megabytes: Int) -> String {
        megabytes >= 1024
            ? String(format: "%g GB", (Double(megabytes) / 1024 * 10).rounded() / 10)
            : "\(megabytes) MB"
    }

    func getGPUInfo() -> String {
        // Use cached data from HardwareCollector
        guard let content = HardwareCollector.shared.getCachedFileContent(InitGlobVar.scrFilePath) else {
            print("No GPU details available from HardwareCollector")
            return "Graphics\n"
        }

        let filteredLines = content.components(separatedBy: .newlines)
            .filter { !$0.contains("Graphics/Displays:") &&
                !$0.hasPrefix("      Displays:") &&
                !$0.hasPrefix("        ") &&
                !$0.hasPrefix("          ")
            }
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }

        return "Graphics\n" + filteredLines.joined(separator: "\n")
    }
}
