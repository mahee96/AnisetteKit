//
//  AnisetteLogging.swift
//  AnisetteKit
//
//  Created by Magesh K on 17/08/26.
//  Copyright © 2026 Magesh K. All rights reserved.
//

import Foundation

public enum AnisetteLogging {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _isLoggingEnabled: Bool = false

    public static var isLoggingEnabled: Bool {
        lock.withLock { _isLoggingEnabled }
    }

    public static func setLogging(_ enabled: Bool) {
        lock.withLock { _isLoggingEnabled = enabled }
    }
}

private func getFastTimestamp() -> String {
    var tv = timeval()
    gettimeofday(&tv, nil)
    var tm_info = tm()
    localtime_r(&tv.tv_sec, &tm_info)
    let ms = Int32(tv.tv_usec / 1000)

    var timeBuf = [CChar](repeating: 0, count: 64)
    let len = strftime(&timeBuf, timeBuf.count - 5, "%Y-%m-%dT%H:%M:%S", &tm_info)
    if len > 0 {
        timeBuf[len] = 46 // '.'
        timeBuf[len + 1] = CChar(48 + (ms / 100))
        timeBuf[len + 2] = CChar(48 + ((ms / 10) % 10))
        timeBuf[len + 3] = CChar(48 + (ms % 10))
        timeBuf[len + 4] = 0
        return String(cString: timeBuf)
    }
    return ""
}

private func getTag(level: String) -> String {
    let timestamp = getFastTimestamp()
    return "\(timestamp) \(level): "
}

public func debugLog(_ text: @autoclosure () -> String) {
    let message = formatLogMessage(text())
    if !message.isEmpty && message.allSatisfy({ $0 == "\n" || $0 == "\r" }) {
        print(message, terminator: "")
    } else {
        print("\(getTag(level: "[D]"))\(message)")
    }
}

public func verboseLog(_ text: @autoclosure () -> String) {
    if AnisetteLogging.isLoggingEnabled {
        let message = formatLogMessage(text())
        if !message.isEmpty && message.allSatisfy({ $0 == "\n" || $0 == "\r" }) {
            print(message, terminator: "")
        } else {
            print("\(getTag(level: "[V]"))\(message)")
        }
    }
}

public func formatLogMessage(_ message: String) -> String {
    guard message.contains("UserInfo=") || 
          message.contains("NSURLErrorDomain") || 
          message.contains("NSErrorFailingURLStringKey=") ||
          message.contains("Error Domain=") else 
    {
        return message
    }
    
    var failingURL: String? = nil
    if let urlMatch = message.range(of: "NSErrorFailingURLStringKey=([^,}\\s]+)", options: .regularExpression) {
        let extracted = String(message[urlMatch])
        failingURL = extracted.replacingOccurrences(of: "NSErrorFailingURLStringKey=", with: "")
    } else if let urlMatch = message.range(of: "NSErrorFailingURL=([^,}\\s]+)", options: .regularExpression) {
        let extracted = String(message[urlMatch])
        failingURL = extracted.replacingOccurrences(of: "NSErrorFailingURL=", with: "")
    }
    
    var domain: String? = nil
    if let domainMatch = message.range(of: "Error Domain=([^\\s,]+)", options: .regularExpression) {
        let extracted = String(message[domainMatch])
        domain = extracted.replacingOccurrences(of: "Error Domain=", with: "")
    }
    
    var code: String? = nil
    if let codeMatch = message.range(of: "Code=(-?\\d+)", options: .regularExpression) {
        let extracted = String(message[codeMatch])
        code = extracted.replacingOccurrences(of: "Code=", with: "")
    }
    
    var desc: String? = nil
    if let descMatch = message.range(of: "\"([^\"]+)\"", options: .regularExpression) {
        desc = String(message[descMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    } else if let descMatch = message.range(of: "NSLocalizedDescription=([^,}\n]+)", options: .regularExpression) {
        desc = String(message[descMatch]).replacingOccurrences(of: "NSLocalizedDescription=", with: "")
    }
    
    var streamCode: String? = nil
    if let streamMatch = message.range(of: "_kCFStreamErrorCodeKey=(\\d+)", options: .regularExpression) {
        streamCode = String(message[streamMatch]).replacingOccurrences(of: "_kCFStreamErrorCodeKey=", with: "")
    }
    
    var header = message
    if let range = message.range(of: "Error Domain=") {
        header = String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let range = message.range(of: "UserInfo=") {
        header = String(message[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if header.hasSuffix(",") || header.hasSuffix(":") {
        header = String(header.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if header.contains("Failed to load image data") && header.contains("Error loading image") {
        header = header.replacingOccurrences(of: ": Failed to load image data", with: "")
    }
    if let desc = desc, !header.contains(desc) {
        header += ": \(desc)"
    }
    
    var bullets: [String] = [header]
    if let url = failingURL, !url.isEmpty {
        bullets.append("  • url: '\(url)'")
    }
    if let dom = domain, !dom.isEmpty {
        bullets.append("  • domain: '\(dom)'")
    }
    if let c = code {
        bullets.append("  • code: \(c)")
    }
    if let stream = streamCode {
        bullets.append("  • streamErrorCode: \(stream)")
    }
    
    return bullets.joined(separator: "\n")
}
