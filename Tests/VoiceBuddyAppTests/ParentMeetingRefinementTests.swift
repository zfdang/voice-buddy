import XCTest
import Foundation
import VoiceBuddyCore
@testable import VoiceBuddyApp

final class ParentMeetingRefinementTests: XCTestCase {
    func testFourLevels() async throws {
        guard ProcessInfo.processInfo.environment["VOICE_BUDDY_TEST_TEXT"] == "1" else {
            throw XCTSkip("Set VOICE_BUDDY_TEST_TEXT=1 to evaluate the parent-meeting regression with a cached model.")
        }
        let engine = LocalModels()
        let modelID = ProcessInfo.processInfo.environment["VOICE_BUDDY_TEST_TEXT_MODEL"] ?? "qwen35-text-0.8b-int5"
        let cached = await engine.isEditorModelCached(id: modelID)
        guard cached else { throw XCTSkip("Download the selected text model before running this cached-model test.") }
        try await engine.prepareEditor(id: modelID) { _, _ in }
        let input = "今天下午三点钟，啊不对，是两点钟，在三帆中学的明远校区，呃开家长会。希望啊，那个各位家长能够准时到。"
        for mode in [Refinement.light, .balanced, .moderate, .rewrite] {
            let start = Date()
            do {
                let output = try await engine.refine(input, mode: mode)
                let item: [String: Any] = ["mode": mode.rawValue, "output": output, "seconds": Date().timeIntervalSince(start), "safety": TextCleanup.unsafeReason(output, original: input) ?? "accepted", "fallback": await engine.refinementNotice ?? "none"]
                let data = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys, .withoutEscapingSlashes])
                FileHandle.standardError.write(Data("PROBE ".utf8) + data + Data("\n".utf8))
                XCTAssertTrue(output.contains("三帆中学"), output)
                XCTAssertTrue(output.contains("明远校区"), output)
                XCTAssertTrue(output.contains("家长会"), output)
                XCTAssertTrue(output.contains("今天") || output.contains("今日"), output)
                XCTAssertNotNil(output.range(of: "两点|2点|14:00", options: .regularExpression), output)
                if mode == .light { XCTAssertTrue(output.contains("三点"), output) }
                else { XCTAssertFalse(output.contains("三点"), output) }
            } catch {
                XCTFail("\(mode.rawValue): \(error.localizedDescription)")
            }
        }
    }
}
