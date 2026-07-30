//
//  LogHelper.swift
//  BluefruitPlayground
//
//  Created by Antonio García on 10/10/2019.
//  Copyright © 2019 Adafruit. All rights reserved.
//

import Foundation

// Note: check that Build Settings -> Project -> Active Compilation Conditions -> Debug, has DEBUG

private let debugLogQueue = DispatchQueue(label: "com.michaelzfreeman.BluefruitPlayground.debug-log")
private let debugLogFileName = "bluefruit-debug.log"
private let maxDebugLogSize = 256 * 1024

func DLog(_ message: String, function: String = #function) {
    if _isDebugAssertConfiguration() {
        NSLog("%@, %@", function, message)
        persistDebugLog("\(ISO8601DateFormatter().string(from: Date())) \(function), \(message)\n")
    }
}

private func persistDebugLog(_ entry: String) {
    debugLogQueue.async {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let logURL = cacheDirectory.appendingPathComponent(debugLogFileName)
        let data = Data(entry.utf8)

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }

        if let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber)?.intValue,
           size > maxDebugLogSize {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}
