import XCTest
@testable import VoiceBuddyApp

final class DiagnosticLogTests: XCTestCase {
    func testRotationRetainsSevenSegmentsInOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root, limit: 60)
        for index in 0..<10 { log.record("event_\(index) " + String(repeating: "x", count: 20)) }
        let current = try log.readyFile()
        var content = ""
        for index in stride(from: 6, through: 1, by: -1) {
            content += try String(contentsOf: root.appendingPathComponent("diagnostics.\(index).log"), encoding: .utf8)
        }
        content += try String(contentsOf: current, encoding: .utf8)
        XCTAssertFalse(content.contains("event_2 "))
        for index in 3..<10 { XCTAssertTrue(content.contains("event_\(index) ")) }
        XCTAssertLessThan(try XCTUnwrap(content.range(of: "event_3")?.lowerBound), try XCTUnwrap(content.range(of: "event_9")?.lowerBound))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 7)
        let permissions = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: log.fileURL.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o600)
    }

    func testRotationOverwritesPreexistingTargetFilesWithoutError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stale1URL = root.appendingPathComponent("diagnostics.1.log")
        let stale2URL = root.appendingPathComponent("diagnostics.2.log")
        let stale6URL = root.appendingPathComponent("diagnostics.6.log")
        try "stale_content_1".write(to: stale1URL, atomically: true, encoding: .utf8)
        try "stale_content_2".write(to: stale2URL, atomically: true, encoding: .utf8)
        try "stale_content_6".write(to: stale6URL, atomically: true, encoding: .utf8)

        let log = DiagnosticLog(directory: root, limit: 60)
        for index in 0..<12 { log.record("event_\(index) " + String(repeating: "x", count: 20)) }
        _ = try log.readyFile()

        let content1 = try String(contentsOf: stale1URL, encoding: .utf8)
        XCTAssertFalse(content1.contains("stale_content_1"), "Rotation must overwrite stale diagnostics.1.log content")
        XCTAssertTrue(content1.contains("event_"), "diagnostics.1.log must contain rotated log events")
        let content6 = try String(contentsOf: stale6URL, encoding: .utf8)
        XCTAssertFalse(content6.contains("stale_content_6"), "Rotation must overwrite stale diagnostics.6.log content without error")
    }

    func testSanitizePreventsLogInjectionAndRedactsSensitiveFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = DiagnosticLog(directory: root, limit: 4096)

        log.record("diagnostic.test user=alice@example.com\nFAKE_LINE token=sk-1234567890abcdef123456 transcript=secret_words text=\"hello world\" content='private note'")
        let file = try log.readyFile()
        let content = try String(contentsOf: file, encoding: .utf8)
        let lines = content.split(separator: "\n")

        XCTAssertEqual(lines.count, 1, "Newlines inside event must be flattened to prevent log injection")
        XCTAssertFalse(content.contains("alice@example.com"))
        XCTAssertFalse(content.contains("sk-1234567890abcdef123456"))
        XCTAssertFalse(content.contains("secret_words"))
        XCTAssertFalse(content.contains("hello world"))
        XCTAssertFalse(content.contains("private note"))
        XCTAssertTrue(content.contains("[REDACTED_EMAIL]"))
        XCTAssertTrue(content.contains("[REDACTED_TOKEN]"))
        XCTAssertTrue(content.contains("transcript=[REDACTED]"))
        XCTAssertTrue(content.contains("text=[REDACTED]"))
        XCTAssertTrue(content.contains("content=[REDACTED]"))
    }
}
