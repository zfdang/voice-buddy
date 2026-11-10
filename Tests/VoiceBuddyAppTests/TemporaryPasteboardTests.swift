import AppKit
import XCTest
@testable import VoiceBuddyApp

final class TemporaryPasteboardTests: XCTestCase {
    func testSensitiveValueIsMarkedAndOriginalIsRestored() throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        XCTAssertTrue(board.setString("original", forType: .string))
        let temporary = TemporaryPasteboard(board: board)
        XCTAssertTrue(temporary.write("secret", sensitive: true))
        XCTAssertTrue(temporary.owns("secret"))
        XCTAssertNotNil(board.pasteboardItems?.first?.types.first { $0.rawValue == "org.nspasteboard.ConcealedType" })
        XCTAssertTrue(temporary.restore())
        XCTAssertEqual(board.string(forType: .string), "original")
    }

    func testExternalChangeIsNotOverwritten() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("original", forType: .string)
        let temporary = TemporaryPasteboard(board: board)
        XCTAssertTrue(temporary.write("temporary", sensitive: false))
        board.clearContents()
        board.setString("new", forType: .string)
        XCTAssertFalse(temporary.restore())
        XCTAssertEqual(board.string(forType: .string), "new")
    }
}
