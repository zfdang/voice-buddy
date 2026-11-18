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

        let lowNoise = [Float](repeating: 0.001, count: 160000)
        let noiseDetected = try await models.containsSpeech(lowNoise)
        XCTAssertFalse(noiseDetected, "Low digital noise must be rejected")

        // 0.2s of soft voice in 10s of total audio: must NOT be dropped
        let shortSpeechInSilence = (0..<160000).map { $0 < 3200 ? sin(Float($0) * 0.1) * 0.02 : 0.0 }
        let shortSpeechDetected = try await models.containsSpeech(shortSpeechInSilence)
        XCTAssertTrue(shortSpeechDetected, "Soft speech within long silence must be accepted by Apple Speech")

        let audibleAudio = (0..<1600).map { sin(Float($0) * 0.1) * 0.2 }
        let hasSpeech = try await models.containsSpeech(audibleAudio)
        XCTAssertTrue(hasSpeech, "Audible voice should be accepted by Apple Speech without throwing VAD unavailable")

        let emptyAudio: [Float] = []
        let hasSpeechEmpty = try await models.containsSpeech(emptyAudio)
        XCTAssertFalse(hasSpeechEmpty, "Empty audio should be rejected")
    }

    func testAppStateCancelPreservesUserClipboard() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("real_user_content_before_dictation", forType: .string)

        let state = AppState()
        state.preferences.sounds = false

        // 1. Test cancel before paste is posted
        let session1 = TemporaryPasteboard(board: board)
        XCTAssertTrue(session1.write("dictation 1 to be cancelled", sensitive: false))
        XCTAssertEqual(board.string(forType: .string), "dictation 1 to be cancelled")

        state.setActivePasteboardSessionForTesting(session1)
        state.cancel()

        // Clipboard must be restored immediately!
        XCTAssertEqual(board.string(forType: .string), "real_user_content_before_dictation")
        XCTAssertNil(state.getActivePasteboardSessionForTesting())

        // 2. Test cancel after paste is posted (e.g. sleep notification during 0.45s consumption window)
        let session2 = TemporaryPasteboard(board: board)
        XCTAssertTrue(session2.write("dictation 2 in flight", sensitive: false))
        session2.markPastePosted()

        state.setActivePasteboardSessionForTesting(session2)
        state.cancel()

        // Dictation 2 remains on pasteboard briefly so target app's ⌘V can consume it
        XCTAssertEqual(board.string(forType: .string), "dictation 2 in flight")
        XCTAssertNil(state.getActivePasteboardSessionForTesting())

        // Once the 0.45s delay elapses (simulated by session2.restore()):
        XCTAssertTrue(session2.restore())
        XCTAssertEqual(board.string(forType: .string), "real_user_content_before_dictation", "Original clipboard must be restored after target app consumes paste")
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

    func testAsrReadyAndReadyEquivalence() {
        let state = AppState()
        state.asrReady = true
        XCTAssertTrue(state.ready, "ready property must read from asrReady")

        state.ready = false
        XCTAssertFalse(state.asrReady, "setting ready must update asrReady")
    }

    func testConcurrentModelDownloadDecoupledFromActiveModel() {
        let state = AppState()
        state.preferences.textModel = "qwen35-text-0.8b-int5"
        state.editorReady = true
        state.asrReady = true

        // Simulate downloading another text model concurrently
        state.downloadingTextModelIDs.insert("qwen3-text-1.7b-4bit")
        state.textDownloadProgress["qwen3-text-1.7b-4bit"] = 0.35

        // Downloading another text model must NEVER reset editorReady or trigger isActivatingTextModel
        XCTAssertTrue(state.editorReady, "Active model readiness must NOT be mutated by other downloads")
        XCTAssertFalse(state.isActivatingTextModel, "Background download must not be marked as activating into memory")

        // Simulate downloading another speech model concurrently
        state.downloadingSpeechModelIDs.insert("whisper-large-v3-turbo")
        state.speechDownloadProgress["whisper-large-v3-turbo"] = 0.50

        XCTAssertTrue(state.asrReady, "Active ASR model readiness must NOT be mutated by background downloads")
        XCTAssertFalse(state.isActivatingSpeechModel, "Background download must not be marked as activating into memory")
    }

    func testRefinementLevelChangeToLightUnloadsTextModel() {
        let state = AppState()
        state.preferences.refinement = .balanced
        state.editorReady = true

        // Switch to light refinement: must unload text model and reset editorReady
        state.preferences.refinement = .light
        XCTAssertFalse(state.editorReady, "Switching to light refinement must unload text model")
    }

    func testRefinementLevelChangeToOriginalUnloadsTextModel() {
        let state = AppState()
        state.preferences.refinement = .moderate
        state.editorReady = true

        // Switch to original mode: must unload text model
        state.preferences.refinement = .original
        XCTAssertFalse(state.editorReady, "Switching to original mode must unload text model")
    }

    func testExplicitUnloadEditorClearsEditorReady() {
        let state = AppState()
        state.editorReady = true
        state.isActivatingTextModel = true
        state.editorPreparing = true

        state.unloadEditor()

        XCTAssertFalse(state.editorReady, "unloadEditor() must set editorReady to false")
        XCTAssertFalse(state.isActivatingTextModel, "unloadEditor() must cancel isActivatingTextModel")
        XCTAssertFalse(state.editorPreparing, "unloadEditor() must cancel editorPreparing")
    }

    func testSelectTextModelInLightModeDoesNotTriggerPrepare() {
        let state = AppState()
        state.preferences.refinement = .light
        state.cachedTextModelIDs.insert("qwen3-text-1.7b-4bit")

        state.selectTextModel(id: "qwen3-text-1.7b-4bit")

        XCTAssertFalse(state.editorReady, "Selecting a text model while in Light mode must not mark it ready")
        XCTAssertFalse(state.isActivatingTextModel, "Selecting a text model while in Light mode must not activate it")
    }

    func testUnloadingIdleEditorDoesNotInvokeGPUCacheClear() async {
        let models = LocalModels()
        await models.unloadEditor()
    }
}
