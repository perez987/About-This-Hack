//
//  UpdateController.swift
//  About This Hack
//

import AppKit
import Combine
import CryptoKit
import Foundation
import Security

struct UpdateVersion: Comparable, Sendable {
    private let components: [UInt64]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 16,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              parts.allSatisfy({ UInt64($0) != nil }) else { return nil }
        components = parts.map { UInt64($0)! }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct UpdateRelease: Sendable {
    let build: String
    let version: String
    let minimumOS: String
    let url: URL
    let length: Int
    let signature: Data
}

enum UpdateFailure: Error {
    case invalid, network, unsigned, destination
}

enum UpdateSecurity {
    static let feedURL = "https://raw.githubusercontent.com/perez987/About-This-Hack/main/appcast-ath.xml"
    static let maximumDownloadSize = 1_073_741_824

    static func isFeedURL(_ url: URL) -> Bool {
        url.absoluteString == feedURL
    }

    static func isReleaseURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return false }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 7, parts[0].isEmpty,
              parts[1] == "perez987", parts[2] == "About-This-Hack",
              parts[3] == "releases", parts[4] == "download",
              UpdateVersion(String(parts[5])) != nil else { return false }
        return parts[6] == "About.This.Hack.\(parts[5]).dmg"
    }

    static func isDownloadRedirect(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, url.fragment == nil else { return false }
        return isReleaseURL(url)
             || ["release-assets.githubusercontent.com", "objects.githubusercontent.com", "github.com/perez987/About-This-Hack/releases/download/5.1.3/About.This.Hack-glass.5.1.3.dmg", "github.com/perez987/About-This-Hack/releases/download/5.1.3/About.This.Hack.5.1.3.dmg"].contains(url.host ?? "")
    }

    static func verify(data: Data, release: UpdateRelease, publicKey: Data) throws {
        guard data.count == release.length, release.length > 0,
              release.length <= maximumDownloadSize,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(release.signature, for: data) else { throw UpdateFailure.invalid }
    }

    static func metadataMatches(
        _ info: [String: Any], bundleIdentifier: String, release: UpdateRelease
    ) -> Bool {
        info["CFBundleIdentifier"] as? String == bundleIdentifier
            && info["CFBundleVersion"] as? String == release.build
            && info["CFBundleShortVersionString"] as? String == release.version
    }

    static func supportsSystem(_ info: [String: Any], systemVersion: String) -> Bool {
        guard let minimumString = info["LSMinimumSystemVersion"] as? String,
              let minimum = UpdateVersion(minimumString), let system = UpdateVersion(systemVersion) else {
            return false
        }
        return minimum <= system
    }
}

/// Only the small, explicitly understood subset of the legacy Sparkle RSS format is accepted.
final class UpdateFeedParser: NSObject, XMLParserDelegate {
    private var releases: [UpdateRelease] = []
    private var fields: [String: String]?
    private var enclosure: [String: String]?
    private var element = ""
    private var invalid = false
    private var stack: [String] = []
    private var sawChannel = false
    private var completedRoot = false

    static func parse(_ data: Data) throws -> [UpdateRelease] {
        guard data.count <= 1_048_576,
              let text = String(data: data, encoding: .utf8),
              !text.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !text.localizedCaseInsensitiveContains("<!ENTITY") else { throw UpdateFailure.invalid }
        let delegate = UpdateFeedParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), parser.parserError == nil, !delegate.invalid,
              delegate.completedRoot, delegate.sawChannel, delegate.stack.isEmpty else {
            throw UpdateFailure.invalid
        }
        return delegate.releases
    }

    static func newest(
        _ releases: [UpdateRelease], installedBuild: String, systemVersion: String, skippedBuild: String? = nil
    ) -> UpdateRelease? {
        guard let installed = UpdateVersion(installedBuild), let system = UpdateVersion(systemVersion) else {
            return nil
        }
        return releases.filter {
            guard let build = UpdateVersion($0.build), let minimum = UpdateVersion($0.minimumOS) else {
                return false
            }
            return build > installed && minimum <= system && $0.build != skippedBuild
        }.max { UpdateVersion($0.build)! < UpdateVersion($1.build)! }
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
        let parent = stack.last
        stack.append(elementName)
        element = elementName
        if stack.count == 1 {
            if elementName != "rss" || attributeDict["version"] != "2.0"
                || attributeDict["xmlns:sparkle"] != "http://www.andymatuschak.org/xml-namespaces/sparkle" {
                invalid = true
            }
        }
        if elementName == "channel" {
            if parent != "rss" || sawChannel { invalid = true }
            sawChannel = true
        }
        if elementName == "item" {
            if fields != nil || parent != "channel" { invalid = true }
            fields = [:]
            enclosure = nil
        } else if fields != nil && elementName == "enclosure" {
            if enclosure != nil || parent != "item" { invalid = true }
            enclosure = attributeDict
        } else if fields != nil && ["sparkle:version", "sparkle:shortVersionString",
                                    "sparkle:minimumSystemVersion"].contains(elementName) {
            if fields?[elementName] != nil || parent != "item" { invalid = true }
            fields?[elementName] = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if fields?[element] != nil { fields?[element, default: ""] += string }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        element = ""
        guard stack.last == elementName else { invalid = true; return }
        stack.removeLast()
        if stack.isEmpty { completedRoot = true }
        guard elementName == "item", let fields else { return }
        defer { self.fields = nil }
        let build = (fields["sparkle:version"] ?? enclosure?["sparkle:version"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let version = (fields["sparkle:shortVersionString"] ?? enclosure?["sparkle:shortVersionString"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let minimum = (fields["sparkle:minimumSystemVersion"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard UpdateVersion(build) != nil, UpdateVersion(version) != nil, UpdateVersion(minimum) != nil,
              let address = enclosure?["url"], let url = URL(string: address),
              UpdateSecurity.isReleaseURL(url),
              url.lastPathComponent == "About.This.Hack.\(version).dmg",
              let size = enclosure?["length"], size.utf8.allSatisfy({ (48...57).contains($0) }),
              let length = Int(size), length > 0, length <= UpdateSecurity.maximumDownloadSize,
              let encoded = enclosure?["sparkle:edSignature"],
              let signature = Data(base64Encoded: encoded), signature.count == 64 else {
            // A malformed item must not silently downgrade selection to an older release.
            invalid = true
            return
        }
        releases.append(UpdateRelease(
            build: build, version: version, minimumOS: minimum, url: url, length: length, signature: signature
        ))
    }
}

private final class UpdateRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let download: Bool

    init(download: Bool) { self.download = download }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let allowed = request.url.map {
            download ? UpdateSecurity.isDownloadRedirect($0) : UpdateSecurity.isFeedURL($0)
        } ?? false
        completionHandler(allowed ? request : nil)
    }
}

private enum UpdateWorker {
    static func session(download: Bool) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: UpdateRedirectDelegate(download: download),
                          delegateQueue: nil)
    }

    static func feed(url: URL) async throws -> [UpdateRelease] {
        guard UpdateSecurity.isFeedURL(url) else { throw UpdateFailure.invalid }
        let session = session(download: false)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url.map(UpdateSecurity.isFeedURL) == true else { throw UpdateFailure.network }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw UpdateFailure.invalid }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try UpdateFeedParser.parse(data)
    }

    static func privateDirectory(in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(".ath-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    static func download(
        _ release: UpdateRelease, to url: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard UpdateSecurity.isReleaseURL(release.url) else { throw UpdateFailure.invalid }
        let session = session(download: true)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: release.url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url.map(UpdateSecurity.isDownloadRedirect) == true,
              response.expectedContentLength < 0 || response.expectedContentLength == Int64(release.length)
        else { throw UpdateFailure.network }
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { throw UpdateFailure.destination }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var buffer = Data()
        var count = 0
        for try await byte in bytes {
            guard count < release.length else { throw UpdateFailure.invalid }
            buffer.append(byte)
            count += 1
            if buffer.count == 65_536 {
                try Task.checkCancellation()
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                progress(Double(count) / Double(release.length))
            }
        }
        try handle.write(contentsOf: buffer)
        guard count == release.length else { throw UpdateFailure.invalid }
        progress(1)
    }

    static func command(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure.invalid }
        return data
    }

    static func requirement(for app: URL) throws -> SecRequirement {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
        else { throw UpdateFailure.unsigned }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let signing = info as? [String: Any],
              let flags = signing[kSecCodeInfoFlags as String] as? UInt32,
              flags & SecCodeSignatureFlags.adhoc.rawValue == 0,
              signing[kSecCodeInfoTeamIdentifier as String] as? String != nil else { throw UpdateFailure.unsigned }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement else {
            throw UpdateFailure.unsigned
        }
        return requirement
    }

    static func validate(app: URL, runningApp: URL, identifier: String, release: UpdateRelease) throws {
        let requirement = try requirement(for: runningApp)
        let values = try app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        let os = ProcessInfo.processInfo.operatingSystemVersion
        guard values.isSymbolicLink != true, values.isDirectory == true,
              let bundle = Bundle(url: app), let info = bundle.infoDictionary,
              UpdateSecurity.metadataMatches(info, bundleIdentifier: identifier, release: release),
              UpdateSecurity.supportsSystem(
                info, systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
              ) else {
            throw UpdateFailure.invalid
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(
                code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode),
                requirement
              ) == errSecSuccess else { throw UpdateFailure.invalid }
        // Gatekeeper remains enabled; a failed assessment requires manual installation.
        _ = try command("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
    }

    static func checkDestination(_ app: URL) throws {
        let values = try app.resourceValues(forKeys: [.isSymbolicLinkKey, .volumeIsReadOnlyKey])
        let parent = app.deletingLastPathComponent()
        guard app.pathExtension == "app", values.isSymbolicLink != true,
              values.volumeIsReadOnly != true, !app.path.contains("/AppTranslocation/"),
              app.standardizedFileURL == app.resolvingSymlinksInPath(),
              FileManager.default.isWritableFile(atPath: app.path),
              FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateFailure.destination }
    }

    static func prepare(
        release: UpdateRelease, publicKey: Data, runningApp: URL, identifier: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try checkDestination(runningApp)
        _ = try requirement(for: runningApp)
        let manager = FileManager.default
        let cache = try manager.url(for: .cachesDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        let work = try privateDirectory(in: cache)
        defer { try? manager.removeItem(at: work) }
        let image = work.appendingPathComponent("update.dmg")
        try await download(release, to: image, progress: progress)
        try Task.checkCancellation()
        try UpdateSecurity.verify(data: Data(contentsOf: image, options: .mappedIfSafe),
                                  release: release, publicKey: publicKey)
        let mount = work.appendingPathComponent("volume", isDirectory: true)
        try manager.createDirectory(at: mount, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer {
            if (try? command("/usr/bin/hdiutil", ["detach", mount.path])) == nil {
                _ = try? command("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            }
        }
        _ = try command("/usr/bin/hdiutil", [
            "attach", image.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, "-plist"
        ])
        try Task.checkCancellation()
        let source = mount.appendingPathComponent("About This Hack.app", isDirectory: true)
        try validate(app: source, runningApp: runningApp, identifier: identifier, release: release)
        let stage = try privateDirectory(in: runningApp.deletingLastPathComponent())
        do {
            let stagedApp = stage.appendingPathComponent("About This Hack.app", isDirectory: true)
            // ditto preserves bundle symlinks, extended attributes, and quarantine.
            _ = try command("/usr/bin/ditto", ["--rsrc", "--extattr", source.path, stagedApp.path])
            try Task.checkCancellation()
            try validate(app: stagedApp, runningApp: runningApp, identifier: identifier, release: release)
            return stage
        } catch {
            try? manager.removeItem(at: stage)
            throw error
        }
    }

    // All variable data is passed as positional arguments, never inserted into shell source.
    static let helperScript = """
    set -u
    pid="$1"; destination="$2"; stage="$3"; ready="$4"; message="$5"
    backup="$stage/previous.app"
    staged="$stage/About This Hack.app"
    exec >> "$stage/install.log" 2>&1
    fail() {
        /usr/bin/osascript -e 'on run argv' -e 'display dialog (item 1 of argv) buttons {"OK"} default button 1 with icon stop' -e 'end run' "$message" || :
        exit 1
    }
    : > "$ready" || exit 1
    count=0
    while /bin/kill -0 "$pid" 2>/dev/null; do
        count=$((count + 1))
        if [ "$count" -ge 60 ]; then
            /bin/rm -rf "$stage"
            exit 1
        fi
        /bin/sleep 1
    done
    [ -d "$destination" ] && [ ! -L "$destination" ] && [ -d "$staged" ] || fail
    /bin/mv "$destination" "$backup" || fail
    if ! /bin/mv "$staged" "$destination"; then
        /bin/mv "$backup" "$destination" || fail
        /usr/bin/open "$destination" || :
        fail
    fi
    if ! /usr/bin/open "$destination"; then
        /bin/mv "$destination" "$staged" || fail
        /bin/mv "$backup" "$destination" || fail
        /usr/bin/open "$destination" || :
        fail
    fi
    /bin/rm -rf "$stage"
    """

    static func launchHelper(stage: URL, destination: URL, message: String) throws {
        try checkDestination(destination)
        let ready = stage.appendingPathComponent("ready")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", helperScript, "ath-updater", String(ProcessInfo.processInfo.processIdentifier),
                             destination.path, stage.path, ready.path, message]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: ready.path), process.isRunning { return }
            if !process.isRunning { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        throw UpdateFailure.destination
    }
}

@MainActor
final class UpdaterController: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var automaticallyChecksForUpdates: Bool
    private let defaults = UserDefaults.standard
    private var operation: Task<Void, Never>?
    private var scheduler: Task<Void, Never>?
    private var progressWindow: NSWindow?
    private var indicator: NSProgressIndicator?
    private var progressLabel: NSTextField?

    override init() {
        automaticallyChecksForUpdates = UserDefaults.standard.bool(forKey: "ATHAutomaticallyChecksForUpdates")
        super.init()
    }

    private static func text(_ key: String, _ fallback: String) -> String {
        NSLocalizedString("update." + key, value: fallback, comment: "Native updater")
    }

    func startAutomaticChecks() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil,
              NSClassFromString("XCTest.XCTestCase") == nil else { return }
        guard scheduler == nil else { return }
        if !defaults.bool(forKey: "ATHUpdateConsentAsked") {
            let alert = NSAlert()
            alert.messageText = Self.text("consent", "Automatically check for updates?")
            alert.informativeText = Self.text(
                "consentDetail",
                "Allow About This Hack to check for updates weekly? Downloads and installation always require your approval."
            )
            alert.addButton(withTitle: Self.text("allow", "Allow"))
            alert.addButton(withTitle: Self.text("notNow", "Not Now"))
            defaults.set(true, forKey: "ATHUpdateConsentAsked")
            setAutomaticallyChecksForUpdates(alert.runModal() == .alertFirstButtonReturn)
        }
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkAutomaticallyIfDue()
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    func toggleAutomaticChecks() {
        setAutomaticallyChecksForUpdates(!automaticallyChecksForUpdates)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        defaults.set(enabled, forKey: "ATHAutomaticallyChecksForUpdates")
        defaults.set(true, forKey: "ATHUpdateConsentAsked")
        if enabled { checkAutomaticallyIfDue() }
    }

    private func checkAutomaticallyIfDue() {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "ATHUpdateCheckInterval") as? NSNumber)?.doubleValue
            ?? 604800
        let interval = configured.isFinite ? max(configured, 604800) : 604800
        let last = defaults.object(forKey: "ATHLastUpdateCheck") as? Date ?? .distantPast
        if automaticallyChecksForUpdates && Date().timeIntervalSince(last) >= interval {
            check(manual: false)
        }
    }

    func checkForUpdates() { check(manual: true) }

    private func check(manual: Bool) {
        guard canCheckForUpdates else { return }
        canCheckForUpdates = false
        defaults.set(Date(), forKey: "ATHLastUpdateCheck")
        operation = Task { [weak self] in
            guard let self else { return }
            var installationRequested = false
            defer {
                closeProgress()
                canCheckForUpdates = true
                operation = nil
            }
            do {
                guard let feed = Bundle.main.object(forInfoDictionaryKey: "ATHUpdateFeedURL") as? String,
                      let url = URL(string: feed), UpdateSecurity.isFeedURL(url),
                      let encoded = Bundle.main.object(forInfoDictionaryKey: "ATHUpdatePublicEDKey") as? String,
                      let key = Data(base64Encoded: encoded), key.count == 32,
                      let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                      UpdateVersion(build) != nil, let identifier = Bundle.main.bundleIdentifier else {
                    throw UpdateFailure.invalid
                }
                let releases = try await UpdateWorker.feed(url: url)
                let os = ProcessInfo.processInfo.operatingSystemVersion
                let release = UpdateFeedParser.newest(
                    releases, installedBuild: build,
                    systemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                    skippedBuild: manual ? nil : defaults.string(forKey: "ATHSkippedUpdateVersion")
                )
                guard let release else {
                    if manual { showMessage(Self.text("current", "You’re up to date.")) }
                    return
                }
                try Task.checkCancellation()
                guard offer(release) else { return }
                installationRequested = true
                showProgress()
                let app = Bundle.main.bundleURL
                let preparation = Task.detached {
                    try await UpdateWorker.prepare(
                        release: release, publicKey: key, runningApp: app, identifier: identifier,
                        progress: { [weak self = self] fraction in
                            Task { @MainActor [weak self] in self?.updateProgress(fraction) }
                        }
                    )
                }
                let stage = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: {
                    preparation.cancel()
                }
                var handedOff = false
                defer {
                    if !handedOff { try? FileManager.default.removeItem(at: stage) }
                }
                try Task.checkCancellation()
                closeProgress()
                let ready = NSAlert()
                ready.messageText = Self.text("ready", "Ready to restart and install.")
                ready.addButton(withTitle: Self.text("restart", "Restart and Install"))
                ready.addButton(withTitle: Self.text("cancel", "Cancel"))
                guard ready.runModal() == .alertFirstButtonReturn else { return }
                let failureMessage = Self.text("failed", "The update could not be completed.") + "\n"
                    + Self.text("manual", "Please download About This Hack from the project’s GitHub releases and install it manually.")
                try await Task.detached {
                    try UpdateWorker.launchHelper(stage: stage, destination: app, message: failureMessage)
                }.value
                // The helper owns staging after its readiness handshake.
                handedOff = true
                NSApplication.shared.terminate(nil)
                // A delegate can veto termination. Leave staging for the helper's bounded wait.
                return
            } catch {
                closeProgress()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                print("Update check or installation failed: \(error)")
                if manual || installationRequested { showFailure(error) }
            }
        }
    }

    private func offer(_ release: UpdateRelease) -> Bool {
        let alert = NSAlert()
        alert.messageText = Self.text("available", "An update is available.")
        alert.informativeText = String(
            format: Self.text("availableDetail", "Version %@ (build %@) is available. Download and install it now?"),
            release.version, release.build
        )
        alert.addButton(withTitle: Self.text("install", "Download and Install"))
        alert.addButton(withTitle: Self.text("notNow", "Not Now"))
        alert.addButton(withTitle: Self.text("skip", "Skip This Version"))
        let result = alert.runModal()
        if result == .alertThirdButtonReturn { defaults.set(release.build, forKey: "ATHSkippedUpdateVersion") }
        return result == .alertFirstButtonReturn
    }

    private func showMessage(_ message: String, detail: String = "") {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    private func showFailure(_ error: Error) {
        let detail: String
        switch error {
        case UpdateFailure.unsigned:
            detail = Self.text("unsigned", "Automatic installation is unavailable because this copy is not signed with a verifiable developer identity.")
        case UpdateFailure.destination:
            detail = Self.text("destination", "This app cannot be updated in its current location. Move it to a writable Applications folder and try again.")
        case UpdateFailure.invalid:
            detail = Self.text("invalid", "The update failed authenticity or integrity verification.")
        default:
            detail = Self.text("network", "The update server could not be reached or returned an invalid response.")
        }
        showMessage(Self.text("failed", "The update could not be completed."), detail: detail + "\n\n"
                    + Self.text("manual", "Please download About This Hack from the project’s GitHub releases and install it manually."))
    }

    private func showProgress() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 130),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = Self.text("title", "Software Update")
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: Self.text("progress", "Downloading update…"))
        label.frame = NSRect(x: 20, y: 90, width: 380, height: 20)
        let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 60, width: 380, height: 16))
        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = 1
        let cancel = NSButton(title: Self.text("cancel", "Cancel"), target: self, action: #selector(cancelUpdate))
        cancel.frame = NSRect(x: 290, y: 15, width: 110, height: 30)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(indicator)
        window.contentView?.addSubview(cancel)
        progressWindow = window
        self.indicator = indicator
        progressLabel = label
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func updateProgress(_ fraction: Double) {
        indicator?.doubleValue = fraction
        if fraction >= 1 {
            progressLabel?.stringValue = Self.text("verifying", "Verifying and preparing update…")
            indicator?.isIndeterminate = true
            indicator?.startAnimation(nil)
        }
    }

    @objc private func cancelUpdate() { operation?.cancel() }

    private func closeProgress() {
        progressWindow?.close()
        progressWindow = nil
        indicator = nil
        progressLabel = nil
    }
}
