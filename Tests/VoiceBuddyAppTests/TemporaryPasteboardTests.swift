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

    func testConsecutiveDictationsPreserveOriginalUserClipboard() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("actual user clipboard", forType: .string)

        // Session 1 begins and writes "dictation 1"
        let session1 = TemporaryPasteboard(board: board)
        XCTAssertTrue(session1.write("dictation 1", sensitive: false))
        XCTAssertEqual(board.string(forType: .string), "dictation 1")

        // Session 2 begins before session 1 has restored (while "dictation 1" is still in board)
        let session2 = TemporaryPasteboard(board: board)
        XCTAssertTrue(session2.write("dictation 2", sensitive: false))
        XCTAssertEqual(board.string(forType: .string), "dictation 2")

        // When session 2 finishes and restores, it should restore the original user clipboard, NOT dictation 1!
        XCTAssertTrue(session2.restore())
        XCTAssertEqual(board.string(forType: .string), "actual user clipboard")
    }
}
