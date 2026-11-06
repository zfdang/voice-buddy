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
}
