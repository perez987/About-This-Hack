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
