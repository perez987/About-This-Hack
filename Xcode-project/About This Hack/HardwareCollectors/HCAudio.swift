//
//  HCAudio.swift
//  About This Hack
//
//  Collects audio codec information from the IORegistry.
//  Retrieves: codec name, vendor name, PCI device name, and layout ID.
//  For USB audio devices, retrieves product name and manufacturer from system_profiler.
//

import Foundation

// MARK: - Audio Info Model

struct AudioInfo {
    let codecName: String
    let vendorName: String
    let deviceName: String
    let layoutId: String
    let driver: String
    let codecHex: String
    let vendorHex: String
    let deviceHex: String
}

// MARK: - HCAudio Collector

final class HCAudio: @unchecked Sendable {
    static let shared = HCAudio()
    private init() {}

    /// Lazy initialization runs on the background thread via pre-warming in HardwareCollector.getAllData().
    private lazy var _audioInfo: AudioInfo = computeAudioInfo()

    func getAudioInfo() -> AudioInfo {
        _audioInfo
    }

    // MARK: - Compute

    private func computeAudioInfo() -> AudioInfo {
        // 1. USB audio: if the current default output device is connected via USB,
        //    report it directly (product name, manufacturer, transport = "USB").
        //    This check takes priority over AppleALC / VoodooHDA so that users who
        //    have set a USB audio device as their main output see its details.
        if let usbInfo = computeUSBAudioInfo() {
            return usbInfo
        }

        // 1b. HDMI/DisplayPort audio: if the current default output device uses HDMI or DisplayPort transport,
        //     report the output source name and the GPU driving it.
        if let hdmiInfo = computeHDMIAudioInfo() {
            return hdmiInfo
        }

        // 2. Codec data: vendor ID from IOHDACodecDevice (present with AppleALC, absent with VoodooHDA)
        let codecOutput = run("ioreg -l -r -c IOHDACodecDevice -w 0 2>/dev/null")

        // 3. PCI controller data: vendor-id, device-id, layout-id.
        //    Present with both AppleALC and VoodooHDA (HDEF/HDAS node is always there).
        //    Try common ACPI node names used on Hackintoshes and real Macs,
        //    then fall back to the driver class name.
        let nodeNames = ["HDEF", "HDAS", "ALZA", "AZAL"]
        var pciOutput = ""
        for name in nodeNames {
            let out = run("ioreg -l -r -n \(name) -w 0 2>/dev/null")
            if !out.isEmpty {
                pciOutput = out
                break
            }
        }
        if pciOutput.isEmpty {
            pciOutput = run("ioreg -l -r -c AppleHDAController -w 0 2>/dev/null")
        }

        // Parse layout-id and PCI device name from the HDA controller node.
        // These are available regardless of whether AppleALC or VoodooHDA is in use.
        let layoutId = parseLayoutId(from: pciOutput)
        let (pciVendor, pciDevice) = parsePciIds(from: pciOutput)
        let (deviceName, deviceHex) = lookupPciDeviceName(vendorId: pciVendor, deviceId: pciDevice)

        // 4. AppleALC: exposes IOHDACodecDevice nodes → codecOutput is non-empty.
        if !codecOutput.isEmpty {
            let vendorIdInt = parseVendorId(from: codecOutput)
            let (codecName, codecHex) = vendorIdInt > 0 ? lookupCodecName(vendorId: vendorIdInt) : ("", "")
            let (vendorName, vendorHex) = vendorIdInt > 0 ? lookupAudioVendorName(vendorCode: (vendorIdInt >> 16) & 0xFFFF) : ("", "")

            // Fall back to system_profiler only when all fields are empty
            // (unlikely with AppleALC, but covers edge cases).
            if codecName.isEmpty, vendorName.isEmpty, layoutId.isEmpty, deviceName.isEmpty {
                return computeAudioInfoFromSystemProfiler()
            }
            return AudioInfo(
                codecName: codecName,
                vendorName: vendorName,
                deviceName: deviceName,
                layoutId: layoutId,
                driver: "AppleALC",
                codecHex: codecHex,
                vendorHex: vendorHex,
                deviceHex: deviceHex
            )
        }

        // 5. HDAUniversal: does not expose IOHDACodecDevice nodes but creates
        //    an HDAUniversalDevice branch in the IORegistry when active.
        let hdaUniversalOutput = run("ioreg -p IOService -r -w 0 -l -n HDAUniversalDevice 2>/dev/null")
        if !hdaUniversalOutput.isEmpty {
            let hdaUniversalLayoutId = parseHDAUniversalEffectiveLayoutId(from: hdaUniversalOutput)
            let effectiveLayoutId = hdaUniversalLayoutId.isEmpty ? layoutId : hdaUniversalLayoutId
            // Try to read the real codec name from IOAudioDeviceShortName property.
            // Line format:  "IOAudioDeviceShortName" = "ALC1220"
            // Also try to read the codec vendor ID from HDAUniversalEffectiveCodecID
            // (decimal integer, e.g. 283906592 = 0x10EC1220 → vendor 0x10EC = Realtek).
            var hdaCodecName = "HDAUniversal"
            var hdaVendorName = ""
            var hdaVendorHex = ""
            var hdaCodecHex = ""
            let shortNameKey = "\"IOAudioDeviceShortName\""
            let codecIdKey = "\"HDAUniversalEffectiveCodecID\""
            for line in hdaUniversalOutput.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if hdaCodecName == "HDAUniversal", let keyRange = trimmed.range(of: shortNameKey) {
                    let prefix = trimmed[..<keyRange.lowerBound]
                    if prefix.allSatisfy({ $0 == "|" || $0 == "+" || $0 == "-" || $0 == "o" || $0 == " " || $0 == "\t" }),
                       let eqRange = trimmed.range(of: "=")
                    {
                        let trimSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\""))
                        let value = trimmed[eqRange.upperBound...].trimmingCharacters(in: trimSet)
                        if !value.isEmpty { hdaCodecName = value }
                    }
                }
                if trimmed.contains(codecIdKey), let eqRange = trimmed.range(of: "=") {
                    let valueStr = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    // Value is a decimal integer; also accept 0x-prefixed hex just in case.
                    let codecId: UInt32? = if valueStr.lowercased().hasPrefix("0x") {
                        UInt32(valueStr.dropFirst(2), radix: 16)
                    } else {
                        UInt32(valueStr)
                    }
                    if let id = codecId, id > 0 {
                        let vendorCode = (id >> 16) & 0xFFFF
                        let (vName, vHex) = lookupAudioVendorName(vendorCode: vendorCode)
                        hdaVendorName = vName
                        hdaVendorHex = vHex
                        let (_, cHex) = lookupCodecName(vendorId: id)
                        hdaCodecHex = cHex
                    }
                }
            }
            return AudioInfo(
                codecName: hdaCodecName,
                vendorName: hdaVendorName,
                deviceName: deviceName,
                layoutId: effectiveLayoutId,
                driver: "HDAUniversal",
                codecHex: hdaCodecHex,
                vendorHex: hdaVendorHex,
                deviceHex: deviceHex
            )
        }

        // 6. VoodooHDA: does not expose IOHDACodecDevice nodes but registers a
        //    VoodooHDADevice in the IORegistry.  Codec info is obtained via the
        //    `getdump` command-line tool shipped with VoodooHDA.
        let voodooOutput = run("ioreg -l -r -c VoodooHDADevice -w 0 2>/dev/null")
        if !voodooOutput.isEmpty {
            if let getdumpExec = getdumpPath() {
                let dumpOutput = run("\(getdumpExec) 2>/dev/null")
                let vendorIdInt = parseGetdumpCodecId(from: dumpOutput)
                if vendorIdInt > 0 {
                    let (codecName, codecHex) = lookupCodecName(vendorId: vendorIdInt)
                    let (vendorName, vendorHex) = lookupAudioVendorName(vendorCode: (vendorIdInt >> 16) & 0xFFFF)
                    return AudioInfo(
                        codecName: codecName,
                        vendorName: vendorName,
                        deviceName: deviceName,
                        layoutId: layoutId,
                        driver: "VoodooHDA",
                        codecHex: codecHex,
                        vendorHex: vendorHex,
                        deviceHex: deviceHex
                    )
                }
            }
            // VoodooHDA present but getdump not found or returned no usable data.
            // Treat as if audio is not available.
            return emptyAudioInfo
        }

        // 7. No AppleALC, HDAUniversal, or VoodooHDA. Fall back to system_profiler for real Macs
        //    whose audio hardware is not exposed via standard IOHDACodecDevice nodes
        //    (e.g. Intel Smart Sound Technology + CS8409).
        if layoutId.isEmpty, deviceName.isEmpty {
            return computeAudioInfoFromSystemProfiler()
        }

        return emptyAudioInfo
    }

    // MARK: - getdump Helpers

    /// Return the full path of the `getdump` executable, or nil if not found.
    /// getdump is shipped with VoodooHDA and can be installed in /usr/local/bin or
    /// /opt/local/bin (the two most common locations from PKG installers).
    private func getdumpPath() -> String? {
        let knownPaths = ["/usr/local/bin/getdump", "/opt/local/bin/getdump"]
        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        // Also honour PATH in case the user placed it elsewhere.
        let whichResult = run("which getdump 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        return whichResult.isEmpty ? nil : whichResult
    }

    /// Parse the first "HDA Codec ID: 0xXXXXYYYY" line from getdump output and
    /// return the value as a UInt32 (upper 16 bits = vendor, lower 16 bits = model).
    private func parseGetdumpCodecId(from output: String) -> UInt32 {
        for line in output.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("HDA Codec ID:") else { continue }
            let valueStr = String(t.dropFirst("HDA Codec ID:".count)).trimmingCharacters(in: .whitespaces)
            if valueStr.lowercased().hasPrefix("0x") {
                if let value = UInt32(valueStr.dropFirst(2), radix: 16) {
                    return value
                }
            } else if let value = UInt32(valueStr) {
                return value
            }
        }
        return 0
    }

    // MARK: - USB Audio Detection

    /// Checks whether the current default audio output device is connected via USB.
    /// Parses the plain-text output of `system_profiler SPAudioDataType`, splits it
    /// into per-device blocks, and returns an AudioInfo if a device is found that is
    /// marked as the Default Output Device AND has Transport = USB.
    private func computeUSBAudioInfo() -> AudioInfo? {
        let output = run("system_profiler SPAudioDataType 2>/dev/null")
        guard !output.isEmpty else { return nil }

        var currentName = ""
        var props: [String: String] = [:]

        func evaluateDevice() -> AudioInfo? {
            guard !currentName.isEmpty else { return nil }
            let isDefault = (props["Default Output Device"] ?? "").lowercased() == "yes"
            let transport = (props["Transport"] ?? "").trimmingCharacters(in: .whitespaces)
            guard isDefault, transport.lowercased() == "usb" else { return nil }
            let manufacturer = (props["Manufacturer"] ?? "").trimmingCharacters(in: .whitespaces)
            return AudioInfo(
                codecName: currentName,
                vendorName: manufacturer,
                deviceName: "",
                layoutId: "",
                driver: "USB",
                codecHex: "",
                vendorHex: "",
                deviceHex: ""
            )
        }

        for line in output.components(separatedBy: .newlines) {
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Device header lines: indented at the device level (>= 6 spaces), end with
            // ":", and do not contain ": " (which would mark them as property lines).
            if leadingSpaces >= 6, trimmed.hasSuffix(":"), !trimmed.contains(": ") {
                if let result = evaluateDevice() { return result }
                currentName = String(trimmed.dropLast()) // strip trailing ":"
                props = [:]
            } else if !currentName.isEmpty, let colonRange = trimmed.range(of: ": ") {
                let key = String(trimmed[trimmed.startIndex ..< colonRange.lowerBound])
                let value = String(trimmed[colonRange.upperBound...])
                props[key] = value
            }
        }

        // Evaluate the last device block.
        return evaluateDevice()
    }

    // MARK: - HDMI Audio Detection

    /// Checks whether the current default audio output device uses HDMI transport.
    /// Parses the plain-text output of `system_profiler SPAudioDataType`, splits it
    /// into per-device blocks, and returns an AudioInfo if a device is found that is
    /// marked as the Default Output Device AND has Transport = HDMI or DisplayPort.
    /// The product name is taken from the "Output Source" field (falling back to the
    /// device header name), and the GPU name is read from HCGPU.
    private func computeHDMIAudioInfo() -> AudioInfo? {
        let output = run("system_profiler SPAudioDataType 2>/dev/null")
        guard !output.isEmpty else { return nil }

        var currentName = ""
        var props: [String: String] = [:]

        func evaluateDevice() -> AudioInfo? {
            guard !currentName.isEmpty else { return nil }
            let isDefault = (props["Default Output Device"] ?? "").lowercased() == "yes"
            let transport = (props["Transport"] ?? "").trimmingCharacters(in: .whitespaces)
            let transportLower = transport.lowercased()
            guard isDefault, transportLower == "hdmi" || transportLower == "displayport" else { return nil }
            let outputSource = (props["Output Source"] ?? "").trimmingCharacters(in: .whitespaces)
            let productName = outputSource.isEmpty ? currentName : outputSource
            let gpuName = HCGPU.shared.getGPU()
            let driverName = transportLower == "displayport" ? "DisplayPort" : "HDMI"
            return AudioInfo(
                codecName: productName,
                vendorName: gpuName,
                deviceName: "",
                layoutId: "",
                driver: driverName,
                codecHex: "",
                vendorHex: "",
                deviceHex: ""
            )
        }

        for line in output.components(separatedBy: .newlines) {
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Device header lines: indented at the device level (>= 6 spaces), end with
            // ":", and do not contain ": " (which would mark them as property lines).
            if leadingSpaces >= 6, trimmed.hasSuffix(":"), !trimmed.contains(": ") {
                if let result = evaluateDevice() { return result }
                currentName = String(trimmed.dropLast()) // strip trailing ":"
                props = [:]
            } else if !currentName.isEmpty, let colonRange = trimmed.range(of: ": ") {
                let key = String(trimmed[trimmed.startIndex ..< colonRange.lowerBound])
                let value = String(trimmed[colonRange.upperBound...])
                props[key] = value
            }
        }

        // Evaluate the last device block.
        return evaluateDevice()
    }

    // MARK: - system_profiler Fallback

    /// Used on real Macs whose audio hardware is not exposed via standard
    /// IOHDACodecDevice nodes (e.g. Intel Smart Sound Technology + CS8409).
    /// Parses `system_profiler SPAudioDataType -xml` to extract at least the
    /// audio device name and its vendor/manufacturer from CoreAudio.
    private func computeAudioInfoFromSystemProfiler() -> AudioInfo {
        let output = run("system_profiler SPAudioDataType -xml 2>/dev/null")
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let rootArray = plist as? [[String: Any]],
              let topDict = rootArray.first,
              let items = topDict["_items"] as? [[String: Any]]
        else {
            return emptyAudioInfo
        }

        // Prefer the first built-in device that has a manufacturer; fall back to any device.
        let chosen = items.first(where: {
            let transport = $0["coreaudio_device_transport"] as? String ?? ""
            let vendor = $0["coreaudio_device_manufacturer"] as? String ?? ""
            return transport.contains("builtin") && !vendor.isEmpty
        }) ?? items.first(where: {
            !($0["coreaudio_device_manufacturer"] as? String ?? "").isEmpty
        })

        guard let device = chosen,
              let vendor = device["coreaudio_device_manufacturer"] as? String,
              !vendor.isEmpty
        else {
            return emptyAudioInfo
        }

        let name = device["_name"] as? String ?? ""
        return AudioInfo(codecName: name, vendorName: vendor, deviceName: "", layoutId: "", driver: "", codecHex: "", vendorHex: "", deviceHex: "")
    }

    private var emptyAudioInfo: AudioInfo {
        AudioInfo(codecName: "", vendorName: "", deviceName: "", layoutId: "", driver: "", codecHex: "", vendorHex: "", deviceHex: "")
    }

    // MARK: - Parsers

    /// Parse `"IOHDACodecVendorID" = <integer>` from ioreg output.
    private func parseVendorId(from output: String) -> UInt32 {
        for line in output.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            // Use contains instead of hasPrefix because ioreg -l prefixes non-last
            // sibling property lines with "| " tree characters that survive whitespace trimming.
            guard t.contains("\"IOHDACodecVendorID\"") else { continue }
            // Format: "IOHDACodecVendorID" = 272659488
            if let eqRange = t.range(of: "=") {
                let valueStr = String(t[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if let value = UInt32(valueStr) {
                    return value
                }
            }
        }
        return 0
    }

    /// Parse layout-id from ioreg output.
    /// Checks "alc-layout-id" first (AppleALC override), then falls back to "layout-id".
    /// Handles two formats:
    ///   Data (AppleALC / bootloader injection): "alc-layout-id" = <07000000>  → first byte little-endian
    ///   Integer (VoodooHDA direct injection):   "layout-id" = 7
    private func parseLayoutId(from output: String) -> String {
        if let id = parseLayoutIdForKey("alc-layout-id", from: output), !id.isEmpty {
            return id
        }
        return parseLayoutIdForKey("layout-id", from: output) ?? ""
    }

    private func parseLayoutIdForKey(_ key: String, from output: String) -> String? {
        let searchKey = "\"\(key)\""
        for line in output.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            // Use contains instead of hasPrefix (see parseVendorId comment).
            guard t.contains(searchKey) else { continue }
            // Try data format first: <XXYYZZ...>
            if let open = t.firstIndex(of: "<"),
               let close = t.firstIndex(of: ">"),
               close > open
            {
                let hex = String(t[t.index(after: open) ..< close])
                guard hex.count >= 2 else { continue }
                let byteStr = String(hex.prefix(2))
                if let byte = UInt32(byteStr, radix: 16), byte > 0 {
                    return "\(byte)"
                }
            }
            // Fall back to integer format: "layout-id" = 7
            if let eqRange = t.range(of: "=") {
                let valueStr = String(t[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                if let value = UInt32(valueStr), value > 0 {
                    return "\(value)"
                }
            }
        }
        return nil
    }

    /// Parse HDAUniversal layout-id from ioreg output.
    /// Format: "HDAUniversalEffectiveLayoutID" = 69 (decimal value, used as-is)
    private func parseHDAUniversalEffectiveLayoutId(from output: String) -> String {
        let key = "\"HDAUniversalEffectiveLayoutID\""
        for line in output.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains(key), let eqRange = t.range(of: "=") else { continue }
            let rawValue = String(t[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let value = UInt32(rawValue), value > 0 {
                return "\(value)"
            }
        }
        return ""
    }

    /// Parse combined PCI device-id: reads `vendor-id` and `device-id` data properties
    /// and returns them as a tuple (vendorId, deviceId).
    private func parsePciIds(from output: String) -> (UInt32, UInt32) {
        var vendorId: UInt32 = 0
        var deviceId: UInt32 = 0
        for line in output.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            // Use contains instead of hasPrefix (see parseVendorId comment).
            if t.contains("\"vendor-id\""), let v = parseLeUInt16DataProp(t) {
                vendorId = v
            } else if t.contains("\"device-id\""), let d = parseLeUInt16DataProp(t) {
                deviceId = d
            }
        }
        return (vendorId, deviceId)
    }

    /// Read an ioreg data property formatted as `"key" = <XXYY0000>` and return the
    /// first two bytes interpreted as a little-endian 16-bit unsigned integer.
    private func parseLeUInt16DataProp(_ line: String) -> UInt32? {
        guard let open = line.firstIndex(of: "<"),
              let close = line.firstIndex(of: ">"),
              close > open else { return nil }
        let hex = String(line[line.index(after: open) ..< close])
        guard hex.count >= 4 else { return nil }
        let byte0Str = String(hex.prefix(2))
        let byte1Str = String(hex.dropFirst(2).prefix(2))
        guard let byte0 = UInt32(byte0Str, radix: 16),
              let byte1 = UInt32(byte1Str, radix: 16) else { return nil }
        // Little-endian: byte0 is LSB, byte1 is the next byte
        return byte0 | (byte1 << 8)
    }

    // MARK: - Codec Name Lookup

    /// Map a codec vendor ID (upper 16 bits = vendor, lower 16 bits = model) to a
    /// human-readable string such as "Realtek ALC1220", plus a hex string for tooltip use.
    private func lookupCodecName(vendorId: UInt32) -> (name: String, hex: String) {
        let vendor = (vendorId >> 16) & 0xFFFF
        let model = vendorId & 0xFFFF

        let hex = String(format: "0x%04X:0x%04X", vendor, model)
        switch vendor {
        case 0x10EC:
            // Realtek: model number encoded as hex digits matching the "ALC" designation
            // e.g. 0x0887 → ALC887, 0x1220 → ALC1220
            return ("Realtek ALC\(String(format: "%X", model))", hex)
        case 0x8086:
            return ("Intel \(String(format: "0x%04X", model))", hex)
        case 0x10DE:
            return ("NVIDIA \(String(format: "0x%04X", model))", hex)
        case 0x1002:
            return ("AMD \(String(format: "0x%04X", model))", hex)
        case 0x1106:
            return ("VIA \(String(format: "0x%04X", model))", hex)
        case 0x14F1:
            return ("Conexant \(String(format: "0x%04X", model))", hex)
        case 0x1013:
            return ("Cirrus Logic \(String(format: "0x%04X", model))", hex)
        case 0x111D:
            return ("IDT \(String(format: "0x%04X", model))", hex)
        case 0x11D4:
            return ("Analog Devices \(String(format: "0x%04X", model))", hex)
        default:
            return (String(format: "0x%04X:0x%04X", vendor, model), "")
        }
    }

    // MARK: - Vendor / Device Name Lookups

    /// Map the upper-16-bit codec vendor code to a company name string, plus a hex string for tooltip use.
    private func lookupAudioVendorName(vendorCode: UInt32) -> (name: String, hex: String) {
        let hex = String(format: "0x%04X", vendorCode)
        switch vendorCode {
        case 0x10EC: return ("Realtek Semiconductor Co., Ltd.", hex)
        case 0x8086: return ("Intel Corporation", hex)
        case 0x10DE: return ("NVIDIA Corporation", hex)
        case 0x1002: return ("Advanced Micro Devices, Inc.", hex)
        case 0x1106: return ("VIA Technologies, Inc.", hex)
        case 0x14F1: return ("Conexant Systems, LLC", hex)
        case 0x1013: return ("Cirrus Logic, Inc.", hex)
        case 0x111D: return ("IDT", hex)
        case 0x11D4: return ("Analog Devices, Inc.", hex)
        default: return (String(format: "0x%04X", vendorCode), "")
        }
    }

    /// Map a PCI vendor + device ID pair to a descriptive controller name, plus a hex string for tooltip use.
    /// Returns a human-readable string such as "Intel Cannon Lake PCH cAVS", or the
    /// raw hex pair when the device is not in the table.
    private func lookupPciDeviceName(vendorId: UInt32, deviceId: UInt32) -> (name: String, hex: String) {
        guard vendorId > 0 || deviceId > 0 else { return ("", "") }

        let hex = String(format: "0x%04X:0x%04X", vendorId, deviceId)

        // Build device description for known HDA controllers
        let deviceDesc: String? = switch (vendorId, deviceId) {
        // Intel – sorted by generation
        case (0x8086, 0x27D8): "NM10/ICH7 HD Audio"
        case (0x8086, 0x284B): "82801H (ICH8) HD Audio"
        case (0x8086, 0x293E): "82801I (ICH9) HD Audio"
        case (0x8086, 0x293F): "82801I (ICH9) HD Audio"
        case (0x8086, 0x3B56): "5 Series/3400 Series PCH HD Audio"
        case (0x8086, 0x3B57): "5 Series/3400 Series PCH HD Audio"
        case (0x8086, 0x1C20): "6 Series/C200 Series PCH HD Audio"
        case (0x8086, 0x1D20): "C600/X79 Series PCH HD Audio"
        case (0x8086, 0x1E20): "7 Series/C210 Series PCH HD Audio"
        case (0x8086, 0x8C20): "8 Series/C220 Series PCH HD Audio"
        case (0x8086, 0x8C21): "8 Series/C220 Series PCH HD Audio"
        case (0x8086, 0x8CA0): "9 Series PCH HD Audio"
        case (0x8086, 0x8D20): "C610/X99 Series PCH HD Audio"
        case (0x8086, 0x9C20): "8 Series HD Audio"
        case (0x8086, 0x9C21): "8 Series HD Audio"
        case (0x8086, 0x9CA0): "Wildcat Point-LP HD Audio"
        case (0x8086, 0x9D70): "Sunrise Point HD Audio"
        case (0x8086, 0x9D71): "Sunrise Point-LP HD Audio"
        case (0x8086, 0xA170): "100 Series/C230 Series PCH HD Audio"
        case (0x8086, 0xA171): "CM238 PCH HD Audio"
        case (0x8086, 0xA1F0): "Lewisburg PCH HD Audio"
        case (0x8086, 0xA2F0): "200 Series PCH HD Audio"
        case (0x8086, 0xA348): "Cannon Lake PCH cAVS"
        case (0x8086, 0x9DC8): "Cannon Point-LP HD Audio"
        case (0x8086, 0x02C8): "Comet Lake PCH-LP cAVS"
        case (0x8086, 0x06C8): "Comet Lake PCH cAVS"
        case (0x8086, 0x0043): "Comet Lake-H PCH cAVS"
        case (0x8086, 0x34C8): "Ice Lake-LP HD Audio"
        case (0x8086, 0xA0C8): "Tiger Lake-LP Smart Sound Technology"
        case (0x8086, 0x43C8): "Tiger Lake-H HD Audio"
        case (0x8086, 0x4B55): "Elkhart Lake HD Audio"
        case (0x8086, 0x4DC8): "Jasper Lake HD Audio"
        case (0x8086, 0x51C8): "Alder Lake PCH-H HD Audio"
        case (0x8086, 0x51C9): "Alder Lake-N PCH HD Audio"
        case (0x8086, 0x54C8): "Alder Lake-P/M HD Audio"
        case (0x8086, 0x7A50): "Raptor Lake-S/HX cAVS"
        case (0x8086, 0x51CA): "Raptor Lake-P HD Audio"
        case (0x8086, 0x7AD0): "Alder Lake PCH-P HD Audio"
        case (0x8086, 0x7E28): "Meteor Lake-P HD Audio"
        case (0x8086, 0xF0C8): "500 Series PCH High Definition"
        // NVIDIA – GeForce/Quadro HDMI audio controllers
        case (0x10DE, _) where deviceId >= 0x0BE2 && deviceId <= 0x0BEF: "GT 2xx HDMI Audio"
        case (0x10DE, _): "HD Audio Controller"
        // AMD
        case (0x1002, 0x1308): "FCH HD Audio"
        case (0x1002, 0x157A): "Bristol Ridge HD Audio"
        case (0x1002, 0x15DE): "Raven/Raven2 HD Audio"
        case (0x1002, 0x1637): "Renoir Radeon HD Audio"
        case (0x1002, 0x1638): "Cezanne Radeon HD Audio"
        case (0x1002, _): "HD Audio Controller"
        default: nil
        }

        let vendorName = switch vendorId {
        case 0x8086: "Intel"
        case 0x10DE: "NVIDIA"
        case 0x1002: "AMD"
        default: String(format: "0x%04X", vendorId)
        }

        if let desc = deviceDesc {
            return ("\(vendorName) \(desc)", hex)
        }
        return ("\(vendorName) \(String(format: "0x%04X", deviceId))", hex)
    }
}
