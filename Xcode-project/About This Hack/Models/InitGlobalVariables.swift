//
//  InitGlobalVariables.swift
//  About This Hack
//

import AppKit
import Foundation

class InitGlobVar {
    /// Computed property for thisApplicationName
    static var thisApplicationName: String {
        (Bundle.main.applicationName ?? "").replacingOccurrences(of: ".app", with: "")
    }

    /// Sandbox-safe temporary directory: returns the app container's tmp folder
    /// when sandboxed, or the system /private/tmp directory otherwise.
    static var athDirectory: String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(".ath", isDirectory: true).path
    }

    static var defaultfileManager: FileManager {
        FileManager.default
    }

    // OCLP Dict File (if exists) where Patch Version Commit and DateTime will be extracted
    static let oclpXmlFilePath = "/System/Library/CoreServices/OpenCore-Legacy-Patcher.plist"
    static let bdmesgExecID = "/usr/local/bin/bdmesg"

    // ioreg Dir perl script and pci ids and names files
    static let whichLocation = "/usr/bin/which"
    static let curlLocation: String = run(whichLocation + " curl  | /usr/bin/tr -d '\n'")

    // Files with Overview, Displays and Storage detailed Datas
    static let hwFilePath = athDirectory + "/hw.txt"
    static let scrFilePath = athDirectory + "/scr.txt"
    static let scrXmlFilePath = athDirectory + "/scrXml.txt"
    static let bootvollistFilePath = athDirectory + "/sysbootvollist.txt"
    static let sysmemFilePath = athDirectory + "/sysmem.txt"
    static let syssoftdataFilePath = athDirectory + "/syssoftdata.txt"
    static let bootvolnameFilePath = athDirectory + "/sysvolname.txt"
    static let storagedataFilePath = athDirectory + "/storagedata.txt"

    // Used by ViewController
    static let systemReportSP = "/System/Library/SystemProfiler/SPPlatformReporter.spreporter"
    static let softwareUpdateSP = "/System/Library/PreferencePanes/SoftwareUpdate.prefPane"
    static let softwareUpdateURL = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"

    /// Used by ViewControllerDisplays
    static let displayPrefPane = "/System/Library/PreferencePanes/Displays.prefPane"

    // Used by ViewControllerSupport
    static let macOSUserGuideURL = "https://support.apple.com/guide/mac-help/welcome/mac"
    static let whatsNewInMacOSURL = "https://www.apple.com/macos/"
    static let AppleSupportURL = "https://support.apple.com"
    static let HackintoshInstallURL = "https://dortania.github.io/OpenCore-Install-Guide/troubleshooting/troubleshooting.html#table-of-contents"
    static let MacBasicsURL = "https://help.apple.com/macos/big-sur/mac-basics/"
    static let MacUserGuideURL = "https://support.apple.com/manuals"

    static let nvramOpencoreVersion = "4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version"
}
