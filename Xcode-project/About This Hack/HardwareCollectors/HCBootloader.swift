//
//  HCBootloader.swift
//  About This Hack
//

import Foundation
import IOKit

final class HCBootloader: @unchecked Sendable {
    static let shared = HCBootloader()
    private init() {}

    private lazy var bootloaderInfo: String = {
        // Prioritize Apple Silicon check
        if (getSysctlValueByKey(inputKey: "machdep.cpu.brand_string") ?? "").contains("Apple") {
            return "Apple iBoot"
        }

        // Check for OpenCore via NVRAM.
        // Primary: read directly from IORegistry (reliable in sandboxed apps on all macOS versions).
        // Fallback: use the nvram CLI via shell in case IOKit access fails.
        let ocKey = InitGlobVar.nvramOpencoreVersion

        if let nvramValue = readNVRAMString(key: ocKey),
           let parsed = parseOpenCoreVersion(nvramValue)
        {
            return parsed
        }

        // Shell-based fallback: split by tab; fewer than 2 parts means nvram returned an
        // error or empty output, so we fall through to the Clover check below.
        let nvramOutput = run("nvram \(ocKey) 2>/dev/null")
        let nvramParts = nvramOutput.components(separatedBy: "\t")
        if nvramParts.count >= 2 {
            let versionPart = nvramParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = parseOpenCoreVersion(versionPart) {
                return parsed
            }
        }

        // Check for OpenCore via IORegistry property enumeration.
        // This catches systems where opencore-version is absent (e.g. ExposeSensitiveData
        // not exposing it) but other OpenCore GUID-namespaced NVRAM variables are present.
        if let ocFromRegistry = findOpenCoreInRegistry() {
            return ocFromRegistry
        }

        // Check for OpenCore via full NVRAM dump.
        // nvram -p prints all variables; scanning for the OC GUID catches opencore-version
        // even when the direct key lookup above failed (e.g. stdout-pollution bug on
        // newer macOS), and also detects OpenCore when the version variable is absent.
        if let ocFromNvramAll = detectOpenCoreViaFullNvramDump() {
            return ocFromNvramAll
        }

        // Check for Clover using cached file content
        if let hwContent = HardwareCollector.shared.getCachedFileContent(InitGlobVar.hwFilePath) {
            let cloverLine = hwContent.components(separatedBy: .newlines)
                .first { $0.contains("Clover") }

            if let line = cloverLine,
               let colonIndex = line.firstIndex(of: ":")
            {
                let version = String(line[line.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !version.isEmpty {
                    return "Clover \(version)"
                }
            }
        }

        // Sandbox-safe OpenCore fallback: detect VirtualSMC in the IOKit service registry.
        // VirtualSMC is OpenCore's SMC emulator. Unlike nvram/IODeviceTree:/options (blocked
        // by the app sandbox), reading general IOKit service nodes is allowed — the same
        // mechanism HCAudio uses successfully with `ioreg -c IOHDACodecDevice`.
        // Real Macs use AppleSMC; Clover uses FakeSMC; OpenCore uses VirtualSMC.
        if detectOpenCoreViaVirtualSMC() {
            return "OpenCore"
        }

        // Fallback
        return "Apple UEFI"
    }()

    // MARK: - Helpers

    /// Reads a string value from NVRAM via IOKit, which is more reliable than the nvram CLI.
    private func readNVRAMString(key: String) -> String? {
        let options = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/options")
        guard options != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(options) }

        guard let value = IORegistryEntryCreateCFProperty(
            options, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return nil
        }

        let raw: String?
        if let str = value as? String {
            raw = str
        } else if let data = value as? Data {
            raw = String(data: data, encoding: .utf8)
        } else {
            return nil
        }

        return raw?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses an OpenCore NVRAM version string (e.g. "REL-100-2024-12-27") into a
    /// human-readable label such as "OpenCore 100-2024-12-27 (Release)".
    private func parseOpenCoreVersion(_ rawValue: String) -> String? {
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let parts = cleaned.split(separator: "-", maxSplits: 1)
        guard parts.count >= 2 else { return nil }

        let buildType = String(parts[0])
        let version = String(parts[1])
            .replacingOccurrences(of: " ", with: ".")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let formattedBuildType: String = switch buildType {
        case "REL": "(Release)"
        case "DEB": "(Debug)"
        default: buildType.isEmpty ? "" : "(\(buildType))"
        }

        return "OpenCore \(version) \(formattedBuildType)".trimmingCharacters(in: .whitespaces)
    }

    /// Enumerates all properties in IODeviceTree:/options and looks for any key containing
    /// the OpenCore GUID namespace.  This catches systems where `opencore-version` is absent
    /// (e.g. ExposeSensitiveData does not have bit 0 set) but other OC NVRAM variables exist.
    /// Returns a formatted "OpenCore …" string (with version when available) or nil.
    private func findOpenCoreInRegistry() -> String? {
        let options = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/options")
        guard options != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(options) }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(options, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propertiesRef?.takeRetainedValue() as NSDictionary?
        else { return nil }

        let ocGUID = "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102"

        // Try to extract version from opencore-version if present under any key form.
        for key in props.allKeys {
            guard let keyStr = key as? String, keyStr.contains("opencore-version") else { continue }
            let raw: String? = if let str = props[key] as? String {
                str
            } else if let data = props[key] as? Data {
                String(data: data, encoding: .utf8)
            } else {
                nil
            }
            if let v = raw?.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
               let parsed = parseOpenCoreVersion(v)
            {
                return parsed
            }
        }

        // If no version variable found, check whether any OC GUID key exists at all.
        let hasOCKey = props.allKeys.contains { ($0 as? String)?.contains(ocGUID) == true }
        return hasOCKey ? "OpenCore" : nil
    }

    /// Runs `nvram -p` to dump every NVRAM variable and searches the output for the OpenCore
    /// GUID namespace.  This catches cases where IOKit access is restricted and the direct
    /// `nvram <key>` lookup was also unsuccessful.
    /// Returns a formatted "OpenCore …" string (with version when available) or nil.
    private func detectOpenCoreViaFullNvramDump() -> String? {
        let output = run("nvram -p 2>/dev/null")
        guard !output.isEmpty else { return nil }

        let ocGUID = "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102"
        guard output.contains(ocGUID) else { return nil }

        // Attempt to extract the version from the opencore-version line.
        for line in output.components(separatedBy: .newlines) where line.contains("opencore-version") {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 2 {
                let versionPart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = parseOpenCoreVersion(versionPart) {
                    return parsed
                }
            }
        }

        // OC GUID found but version unavailable.
        return "OpenCore"
    }

    /// Detects OpenCore by looking up VirtualSMC — OpenCore's IOKit-registered SMC emulator —
    /// in the IOKit service registry.  This method never touches NVRAM (IODeviceTree:/options)
    /// and is therefore compatible with the macOS app sandbox, unlike the nvram-based checks.
    ///
    /// Detection hierarchy:
    ///  1. Direct IOKit service match: `IOServiceGetMatchingService` for "VirtualSMC"
    ///  2. Shell fallback: `ioreg -p IOService -n VirtualSMC -r` (same non-NVRAM IOKit path, sandboxed subprocess)
    ///
    /// Real Macs use AppleSMC; Clover-based Hackintoshes use FakeSMC; OpenCore uses VirtualSMC.
    private func detectOpenCoreViaVirtualSMC() -> Bool {
        // Primary: direct IOKit lookup in the Swift process — fast, no subprocess.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("VirtualSMC"))
        if service != IO_OBJECT_NULL {
            IOObjectRelease(service)
            return true
        }

        // Fallback: ioreg subprocess restricted to an actual IOService node named
        // VirtualSMC. `ioreg -c VirtualSMC` can return class metadata on real Macs
        // and produce false positives; `-p IOService -n VirtualSMC -r` only returns
        // a concrete service instance.
        let ioregsOutput = run("ioreg -p IOService -n VirtualSMC -r -d 1 2>/dev/null")
        if ioregsOutput.contains("\"VirtualSMC\"") {
            return true
        }

        return false
    }

    private lazy var bootargsInfo: String = {
        // Primary: read boot-args directly from IORegistry
        if let bootargs = readNVRAMString(key: "boot-args"), !bootargs.isEmpty {
            return bootargs
        }

        // Shell-based fallback (plist format)
        var bootargs = run("nvram -x boot-args 2>/dev/null | grep -A1 \"<key>boot-args</key>\" | tail -1 | awk -F \"<string>\" '{print $NF}' | awk -F \"<\\/string>\" '{print $1}'  | tr -d '\n'")

        if bootargs.isEmpty {
            bootargs = run("\(InitGlobVar.bdmesgExecID) 2>/dev/null | grep ' boot-args=' | tail -1 | awk -F ' boot-args=' '{print $NF}' | tr -d '\n'")
        }

        return bootargs.isEmpty ? "⎯" : bootargs
    }()

    func getBootloader() -> String {
        bootloaderInfo.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func getBootargs() -> String {
        bootargsInfo
    }
}
