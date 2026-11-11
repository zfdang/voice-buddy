import AppKit
import XCTest
@testable import VoiceBuddyApp

@MainActor
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

    func testConsecutiveOutOfOrderDictationsPreserveOriginalUserClipboard() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("actual user clipboard", forType: .string)

        // Session 1 writes "dictation 1"
        let s1 = TemporaryPasteboard(board: board)
        XCTAssertTrue(s1.write("dictation 1", sensitive: false))
        XCTAssertEqual(board.string(forType: .string), "dictation 1")

        // Session 2 begins before session 1 has restored, passing s1 as predecessor
        let s2 = TemporaryPasteboard(board: board, predecessor: s1)
        XCTAssertTrue(s2.write("dictation 2", sensitive: false))
        XCTAssertEqual(board.string(forType: .string), "dictation 2")

        // Session 1's timer fires out of order: must be a no-op since it was invalidated by s2
        XCTAssertFalse(s1.restore(), "s1 must be invalidated by s2 and fail to restore")
        XCTAssertEqual(board.string(forType: .string), "dictation 2")

        // Session 3 begins before session 2 has restored, passing s2 as predecessor
        let s3 = TemporaryPasteboard(board: board, predecessor: s2)
        XCTAssertTrue(s3.write("dictation 3", sensitive: false))
        XCTAssertEqual(board.string(forType: .string), "dictation 3")

        // Session 2's timer fires out of order: must be a no-op since it was invalidated by s3
        XCTAssertFalse(s2.restore(), "s2 must be invalidated by s3 and fail to restore")
        XCTAssertEqual(board.string(forType: .string), "dictation 3")

        // When session 3 finishes and restores, it must restore the genuine user clipboard!
        XCTAssertTrue(s3.restore())
        XCTAssertEqual(board.string(forType: .string), "actual user clipboard", "Genuine user clipboard must be preserved across out-of-order chained dictations")
    }

    func testExternalTransientCopyBetweenDictationsIsPreserved() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("actual user clipboard", forType: .string)

        // Session 1 begins and writes "dictation 1"
        let s1 = TemporaryPasteboard(board: board)
        XCTAssertTrue(s1.write("dictation 1", sensitive: false))

        // Between dictations, an external password manager writes a new transient item
        let item = NSPasteboardItem()
        item.setString("external_password_123", forType: .string)
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        board.clearContents()
        board.writeObjects([item])

        // Session 2 begins. Even though board has TransientType, board.changeCount moved!
        // Session 2 must NOT inherit s1's savedItems ("actual user clipboard"), but capture "external_password_123"
        let s2 = TemporaryPasteboard(board: board, predecessor: s1)
        XCTAssertTrue(s2.write("dictation 2", sensitive: false))

        // When session 2 restores, it must restore the external tool's copy!
        XCTAssertTrue(s2.restore())
        XCTAssertEqual(board.string(forType: .string), "external_password_123", "External copy between dictations must be preserved")
    }

    func testCancelSessionBeforePasteRestoresOriginalClipboard() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("user_original_data", forType: .string)

        let session = TemporaryPasteboard(board: board)
        XCTAssertTrue(session.write("dictation to cancel", sensitive: false))
        XCTAssertFalse(session.isPastePosted)

        // Cancellation restores original user data immediately
        XCTAssertTrue(session.restore())
        XCTAssertEqual(board.string(forType: .string), "user_original_data", "Session cancellation must restore original user data")
    }
}
