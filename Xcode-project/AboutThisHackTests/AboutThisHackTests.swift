import XCTest

@testable import About_This_Hack

final class FormattingTests: XCTestCase {
    func testProcessorFormatting() {
        let processor = HCCPU.shared.getCPU()

        XCTAssertFalse(processor.isEmpty)
        XCTAssertFalse(processor.contains("(R)"))
        XCTAssertFalse(processor.contains("(TM)"))
    }

    func testBootloaderFormatting() {
        let bootloader = HCBootloader.shared.getBootloader()

        XCTAssertFalse(bootloader.isEmpty)
        XCTAssertEqual(
            bootloader,
            bootloader.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertTrue(
            ["Apple iBoot", "Apple UEFI", "OpenCore", "Clover"]
                .contains { bootloader.hasPrefix($0) },
            "Unexpected bootloader format: \(bootloader)"
        )
    }

    func testSystemVersionComparison() {
        HCVersion.shared.getVersion()
        let versionComponents = HCVersion.shared.osNumber
            .split(separator: ".")
            .compactMap { Int($0) }
        XCTAssertGreaterThanOrEqual(versionComponents.count, 2)

        let reportedVersion = OperatingSystemVersion(
            majorVersion: versionComponents[0],
            minorVersion: versionComponents[1],
            patchVersion: versionComponents.dropFirst(2).first ?? 0
        )
        let processInfo = ProcessInfo.processInfo
        XCTAssertTrue(processInfo.isOperatingSystemAtLeast(reportedVersion))
        let version = processInfo.operatingSystemVersion
        XCTAssertFalse(
            ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(
                    majorVersion: version.majorVersion + 1,
                    minorVersion: 0,
                    patchVersion: 0
                )
            )
        )
        XCTAssertEqual(reportedVersion.majorVersion, version.majorVersion)
        XCTAssertEqual(reportedVersion.minorVersion, version.minorVersion)
    }
}

final class GPUFallbackTests: XCTestCase {
    private let intelIdentity = HCGPU.PCIIdentity(
        vendorID: 0x8086,
        deviceID: 0x3e98
    )
    private let intelReport = """
        Graphics/Displays:

            Intel UHD Graphics 630:

              Chipset Model: Intel UHD Graphics 630
              Type: GPU
              Bus: Built-In
              VRAM (Dynamic, Max): 1536 MB
              Vendor: Intel (0x8086)
              Device ID: 0x3e98
              Metal Support: Metal 3
              Displays:
                Main Display:
                  VRAM: 999 GB
                  Metal Support: Not an adapter property
        """
    private let amdReport = """
            AMD Radeon RX 580:

              Chipset Model: AMD Radeon RX 580
              VRAM (Total): 8 GB
              Vendor: AMD (0x1002)
              Device ID: 0x67df
              Metal Support: Metal 2
              Displays:
                External Display:
                  Resolution: 1920 x 1080
        """

    func testUnknownMetalNamesFallBack() {
        for name in [
            "Intel(R) KBL Unknown", "Intel(R) KBL uNkNoWn", "UNKNOWN",
            "unknown",
        ] {
            XCTAssertNil(
                HCGPU.nativeSummary(
                    name: name,
                    details: ["1536 MB", "Metal 3"]
                )
            )
        }
    }

    func testMissingAndBlankMetalNamesFallBack() {
        for name: String? in [nil, "", " ", "\t \n"] {
            XCTAssertNil(HCGPU.nativeSummary(name: name, details: ["Metal 3"]))
        }
    }

    func testKnownMetalNamesKeepFormatting() {
        XCTAssertEqual(
            HCGPU.nativeSummary(
                name: "Intel(R) UHD Graphics 630",
                details: ["", "Metal 3"]
            ),
            "Intel(R) UHD Graphics 630 (Metal 3)"
        )
        XCTAssertEqual(
            HCGPU.nativeSummary(
                name: "Apple M4 Pro",
                details: ["", "20-Core", "Metal 4"]
            ),
            "Apple M4 Pro (20-Core, Metal 4)"
        )
        XCTAssertEqual(
            HCGPU.nativeSummary(
                name: "AMD Radeon RX 580",
                details: ["8 GB", "", "Metal 3"]
            ),
            "AMD Radeon RX 580 (8 GB, Metal 3)"
        )
        XCTAssertEqual(HCGPU.nativeSummary(name: " GPU ", details: []), " GPU ")
    }

    func testSingleGPUFallbackKeepsOriginalSummary() {
        XCTAssertEqual(
            HCGPU.profilerSummary(intelReport, selectedIdentity: nil),
            "UHD Graphics 630 1536 MB (Metal 3)"
        )
        XCTAssertEqual(
            HCGPU.profilerSummary(intelReport, selectedIdentity: intelIdentity),
            "UHD Graphics 630 1536 MB (Metal 3)"
        )
    }

    func testSuppliedIntelReportWithoutHexVendorKeepsSummary() {
        let report = intelReport.replacingOccurrences(
            of: "Vendor: Intel (0x8086)",
            with: "Vendor: Intel"
        )
        for identity in [nil, intelIdentity] {
            XCTAssertEqual(
                HCGPU.profilerSummary(report, selectedIdentity: identity),
                "UHD Graphics 630 1536 MB (Metal 3)"
            )
        }
    }

    func testUniquePCIMatchIgnoresProfilerOrder() {
        for report in [
            intelReport + "\n" + amdReport, amdReport + "\n" + intelReport,
        ] {
            XCTAssertEqual(
                HCGPU.profilerSummary(report, selectedIdentity: intelIdentity),
                "UHD Graphics 630 1536 MB (Metal 3)"
            )
            XCTAssertEqual(
                HCGPU.profilerSummary(
                    report,
                    selectedIdentity: HCGPU.PCIIdentity(
                        vendorID: 0x1002,
                        deviceID: 0x67df
                    )
                ),
                "Radeon RX 580 8 GB (Metal 2)"
            )
        }
    }

    func testUnavailableOrMismatchedIdentityReportsAllAdapters() {
        let report = intelReport + "\n" + amdReport
        for identity in [
            nil,
            HCGPU.PCIIdentity(vendorID: 0x8086, deviceID: 0xffff),
            HCGPU.PCIIdentity(vendorID: 0xffff, deviceID: 0x3e98),
        ] {
            XCTAssertEqual(
                HCGPU.profilerSummary(report, selectedIdentity: identity),
                "UHD Graphics 630 1536 MB (Metal 3); Radeon RX 580 8 GB (Metal 2)"
            )
        }
        let missingIDs =
            report
            .replacingOccurrences(
                of: "Vendor: Intel (0x8086)",
                with: "Vendor: Intel"
            )
            .replacingOccurrences(
                of: "Device ID: 0x3e98",
                with: "Device ID: unavailable"
            )
        XCTAssertEqual(
            HCGPU.profilerSummary(missingIDs, selectedIdentity: intelIdentity),
            "UHD Graphics 630 1536 MB (Metal 3); Radeon RX 580 8 GB (Metal 2)"
        )
    }

    func testDuplicatePCIMatchReportsAllAdapters() {
        XCTAssertEqual(
            HCGPU.profilerSummary(
                intelReport + "\n" + intelReport,
                selectedIdentity: intelIdentity
            ),
            "UHD Graphics 630 1536 MB (Metal 3); UHD Graphics 630 1536 MB (Metal 3)"
        )
    }

    func testVRAMIsNotBorrowedFromAnotherGPUOrDisplay() {
        let noVRAM = intelReport.replacingOccurrences(
            of: "VRAM (Dynamic, Max): 1536 MB",
            with: ""
        )
        XCTAssertEqual(
            HCGPU.profilerSummary(
                noVRAM + "\n" + amdReport,
                selectedIdentity: intelIdentity
            ),
            "UHD Graphics 630 (Metal 3)"
        )
        XCTAssertEqual(
            HCGPU.profilerSummary(
                noVRAM + "\n" + amdReport,
                selectedIdentity: nil
            ),
            "UHD Graphics 630 (Metal 3); Radeon RX 580 8 GB (Metal 2)"
        )
    }

    func testSectionHeaderSuppliesMissingChipsetName() {
        let noChipset = intelReport.replacingOccurrences(
            of: "Chipset Model: Intel UHD Graphics 630",
            with: ""
        )
        XCTAssertEqual(
            HCGPU.profilerSummary(noChipset, selectedIdentity: nil),
            "UHD Graphics 630 1536 MB (Metal 3)"
        )
        XCTAssertEqual(HCGPU.profilerSummary("", selectedIdentity: nil), "")
    }
}

final class AudioDriverTests: XCTestCase {
    private func collector(
        simpleHDAOutput: String,
        codecOutput: String = "\"IOHDACodecVendorID\" = 283906592",
        audioOutput: String = "",
        controllerOutput: String = """
        "layout-id" = <07000000>
        "vendor-id" = <86800000>
        "device-id" = <70a10000>
        """
    ) -> HCAudio {
        HCAudio { command in
            switch command {
            case "system_profiler SPAudioDataType 2>/dev/null":
                return audioOutput
            case "ioreg -l -r -c IOHDACodecDevice -w 0 2>/dev/null":
                return codecOutput
            case "ioreg -l -r -n HDEF -w 0 2>/dev/null":
                return controllerOutput
            case "ioreg -p IOService -r -c SimpleHDA -d 1 -w 0 2>/dev/null":
                return simpleHDAOutput
            default:
                return ""
            }
        }
    }

    func testSimpleHDATakesPrecedenceAndPreservesCodecDetails() {
        let appleALC = collector(simpleHDAOutput: "").getAudioInfo()
        let simpleHDA = collector(
            simpleHDAOutput:
                "+-o SimpleHDA  <class SimpleHDA, registered, matched, active>"
        ).getAudioInfo()

        XCTAssertEqual(simpleHDA.driver, "SimpleHDA")
        XCTAssertEqual(simpleHDA.codecName, "Realtek ALC1220")
        XCTAssertEqual(simpleHDA.layoutId, "7")
        XCTAssertEqual(simpleHDA.codecName, appleALC.codecName)
        XCTAssertEqual(simpleHDA.vendorName, appleALC.vendorName)
        XCTAssertEqual(simpleHDA.deviceName, appleALC.deviceName)
        XCTAssertEqual(simpleHDA.layoutId, appleALC.layoutId)
        XCTAssertEqual(simpleHDA.codecHex, appleALC.codecHex)
        XCTAssertEqual(simpleHDA.vendorHex, appleALC.vendorHex)
        XCTAssertEqual(simpleHDA.deviceHex, appleALC.deviceHex)
    }

    func testMissingSimpleHDAKeepsAppleALC() {
        for output in ["", " \n\t"] {
            XCTAssertEqual(
                collector(simpleHDAOutput: output).getAudioInfo().driver,
                "AppleALC"
            )
        }
    }

    func testDefaultUSBAudioKeepsPriorityOverSimpleHDA() {
        let info = collector(
            simpleHDAOutput: "+-o SimpleHDA  <class SimpleHDA>",
            audioOutput: """
                Audio:
                      USB Speakers:
                        Default Output Device: Yes
                        Transport: USB
                        Manufacturer: Test Vendor
                """
        ).getAudioInfo()

        XCTAssertEqual(info.driver, "USB")
        XCTAssertEqual(info.codecName, "USB Speakers")
    }

    func testEqMacOutputIncludesBuiltInCodecAndActiveLayout() {
        let info = collector(
            simpleHDAOutput: "",
            codecOutput: """
                "IOHDACodecVendorID" = 283902595
                "IOAudioEngineDeviceDescription" = {"layout-id"=7}
                """,
            audioOutput: """
                Audio:
                        Internal Speakers (eqMac):
                          Default Output Device: Yes
                          Manufacturer: Bitgapp Ltd
                          Transport: USB
                          Output Source: Internal Speakers (eqMac)
                """,
            controllerOutput: """
                "alc-layout-id" = <0f000000>
                "layout-id" = <07000000>
                """
        ).getAudioInfo()

        XCTAssertEqual(info.driver, "eqMac")
        XCTAssertEqual(info.codecName, "Realtek ALC283")
        XCTAssertEqual(info.vendorName, "Bitgapp Ltd")
        XCTAssertEqual(info.deviceName, "Internal Speakers (eqMac)")
        XCTAssertEqual(info.layoutId, "7")
    }

    func testSimpleHDADoesNotReplaceUnrelatedAudioFallback() {
        let info = collector(
            simpleHDAOutput: "+-o SimpleHDA  <class SimpleHDA>",
            codecOutput: ""
        ).getAudioInfo()
        XCTAssertNotEqual(info.driver, "SimpleHDA")
    }

    func testSimpleHDAIsRecognizedForAudioTabVisibility() {
        for driver in [
            "AppleALC", "SimpleHDA", "HDAUniversal", "VoodooHDA", "USB",
            "eqMac", "HDMI", "DisplayPort",
        ] {
            XCTAssertTrue(AppState.hackintoshAudioDrivers.contains(driver))
        }
        XCTAssertFalse(AppState.hackintoshAudioDrivers.contains(""))
    }
}

final class LocalizationTests: XCTestCase {
    func testLanguagesShareKeys() throws {
        let bundle = Bundle(for: HCCPU.self)
        let english = try localizationKeys(for: "en", in: bundle)
        XCTAssertFalse(english.isEmpty)

        for language in ["de", "es", "fr", "it", "ru"] {
            let other = try localizationKeys(for: language, in: bundle)
            XCTAssertEqual(
                english.subtracting(other),
                [],
                "Keys missing in \(language)"
            )
            XCTAssertEqual(
                other.subtracting(english),
                [],
                "Extra keys in \(language)"
            )
        }
    }

    private func localizationKeys(for language: String, in bundle: Bundle)
        throws -> Set<String>
    {
        let path = try XCTUnwrap(
            bundle.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: language
            ),
            "Missing Localizable.strings for \(language)"
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        )
        let strings = try XCTUnwrap(propertyList as? [String: String])
        return Set(strings.keys)
    }
}

final class LiveHardwareTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let loaded = NSPredicate { _, _ in AppState.shared.isDataLoaded }
        let expectation = XCTNSPredicateExpectation(
            predicate: loaded,
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 60),
            .completed,
            "Hardware collection and app state initialization did not finish"
        )
    }

    func testCollectorsReturnValues() throws {
        XCTAssertFalse(HCCPU.shared.getCPU().isEmpty)
        XCTAssertFalse(HCRAM.shared.getRam().isEmpty)
        XCTAssertFalse(HCGPU.shared.getGPU().isEmpty)
        XCTAssertFalse(HCDisplay.shared.getDisp().isEmpty)
        XCTAssertFalse(HCMacModel.shared.macName.isEmpty)
        XCTAssertFalse(HCSerialNumber.shared.getSerialNumber().isEmpty)
        XCTAssertFalse(HCStartupDisk.shared.getStartupDisk().isEmpty)
        XCTAssertFalse(HCBootloader.shared.getBootloader().isEmpty)
        XCTAssertFalse(HCVersion.shared.osNumber.isEmpty)
    }

    func testAudioCollectorReturnsValuesWhenAudioTabIsVisible() throws {
        try XCTSkipUnless(
            AppState.shared.shouldShowAudioTab,
            "The Audio tab is unavailable on this hardware or audio configuration"
        )

        let audio = HCAudio.shared.getAudioInfo()
        XCTAssertFalse(
            [
                audio.codecName,
                audio.vendorName,
                audio.deviceName,
                audio.layoutId,
                audio.driver,
                audio.codecHex,
                audio.vendorHex,
                audio.deviceHex,
            ].allSatisfy(\.isEmpty)
        )
    }
}
