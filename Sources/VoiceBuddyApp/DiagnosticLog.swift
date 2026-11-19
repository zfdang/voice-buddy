import Foundation

/// Local diagnostics contain only explicitly supplied operational metadata.
final class DiagnosticLog {
    static let shared = DiagnosticLog()
    private let queue = DispatchQueue(label: "VoiceBuddy.diagnostics")
    private let directory: URL
    private let limit: UInt64

    init(directory: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/VoiceBuddy", isDirectory: true), limit: UInt64 = 1_000_000) {
        self.directory = directory
        self.limit = limit
    }

    var fileURL: URL { directory.appendingPathComponent("diagnostics.log") }
    private func previousURL(_ index: Int) -> URL { directory.appendingPathComponent("diagnostics.\(index).log") }

    private func prepare() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if !fm.fileExists(atPath: fileURL.path) {
            guard fm.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static let emailRegex = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|hf_[A-Za-z0-9]{16,}|Bearer\s+[A-Za-z0-9._-]{16,})\b"#,
        options: []
    )
    private static let sensitiveFieldRegex = try! NSRegularExpression(
        pattern: #"\b(transcript|raw_text|polished_text|text|content)=([^\s]+)"#,
        options: [.caseInsensitive]
    )

    static func sanitize(_ event: String) -> String {
        var sanitized = event.replacingOccurrences(of: #"[\r\n\t\x00-\x1F\x7F]+"#, with: " ", options: .regularExpression)
        let range1 = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        sanitized = emailRegex.stringByReplacingMatches(in: sanitized, options: [], range: range1, withTemplate: "[REDACTED_EMAIL]")
        let range2 = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        sanitized = tokenRegex.stringByReplacingMatches(in: sanitized, options: [], range: range2, withTemplate: "[REDACTED_TOKEN]")
        let range3 = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        sanitized = sensitiveFieldRegex.stringByReplacingMatches(in: sanitized, options: [], range: range3, withTemplate: "$1=[REDACTED]")
        return sanitized.trimmingCharacters(in: .whitespaces)
    }

    func record(_ event: String) {
        let recordedAt = Date()
        let safeEvent = Self.sanitize(event)
        queue.async {
            do {
                try self.prepare()
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let date = formatter.string(from: recordedAt)
                let candidate = Data("\(date) \(safeEvent)\n".utf8)
                // Never let an unusually long event defeat the file size limit.
                let data = UInt64(candidate.count) <= self.limit ? candidate : Data("\(date) diagnostic.event_oversize\n".utf8).prefix(Int(self.limit))
                let size = (try FileManager.default.attributesOfItem(atPath: self.fileURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
                if size > 0 && size + UInt64(data.count) > self.limit {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: self.previousURL(6).path) { try fm.removeItem(at: self.previousURL(6)) }
                    for index in stride(from: 5, through: 1, by: -1) {
                        let source = self.previousURL(index)
                        let target = self.previousURL(index + 1)
                        if fm.fileExists(atPath: source.path) {
                            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                            try fm.moveItem(at: source, to: target)
                        }
                    }
                    let target1 = self.previousURL(1)
                    if fm.fileExists(atPath: target1.path) { try fm.removeItem(at: target1) }
                    try fm.moveItem(at: self.fileURL, to: target1)
                    try self.prepare()
                }
                let handle = try FileHandle(forWritingTo: self.fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Fail-safe: do not crash application on log write failures
            }
        }
    }

    /// Flush pending writes before revealing the files in Finder.
    func readyFile() throws -> URL {
        try queue.sync {
            try prepare()
            return fileURL
        }
    }
}
