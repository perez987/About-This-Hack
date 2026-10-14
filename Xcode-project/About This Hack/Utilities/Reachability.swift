//
//  Reachability.swift
//  About This Hack
//

import Network

public enum Reachability {
    private final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) {
        value = v
    } }

    static func isConnectedToNetwork() -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        let isConnected = Box(false)

        monitor.pathUpdateHandler = { path in
            isConnected.value = path.status == .satisfied
            semaphore.signal()
        }

        let queue = DispatchQueue(label: "Reachability")
        monitor.start(queue: queue)
        semaphore.wait()
        monitor.cancel()

        let status = isConnected.value ? "reachable" : "NOT reachable"
        print("Internet is \(status)")

        return isConnected.value
    }
}
