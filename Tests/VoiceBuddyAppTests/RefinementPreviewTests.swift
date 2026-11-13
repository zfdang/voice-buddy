import XCTest
import VoiceBuddyCore
@testable import VoiceBuddyApp

@MainActor
final class RefinementPreviewTests: XCTestCase {
    func testOriginalPreviewUsesCapturedTextAndPreservesPreferences() async {
        let state = AppState()
        state.original = "  周三，不对，周四。  "
        state.result = "previous result"
        let settings = state.preferences
        await state.testRefinement(mode: .original, modelID: "not-a-model")
        XCTAssertEqual(state.result, state.original)
        XCTAssertEqual(state.preferences, settings)
        XCTAssertFalse(state.testingRefinement)
        XCTAssertFalse(state.refinementTestSummary.isEmpty)
    }

    func testEmptyTranscriptDoesNotReplaceResult() async {
        let state = AppState()
        state.original = "  \n "
        state.result = "keep this"
        await state.testRefinement(mode: .light, modelID: "not-a-model")
        XCTAssertEqual(state.result, "keep this")
        XCTAssertFalse(state.testingRefinement)
    }

    func testDictationInProgressRejectsPreview() async {
        let state = AppState()
        state.original = "original"
        state.result = "keep this"
        state.busy = true
        await state.testRefinement(mode: .original, modelID: "not-a-model")
        XCTAssertEqual(state.result, "keep this")
        XCTAssertTrue(state.busy)
        XCTAssertFalse(state.testingRefinement)
    }
}
