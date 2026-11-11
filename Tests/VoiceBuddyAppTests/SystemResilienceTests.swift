import XCTest
import AppKit
import VoiceBuddyCore
@testable import VoiceBuddyApp

@MainActor
final class SystemResilienceTests: XCTestCase {
    func testOverlayIgnoresMouseEvents() {
        let overlay = Overlay()
        let state = AppState()
        overlay.show(state: state)
        defer { overlay.hide() }

        XCTAssertTrue(overlay.isIgnoringMouseEvents, "Overlay HUD must ignore mouse events to avoid blocking underlying windows")
    }

    func testCancelDoesNotInterruptBackgroundEditorDownload() {
        let state = AppState()
        state.editorPreparing = true
        state.activeDownloadingTextModelID = "qwen35-text-0.8b-int5"

        // Calling session cancel should only affect active dictation/recording
        state.cancel()

        XCTAssertTrue(state.editorPreparing, "cancel() must decouple recording cancellation from text model download")
        XCTAssertEqual(state.activeDownloadingTextModelID, "qwen35-text-0.8b-int5")

        // Explicitly cancelling text download clears the state
        state.cancelTextDownload(id: "qwen35-text-0.8b-int5")
        XCTAssertFalse(state.editorPreparing)
        XCTAssertNil(state.activeDownloadingTextModelID)
    }

    func testCancelSpeechDownloadSymmetry() {
        let state = AppState()
        state.speechPreparing = true
        state.activeDownloadingSpeechModelID = "sensevoice-asr-int8"
        state.preferences.speechModel = "sensevoice-asr-int8"

        state.cancelSpeechDownload(id: "sensevoice-asr-int8")

        XCTAssertFalse(state.speechPreparing)
        XCTAssertNil(state.activeDownloadingSpeechModelID)
        XCTAssertFalse(state.modelPreparing)
    }

    func testAppleSpeechOfflineDoesNotRequireVAD() async throws {
        let models = LocalModels()
        // Try prepareSpeech for apple-speech; must complete without network or Silero VAD error
        try await models.prepareSpeech(id: "apple-speech") { _, _ in }

        let sampleAudio = [Float](repeating: 0.05, count: 1600)
        let hasSpeech = try await models.containsSpeech(sampleAudio)
        XCTAssertTrue(hasSpeech, "Apple Speech should accept audio without throwing VAD unavailable")

        let emptyAudio: [Float] = []
        let hasSpeechEmpty = try await models.containsSpeech(emptyAudio)
        XCTAssertFalse(hasSpeechEmpty, "Empty audio should be rejected")
    }

    func testFocusVerificationFailsClosedWhenInitialElementIsNil() {
        let state = AppState()
        let frontApp = NSWorkspace.shared.frontmostApplication
        let targetPID = (frontApp != nil && frontApp?.processIdentifier != NSRunningApplication.current.processIdentifier)
            ? frontApp!.processIdentifier
            : 1

        let result = state.insertIfSafe(
            "test text",
            targetPID: targetPID,
            targetAppName: frontApp?.localizedName ?? "launchd",
            targetElement: nil
        )

        XCTAssertFalse(result, "insertIfSafe must fail-closed when focus element cannot be verified")
        XCTAssertFalse(state.insertFailure.isEmpty, "insertFailure must describe the refusal reason")
    }

    func testStuckBusyStateSelfHealing() {
        let state = AppState()
        state.busy = true
        state.recording = false

        // Attempting to start dictation when busy is stuck without active recording or task should self-heal
        state.toggle()

        // Either it began recording (if speech model was ready) or reset busy and stopped cleanly
        XCTAssertFalse(state.busy, "Stale busy state must be repaired and self-healed")
    }
}
