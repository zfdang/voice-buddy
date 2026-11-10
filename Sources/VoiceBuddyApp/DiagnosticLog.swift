import Foundation

/// Local diagnostics contain only explicitly supplied operational metadata.
final class DiagnosticLog {
    static let shared = DiagnosticLog()
    private let queue = DispatchQueue(label: "VoiceBuddy.diagnostics")
    private let directory: URL
    private let limit: UInt64
    private var lastError: Error?

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

    func record(_ event: String) {
        let recordedAt = Date()
        queue.async {
            do {
                try self.prepare()
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let date = formatter.string(from: recordedAt)
                let candidate = Data("\(date) \(event)\n".utf8)
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
                            if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                            try fm.moveItem(at: source, to: target)
                        }
                    }
                    let target1 = self.previousURL(1)
                    if fm.fileExists(atPath: target1.path) { try? fm.removeItem(at: target1) }
                    try fm.moveItem(at: self.fileURL, to: target1)
                    try self.prepare()
                }
                let handle = try FileHandle(forWritingTo: self.fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                self.lastError = nil
            } catch { self.lastError = error }
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
