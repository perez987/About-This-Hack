//
//  Shell.swift
//  About This Hack
//
//

import Foundation

/// Allows native runnning of Terminal commands
func run(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/zsh"
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)!

    // readDataToEndOfFile() already blocks until the subprocess closes stdout
    // (which happens when the process exits), so waitUntilExit() is not needed.
    // Calling waitUntilExit() here would spin the RunLoop, allowing nested
    // SwiftUI updates to fire during an in-progress render pass and trigger
    // "precondition failure: setting value during update".
}
