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
        final class ProgressBox: @unchecked Sendable { var value: Double = 0 }
        let box = ProgressBox()
        try await models.prepareSpeech(id: "apple-speech") { progress, _ in
            box.value = progress
        }
        XCTAssertEqual(box.value, 1.0, "Apple Speech preparation must reach 100% progress")

        let silence = [Float](repeating: 0.0, count: 1600)
        let silenceDetected = try await models.containsSpeech(silence)
        XCTAssertFalse(silenceDetected, "Pure silence must be rejected by Apple Speech energy detection")

        let lowNoise = [Float](repeating: 0.003, count: 160000)
        let noiseDetected = try await models.containsSpeech(lowNoise)
        XCTAssertFalse(noiseDetected, "Low ambient noise must be rejected by frame-based energy detection")

        // 0.2s of speech in 10s of total audio: frame-based energy detection must NOT dilute this
        let shortSpeechInSilence = (0..<160000).map { $0 < 3200 ? sin(Float($0) * 0.1) * 0.05 : 0.0 }
        let shortSpeechDetected = try await models.containsSpeech(shortSpeechInSilence)
        XCTAssertTrue(shortSpeechDetected, "Short speech within long silence must be detected by frame-based energy gate")

        let audibleAudio = (0..<1600).map { sin(Float($0) * 0.1) * 0.2 }
        let hasSpeech = try await models.containsSpeech(audibleAudio)
        XCTAssertTrue(hasSpeech, "Audible voice should be accepted by Apple Speech without throwing VAD unavailable")

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
        state.preferences.sounds = false
        state.busy = true
        state.recording = false
        defer { state.cancel() }

        // Attempting to start dictation when busy is stuck without active recording or task should self-heal
        state.toggle()

        // Either it began recording (if speech model was ready) or reset busy and stopped cleanly
        XCTAssertFalse(state.busy, "Stale busy state must be repaired and self-healed")
    }
}
