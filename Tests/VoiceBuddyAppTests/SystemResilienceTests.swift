import XCTest
import AppKit
@testable import VoiceBuddyApp

@MainActor
final class SystemResilienceTests: XCTestCase {
    func testOverlayIgnoresMouseEvents() {
        let overlay = Overlay()
        let state = AppState()
        overlay.show(state: state)
        defer { overlay.hide() }

        XCTAssertNotNil(overlay.panel)
        XCTAssertTrue(overlay.panel?.ignoresMouseEvents ?? false, "Overlay HUD must ignore mouse events to avoid blocking underlying windows")
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

    func testOfflineSpeechEnergyDetectionFallback() async throws {
        let models = LocalModels()
        // Without VAD loaded, containsSpeech falls back to RMS energy threshold
        let silence = [Float](repeating: 0.0, count: 1600)
        let silenceDetected = try await models.containsSpeech(silence)
        XCTAssertFalse(silenceDetected, "Silence should not trigger speech detection")

        let audio = (0..<1600).map { sin(Float($0) * 0.1) * 0.5 }
        let speechDetected = try await models.containsSpeech(audio)
        XCTAssertTrue(speechDetected, "Audible energy should trigger fallback speech detection")
    }
}
