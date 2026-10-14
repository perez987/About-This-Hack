//
//  SystemFunctions.swift
//  About This Hack
//
// Update by YBronst https://github.com/YBronst

import AppKit
import Cocoa
import Darwin
import IOKit

nonisolated(unsafe) var thisApplicationVersion = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String

/// Define RTLD_DEFAULT for symbol lookup
nonisolated(unsafe) let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

func initPortDefault() -> mach_port_t {
    if #available(macOS 12.0, *) {
        guard let sym = dlsym(RTLD_DEFAULT, "kIOMainPortDefault") else {
            return kIOMainPortDefault
        }
        let ptr = sym.assumingMemoryBound(to: mach_port_t.self)
        return ptr.pointee
    } else {
        return kIOMasterPortDefault
    }
}

import Foundation

func getSysctlValueByKey(inputKey sysctlKey: String) -> String? {
    var oNbrBytes = 0
    // 1. Getting the buffer size
    guard sysctlbyname(sysctlKey, nil, &oNbrBytes, nil, 0) == 0 else { return nil }

    // Protection in case the key is not found
    guard oNbrBytes > 0 else { return nil }

    // 2. Allocate a buffer for the C-string
    var sysctlValue = [CChar](repeating: 0, count: oNbrBytes)
    guard sysctlbyname(sysctlKey, &sysctlValue, &oNbrBytes, nil, 0) == 0 else { return nil }

    // 3. We trim off the null terminator and decode via an explicit Array(CUnsignedChar)
    let cleanBytes = sysctlValue.prefix(while: { $0 != 0 })
    return String(decoding: cleanBytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// Reads a string or NUL-terminated data property without launching ioreg.
func registryString(_ entry: io_registry_entry_t, _ key: String) -> String? {
    guard entry != 0,
          let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    else { return nil }

    let text: String? = switch value {
    case let string as String: string
    case let data as Data: String(data: data, encoding: .utf8)
    default: nil
    }
    return text?
        .replacingOccurrences(of: "\0", with: "")
        .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
        .nilIfEmpty
}

func registryString(path: String, _ key: String) -> String? {
    let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
    defer { if entry != 0 { IOObjectRelease(entry) } }
    return registryString(entry, key)
}

extension Bundle {
    /// Application name shown under the application icon.
    var applicationName: String? {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            object(forInfoDictionaryKey: "CFBundleName") as? String ??
            object(forInfoDictionaryKey: "CFBundleExecutable") as? String
    }
}
