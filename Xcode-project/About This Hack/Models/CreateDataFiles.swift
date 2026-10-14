//
//  CreateDataFiles.swift
//  About This Hack
//

import Foundation

class CreateDataFiles {
    private final class DataFilesCreatedState: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func get() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: Bool) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    private static let dataFilesState = DataFilesCreatedState()

    /// Notification name for when data files are created
    static let dataFilesCreatedNotification = Notification.Name("DataFilesCreated")

    static var dataFilesCreated: Bool {
        dataFilesState.get()
    }

    /// Asynchronously creates initial data files
    /// - Parameter completion: Called on completion (main thread)
    static func getInitDataFilesAsync(completion: @Sendable @escaping () -> Void) {
        if dataFilesState.get() {
            DispatchQueue.main.async {
                completion()
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            getInitDataFiles()
            DispatchQueue.main.async {
                completion()
                // Post notification that data files are ready
                NotificationCenter.default.post(name: dataFilesCreatedNotification, object: nil)
            }
        }
    }

    private static let directoryLock = NSLock()
    private nonisolated(unsafe) static var directoryPrepared = false

    /// Removes any stale data directory and recreates it once per launch.
    private static func prepareDirectory() {
        directoryLock.lock()
        defer { directoryLock.unlock() }
        guard !directoryPrepared else { return }
        directoryPrepared = true

        let fm = FileManager.default
        let athURL = URL(fileURLWithPath: InitGlobVar.athDirectory, isDirectory: true)
        try? fm.removeItem(at: athURL)
        do {
            try fm.createDirectory(at: athURL, withIntermediateDirectories: true)
        } catch {
            print("Error: could not create temp directory \(athURL.path): \(error)")
        }
    }

    /// Fast reports the Overview needs beyond native APIs (memory type/speed and
    /// Clover detection). Creating them first lets the Overview appear with final values.
    private static let overviewCommands: [(path: String, command: String)] = [
        (InitGlobVar.sysmemFilePath, "system_profiler SPMemoryDataType 2>/dev/null | grep -v \"^Memory:$\" > \"\(InitGlobVar.sysmemFilePath)\""),
        (InitGlobVar.hwFilePath, "system_profiler SPHardwareDataType 2>/dev/null > \"\(InitGlobVar.hwFilePath)\""),
    ]

    /// Note: scrXmlFilePath and syssoftdataFilePath removed - they were never used in the codebase
    /// Note: SPDisplaysDataType is run directly (without a file) in HardwareCollector.getAllData()
    private static let detailCommands: [(path: String, command: String)] = [
        (InitGlobVar.bootvolnameFilePath, "diskutil info / 2>/dev/null > \"\(InitGlobVar.bootvolnameFilePath)\""),
        (InitGlobVar.bootvollistFilePath, "diskutil list / 2>/dev/null > \"\(InitGlobVar.bootvollistFilePath)\""),
        (InitGlobVar.storagedataFilePath, "system_profiler SPStorageDataType 2>/dev/null > \"\(InitGlobVar.storagedataFilePath)\""),
    ]

    private static func fileHasContent(_ path: String) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 0
    }

    /// Runs the commands whose output files do not exist yet, concurrently, and waits for them.
    private static func runMissing(_ entries: [(path: String, command: String)]) {
        prepareDirectory()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        for entry in entries where !fileHasContent(entry.path) {
            let command = entry.command
            group.enter()
            queue.async {
                _ = run(command)
                group.leave()
            }
        }
        group.wait()
    }

    /// Creates only the fast reports needed by the Overview tab.
    static func createOverviewDataFiles() {
        runMissing(overviewCommands)
    }

    static func getInitDataFiles() {
        if dataFilesState.get() {
            return
        }

        // /* Product phase  - Uncomment for product phase
        // Run all commands in parallel; reports already created for the Overview are reused.
        runMissing(overviewCommands + detailCommands)
        print("Data files created")
        // */

        /*  Testing phase - Uncomment and modify path for testing phase
         let testDataRep = "~/Downloads/0-ath-issue-N78" // Replace with your test data directory

         createFileIfNeeded(atPath: InitGlobVar.hwFilePath, withCommand: "ln -s \(testDataRep)/hw.txt  \"\(InitGlobVar.hwFilePath)\"")
         // ... Add similar lines for other files
         */

        dataFilesState.set(true)
    }
}
