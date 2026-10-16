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

        let lines = content.components(separatedBy: .newlines)
        var chipset = "", vram = "", metal = ""
        // Fallback: the GPU section header line (e.g., "    AMD Radeon RX 580:")
        var gpuSectionHeader = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Capture the first GPU section header (4-space indent, ends with ":")
            // as a fallback name in case "Chipset Model:" is absent.
            if gpuSectionHeader.isEmpty,
               line.hasPrefix("    "), !line.hasPrefix("     "),
               trimmed.hasSuffix(":"), trimmed.count > 1
            {
                let headerName = String(trimmed.dropLast())
                    .replacingOccurrences(of: "Intel ", with: "")
                    .replacingOccurrences(of: "NVIDIA ", with: "")
                    .replacingOccurrences(of: "AMD ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !headerName.isEmpty {
                    gpuSectionHeader = headerName
                }
            }

            if chipset.isEmpty, trimmed.hasPrefix("Chipset Model:") {
                let value = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    chipset = value.replacingOccurrences(of: "Intel ", with: "")
                        .replacingOccurrences(of: "NVIDIA ", with: "")
                        .replacingOccurrences(of: "AMD ", with: "")
                }
            } else if vram.isEmpty, trimmed.hasPrefix("VRAM") {
                let value = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    vram = value
                }
            } else if metal.isEmpty, trimmed.hasPrefix("Metal Support:") {
                let value = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    metal = value
                }
            }

            // Stop when we hit the Displays section
            if trimmed == "Displays:" {
                break
            }
        }

        // If "Chipset Model:" was not found, fall back to the GPU section header.
        if chipset.isEmpty {
            chipset = gpuSectionHeader
        }

        // Build result based on what we found
        var result = chipset
        if !vram.isEmpty {
            result += " \(vram)"
        }
        if !metal.isEmpty {
            result += " (\(metal))"
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    func getGPU() -> String {
        gpuInfo
    }

    // MARK: - Native summary (adapted from upstream commit 064d609)

    private var _nativeGPU: String??
    private let nativeGPULock = NSLock()

    /// Primary GPU from Metal and the I/O Registry, e.g. "Apple M4 Pro (20-Core, Metal 4)"
    /// or "AMD Radeon RX 580 (8 GB, Metal 3)". Available instantly, so the Overview
    /// shows its final value without waiting for `system_profiler SPDisplaysDataType`.
    /// Returns nil when Metal reports no GPU; callers then fall back to `getGPU()`.
    func getNativeGPU() -> String? {
        nativeGPULock.lock()
        defer { nativeGPULock.unlock() }

        if let cached = _nativeGPU {
            return cached
        }

        // High-performance internal GPUs first, then eGPUs, then integrated ones.
        // MTLCopyAllDevices does not force a GPU switch on dual-GPU MacBook Pros.
        let rank: (any MTLDevice) -> Int = { $0.isLowPower ? 2 : ($0.isRemovable ? 1 : 0) }
        let computed = MTLCopyAllDevices()
            .sorted { rank($0) < rank($1) }
            .first
            .map { (device: any MTLDevice) -> String in
                let vram = device.hasUnifiedMemory ? "" : dedicatedMemory(of: device)
                let cores = registryInt("gpu-core-count", registryID: device.registryID).map { "\($0)-Core" } ?? ""
                let details = [vram, cores, metalVersion(of: device)].filter { !$0.isEmpty }
                return details.isEmpty ? device.name : "\(device.name) (\(details.joined(separator: ", ")))"
            }
        _nativeGPU = .some(computed)
        return computed
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
