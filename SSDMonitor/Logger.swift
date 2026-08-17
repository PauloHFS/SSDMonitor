//
//  Logger.swift
//  SSDMonitor
//
//  Logger thread-safe centralizado que grava logs estruturados em /tmp/ssdmonitor.log e no stdout.
//

import Foundation

public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()
    
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.ssdmonitor.logger", qos: .utility)
    
    private init() {
        self.logFileURL = URL(fileURLWithPath: "/tmp/ssdmonitor.log")
        let header = "\n=== SSDMonitor Started at \(Date()) (PID \(ProcessInfo.processInfo.processIdentifier)) ===\n"
        if let data = header.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }
    
    public nonisolated func log(category: String, message: String, isError: Bool = false) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeStr = formatter.string(from: Date())
        let icon = isError ? "❌" : "ℹ️"
        let line = "[\(timeStr)] [\(category)] \(icon) \(message)\n"
        
        print(line, terminator: "")
        fflush(stdout)
        
        queue.async { [logFileURL] in
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            }
        }
    }
}

public nonisolated func logWatcher(_ message: String, isError: Bool = false) {
    AppLogger.shared.log(category: "DiskWatcher", message: message, isError: isError)
}

public nonisolated func logTelemetry(_ message: String, isError: Bool = false) {
    AppLogger.shared.log(category: "TelemetryService", message: message, isError: isError)
}
