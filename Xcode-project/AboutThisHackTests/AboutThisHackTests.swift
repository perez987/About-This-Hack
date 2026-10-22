import XCTest
import CryptoKit
@testable import About_This_Hack_glass

final class NativeUpdaterTests: XCTestCase {
    private let releaseURL = "https://github.com/perez987/About-This-Hack/releases/download/5.1.2/About.This.Hack-glass.5.1.2.dmg"

    private func item(build: String = "1662", minimumOS: String = "15.6", url: String? = nil) -> String {
        """
        <item>
          <sparkle:version>\(build)</sparkle:version>
          <sparkle:shortVersionString>5.1.2</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>\(minimumOS)</sparkle:minimumSystemVersion>
          <enclosure url="\(url ?? releaseURL)" length="4"
            sparkle:edSignature="\(Data(repeating: 0, count: 64).base64EncodedString())" />
        </item>
        """
    }

    private func feed(_ items: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel>\(items)</channel></rss>
        """.utf8)
    }

    func testNumericBuildOrderingAndPadding() throws {
        XCTAssertGreaterThan(try XCTUnwrap(UpdateVersion("1662")), try XCTUnwrap(UpdateVersion("999")))
        XCTAssertGreaterThan(try XCTUnwrap(UpdateVersion("2.10")), try XCTUnwrap(UpdateVersion("2.9")))
        XCTAssertEqual(UpdateVersion("2"), UpdateVersion("2.0.0"))
        XCTAssertEqual(UpdateVersion("02.001"), UpdateVersion("2.1"))
    }

    func testMalformedVersionsAreRejected() {
        for version in ["", "1.", ".1", "1..2", "-1", "+1", " 1", "1 ", "1.0-beta", "１", "18446744073709551616"] {
            XCTAssertNil(UpdateVersion(version), version)
        }
    }

    func testLegacySignedAppcastSelectsNewestSupportedBuild() throws {
        let releases = try UpdateFeedParser.parse(feed(
            item(build: "1663", minimumOS: "16") + item(build: "1661") + item(build: "1662")
        ))
        XCTAssertEqual(releases.count, 3)
        XCTAssertEqual(
            UpdateFeedParser.newest(releases, installedBuild: "1660", systemVersion: "15.6")?.build, "1662"
        )
        XCTAssertNil(UpdateFeedParser.newest(releases, installedBuild: "1662", systemVersion: "15.6"))
        XCTAssertNil(UpdateFeedParser.newest(releases, installedBuild: "1660", systemVersion: "15.5"))
        XCTAssertNil(UpdateFeedParser.newest(releases, installedBuild: "invalid", systemVersion: "16"))
        XCTAssertEqual(
            UpdateFeedParser.newest(
                releases, installedBuild: "1660", systemVersion: "15.6", skippedBuild: "1662"
            )?.build, "1661"
        )
    }

    func testMalformedFeedItemsFailClosed() {
        for badItem in [
            item(build: "16beta"),
            item(minimumOS: ""),
            item().replacingOccurrences(of: "length=\"4\"", with: "length=\"0\""),
            item().replacingOccurrences(of: "length=\"4\"", with: "length=\"1073741825\""),
            item().replacingOccurrences(of: "length=\"4\"", with: "length=\"-4\""),
            item().replacingOccurrences(of: "length=\"4\"", with: "length=\"4.0\""),
            item().replacingOccurrences(of: Data(repeating: 0, count: 64).base64EncodedString(), with: "bad"),
            item().replacingOccurrences(of: "</item>", with: "<sparkle:version>1700</sparkle:version></item>"),
            item().replacingOccurrences(of: "glass.5.1.2.dmg", with: "5.1.2.dmg"),
        ] {
            XCTAssertThrowsError(try UpdateFeedParser.parse(feed(item() + badItem)))
        }
        XCTAssertThrowsError(try UpdateFeedParser.parse(Data("<rss><channel>".utf8)))
        XCTAssertThrowsError(try UpdateFeedParser.parse(Data(repeating: 32, count: 1_048_577)))
    }

    func testFeedRejectsEntitiesAndDoctypes() {
        let xml = """
        <?xml version="1.0"?>
        <!DOCTYPE rss [<!ENTITY external SYSTEM "file:///etc/passwd">]>
        <rss><channel><item>&external;</item></channel></rss>
        """
        XCTAssertThrowsError(try UpdateFeedParser.parse(Data(xml.utf8)))
    }

    func testReleaseURLChannelAndOriginRestrictions() throws {
        XCTAssertTrue(UpdateSecurity.isReleaseURL(try XCTUnwrap(URL(string: releaseURL))))
        for address in [
            releaseURL.replacingOccurrences(of: "https:", with: "http:"),
            releaseURL.replacingOccurrences(of: "github.com", with: "github.com.evil.invalid"),
            releaseURL.replacingOccurrences(of: "github.com", with: "user@github.com"),
            releaseURL.replacingOccurrences(of: "github.com", with: "github.com:443"),
            releaseURL.replacingOccurrences(of: "perez987", with: "another-user"),
            releaseURL.replacingOccurrences(of: "About-This-Hack/", with: "About-This-Hack-glass/"),
            releaseURL.replacingOccurrences(of: "Hack-glass", with: "Hack"),
            releaseURL + "?download=1",
            releaseURL + "#fragment",
            releaseURL.replacingOccurrences(of: "download/5.1.2/", with: "download/../"),
        ] {
            XCTAssertFalse(UpdateSecurity.isReleaseURL(try XCTUnwrap(URL(string: address))), address)
        }
    }

    func testOnlyRetainedFeedAndHTTPSAssetRedirectsAreAllowed() throws {
        XCTAssertTrue(UpdateSecurity.isFeedURL(try XCTUnwrap(URL(string: UpdateSecurity.feedURL))))
        XCTAssertFalse(UpdateSecurity.isFeedURL(try XCTUnwrap(URL(
            string: UpdateSecurity.feedURL.replacingOccurrences(of: "/main/", with: "/untrusted/")
        ))))
        XCTAssertTrue(UpdateSecurity.isDownloadRedirect(try XCTUnwrap(
            URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/file?token=value")
        )))
        for address in ["http://release-assets.githubusercontent.com/file",
                        "https://release-assets.githubusercontent.com.evil.invalid/file",
                        "https://github.com/perez987/About-This-Hack/releases/latest",
                        "https://user@objects.githubusercontent.com/file"] {
            XCTAssertFalse(UpdateSecurity.isDownloadRedirect(try XCTUnwrap(URL(string: address))))
        }
    }

    func testEd25519SignatureSizeAndTampering() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data("signed disk image".utf8)
        let signature = try key.signature(for: data)
        let release = UpdateRelease(
            build: "1662", version: "5.1.2", minimumOS: "15.6",
            url: try XCTUnwrap(URL(string: releaseURL)), length: data.count, signature: signature
        )
        XCTAssertNoThrow(try UpdateSecurity.verify(
            data: data, release: release, publicKey: key.publicKey.rawRepresentation
        ))
        XCTAssertThrowsError(try UpdateSecurity.verify(
            data: Data("Signed disk image".utf8), release: release, publicKey: key.publicKey.rawRepresentation
        ))
        XCTAssertThrowsError(try UpdateSecurity.verify(
            data: data + Data([0]), release: release, publicKey: key.publicKey.rawRepresentation
        ))
        XCTAssertThrowsError(try UpdateSecurity.verify(
            data: data, release: release, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
        ))
        XCTAssertThrowsError(try UpdateSecurity.verify(data: data, release: release, publicKey: Data()))
    }

    func testStagedBundleMetadataMustMatchExactly() throws {
        let release = try XCTUnwrap(UpdateFeedParser.parse(feed(item())).first)
        let identifier = "com.0xCUBE.About-This-Hack"
        let info = ["CFBundleIdentifier": identifier, "CFBundleVersion": "1662",
                    "CFBundleShortVersionString": "5.1.2"]
        XCTAssertTrue(UpdateSecurity.metadataMatches(info, bundleIdentifier: identifier, release: release))
        for field in info.keys {
            var modified = info
            modified[field] = "different"
            XCTAssertFalse(UpdateSecurity.metadataMatches(modified, bundleIdentifier: identifier, release: release))
            modified.removeValue(forKey: field)
            XCTAssertFalse(UpdateSecurity.metadataMatches(modified, bundleIdentifier: identifier, release: release))
        }
    }

    func testCandidateMinimumOSIsCheckedIndependentlyOfFeed() {
        XCTAssertTrue(UpdateSecurity.supportsSystem(["LSMinimumSystemVersion": "15.6"], systemVersion: "15.6"))
        XCTAssertTrue(UpdateSecurity.supportsSystem(["LSMinimumSystemVersion": "15"], systemVersion: "26.0"))
        XCTAssertFalse(UpdateSecurity.supportsSystem(["LSMinimumSystemVersion": "26"], systemVersion: "15.6"))
        XCTAssertFalse(UpdateSecurity.supportsSystem(["LSMinimumSystemVersion": "15.6.1"], systemVersion: "15.6"))
        XCTAssertFalse(UpdateSecurity.supportsSystem(["LSMinimumSystemVersion": "invalid"], systemVersion: "26"))
        XCTAssertFalse(UpdateSecurity.supportsSystem([:], systemVersion: "26"))
    }
}

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
        XCTAssertEqual(bootloader, bootloader.trimmingCharacters(in: .whitespacesAndNewlines))
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
        XCTAssertFalse(ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(
                majorVersion: version.majorVersion + 1,
                minorVersion: 0,
                patchVersion: 0
            )
        ))
        XCTAssertEqual(reportedVersion.majorVersion, version.majorVersion)
        XCTAssertEqual(reportedVersion.minorVersion, version.minorVersion)
    }
}

final class GPUFallbackTests: XCTestCase {
    private let intelIdentity = HCGPU.PCIIdentity(vendorID: 0x8086, deviceID: 0x3e98)
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
        for name in ["Intel(R) KBL Unknown", "Intel(R) KBL uNkNoWn", "UNKNOWN", "unknown"] {
            XCTAssertNil(HCGPU.nativeSummary(name: name, details: ["1536 MB", "Metal 3"]))
        }
    }

    func testMissingAndBlankMetalNamesFallBack() {
        for name: String? in [nil, "", " ", "\t \n"] {
            XCTAssertNil(HCGPU.nativeSummary(name: name, details: ["Metal 3"]))
        }
    }

    func testKnownMetalNamesKeepFormatting() {
        XCTAssertEqual(
            HCGPU.nativeSummary(name: "Intel(R) UHD Graphics 630", details: ["", "Metal 3"]),
            "Intel(R) UHD Graphics 630 (Metal 3)"
        )
        XCTAssertEqual(
            HCGPU.nativeSummary(name: "Apple M4 Pro", details: ["", "20-Core", "Metal 4"]),
            "Apple M4 Pro (20-Core, Metal 4)"
        )
        XCTAssertEqual(
            HCGPU.nativeSummary(name: "AMD Radeon RX 580", details: ["8 GB", "", "Metal 3"]),
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
        let report = intelReport.replacingOccurrences(of: "Vendor: Intel (0x8086)", with: "Vendor: Intel")
        for identity in [nil, intelIdentity] {
            XCTAssertEqual(
                HCGPU.profilerSummary(report, selectedIdentity: identity),
                "UHD Graphics 630 1536 MB (Metal 3)"
            )
        }
    }

    func testUniquePCIMatchIgnoresProfilerOrder() {
        for report in [intelReport + "\n" + amdReport, amdReport + "\n" + intelReport] {
            XCTAssertEqual(
                HCGPU.profilerSummary(report, selectedIdentity: intelIdentity),
                "UHD Graphics 630 1536 MB (Metal 3)"
            )
            XCTAssertEqual(
                HCGPU.profilerSummary(
                    report, selectedIdentity: HCGPU.PCIIdentity(vendorID: 0x1002, deviceID: 0x67df)
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
        let missingIDs = report
            .replacingOccurrences(of: "Vendor: Intel (0x8086)", with: "Vendor: Intel")
            .replacingOccurrences(of: "Device ID: 0x3e98", with: "Device ID: unavailable")
        XCTAssertEqual(
            HCGPU.profilerSummary(missingIDs, selectedIdentity: intelIdentity),
            "UHD Graphics 630 1536 MB (Metal 3); Radeon RX 580 8 GB (Metal 2)"
        )
    }

    func testDuplicatePCIMatchReportsAllAdapters() {
        XCTAssertEqual(
            HCGPU.profilerSummary(intelReport + "\n" + intelReport, selectedIdentity: intelIdentity),
            "UHD Graphics 630 1536 MB (Metal 3); UHD Graphics 630 1536 MB (Metal 3)"
        )
    }

    func testVRAMIsNotBorrowedFromAnotherGPUOrDisplay() {
        let noVRAM = intelReport.replacingOccurrences(of: "VRAM (Dynamic, Max): 1536 MB", with: "")
        XCTAssertEqual(
            HCGPU.profilerSummary(noVRAM + "\n" + amdReport, selectedIdentity: intelIdentity),
            "UHD Graphics 630 (Metal 3)"
        )
        XCTAssertEqual(
            HCGPU.profilerSummary(noVRAM + "\n" + amdReport, selectedIdentity: nil),
            "UHD Graphics 630 (Metal 3); Radeon RX 580 8 GB (Metal 2)"
        )
    }

    func testSectionHeaderSuppliesMissingChipsetName() {
        let noChipset = intelReport.replacingOccurrences(of: "Chipset Model: Intel UHD Graphics 630", with: "")
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
        audioOutput: String = ""
    ) -> HCAudio {
        HCAudio { command in
            switch command {
            case "system_profiler SPAudioDataType 2>/dev/null":
                return audioOutput
            case "ioreg -l -r -c IOHDACodecDevice -w 0 2>/dev/null":
                return codecOutput
            case "ioreg -l -r -n HDEF -w 0 2>/dev/null":
                return """
                "layout-id" = <07000000>
                "vendor-id" = <86800000>
                "device-id" = <70a10000>
                """
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
            simpleHDAOutput: "+-o SimpleHDA  <class SimpleHDA, registered, matched, active>"
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
            XCTAssertEqual(collector(simpleHDAOutput: output).getAudioInfo().driver, "AppleALC")
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

    func testSimpleHDADoesNotReplaceUnrelatedAudioFallback() {
        let info = collector(
            simpleHDAOutput: "+-o SimpleHDA  <class SimpleHDA>", codecOutput: ""
        ).getAudioInfo()
        XCTAssertNotEqual(info.driver, "SimpleHDA")
    }

    func testSimpleHDAIsRecognizedForAudioTabVisibility() {
        for driver in ["AppleALC", "SimpleHDA", "HDAUniversal", "VoodooHDA", "USB", "HDMI", "DisplayPort"] {
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
            XCTAssertEqual(english.subtracting(other), [], "Keys missing in \(language)")
            XCTAssertEqual(other.subtracting(english), [], "Extra keys in \(language)")
        }
    }

    private func localizationKeys(for language: String, in bundle: Bundle) throws -> Set<String> {
        let path = try XCTUnwrap(
            bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
            "Missing Localizable.strings for \(language)"
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        let strings = try XCTUnwrap(propertyList as? [String: String])
        return Set(strings.keys)
    }
}

final class LiveHardwareTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let loaded = NSPredicate { _, _ in AppState.shared.isDataLoaded }
        let expectation = XCTNSPredicateExpectation(predicate: loaded, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 60), .completed,
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
        XCTAssertFalse([
            audio.codecName,
            audio.vendorName,
            audio.deviceName,
            audio.layoutId,
            audio.driver,
            audio.codecHex,
            audio.vendorHex,
            audio.deviceHex,
        ].allSatisfy(\.isEmpty))
    }
}
