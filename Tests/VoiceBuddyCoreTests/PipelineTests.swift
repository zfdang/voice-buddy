import XCTest
@testable import VoiceBuddyCore

private struct Detector: SpeechDetector { let value: Bool; func containsSpeech(_ samples: [Float]) async throws -> Bool { value } }
private struct ASR: TranscriptionEngine { let text: String; func transcribe(samples: [Float], language: String) async throws -> String { text } }
private struct Editor: TextRefinementEngine { let text: String; func refine(_ text: String, mode: Refinement) async throws -> String { self.text } }

final class PipelineTests: XCTestCase {
    func testSilenceRejected() async throws {
        let pipeline = Pipeline(detector: Detector(value: false), transcription: ASR(text: "x"), refinement: Editor(text: "y"))
        do { _ = try await pipeline.run(samples: [0], language: "auto", mode: .light); XCTFail("Expected silence") }
        catch { XCTAssertEqual(error as? VoiceBuddyError, .noSpeech) }
    }
    func testOriginalAndLight() async throws {
        let p = Pipeline(detector: Detector(value: true), transcription: ASR(text: "  hello   world  "), refinement: Editor(text: "edited"))
        let raw = try await p.run(samples: [1], language: "en", mode: .original)
        let light = try await p.run(samples: [1], language: "en", mode: .light)
        XCTAssertEqual(raw.result, "hello   world"); XCTAssertEqual(light.result, "hello world")
    }
    func testRefinementAndEmptyResponse() async throws {
        let p = Pipeline(detector: Detector(value: true), transcription: ASR(text: "hello"), refinement: Editor(text: "rewritten"))
        let value = try await p.run(samples: [1], language: "en", mode: .rewrite)
        XCTAssertEqual(value.original, "hello"); XCTAssertEqual(value.result, "rewritten")
        let empty = Pipeline(detector: Detector(value: true), transcription: ASR(text: "hello"), refinement: Editor(text: ""))
        do { _ = try await empty.run(samples: [1], language: "auto", mode: .moderate); XCTFail("Expected error") } catch { XCTAssertEqual((error as? RefinementFailure)?.original, "hello") }
    }
    func testPreferencesRoundTrip() throws {
        var settings = Preferences(); settings.speechLanguage = "zh"; settings.refinement = .rewrite
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings)), settings)
    }
}

private struct FailingASR: TranscriptionEngine {
    func transcribe(samples: [Float], language: String) async throws -> String { throw VoiceBuddyError.modelUnavailable("ASR") }
}
private struct FailingEditor: TextRefinementEngine {
    func refine(_ text: String, mode: Refinement) async throws -> String { throw VoiceBuddyError.modelUnavailable("editor") }
}
extension PipelineTests {
    func testModelFailurePreservesOriginal() async throws {
        let p = Pipeline(detector: Detector(value: true), transcription: ASR(text: "important words"), refinement: FailingEditor())
        do { _ = try await p.run(samples: [1], language: "en", mode: .moderate); XCTFail("Expected failure") }
        catch let failure as RefinementFailure { XCTAssertEqual(failure.original, "important words") }
    }
    func testEmptySamplesNeverRunASR() async throws {
        let p = Pipeline(detector: Detector(value: true), transcription: FailingASR(), refinement: Editor(text: ""))
        do { _ = try await p.run(samples: [], language: "en", mode: .light); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? VoiceBuddyError, .noSpeech) }
    }
    func testASRErrorIsNotPretendSuccess() async throws {
        let p = Pipeline(detector: Detector(value: true), transcription: FailingASR(), refinement: Editor(text: ""))
        do { _ = try await p.run(samples: [1], language: "en", mode: .original); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? VoiceBuddyError, .modelUnavailable("ASR")) }
    }
}

private actor SpyASR: TranscriptionEngine {
    private(set) var language = ""
    func transcribe(samples: [Float], language: String) async throws -> String { self.language = language; return "你好  world" }
}
private actor SpyEditor: TextRefinementEngine {
    private(set) var calls = 0
    func refine(_ text: String, mode: Refinement) async throws -> String { calls += 1; return text }
}
extension PipelineTests {
    func testLanguagePropagatesAndOriginalDoesNotCallEditor() async throws {
        let asr = SpyASR(); let editor = SpyEditor()
        let pipeline = Pipeline(detector: Detector(value: true), transcription: asr, refinement: editor)
        _ = try await pipeline.run(samples: [0.5], language: "French", mode: .original)
        let language = await asr.language; let calls = await editor.calls
        XCTAssertEqual(language, "French"); XCTAssertEqual(calls, 0)
    }
    func testLightPreservesWordsAndNewlines() {
        XCTAssertEqual(TextCleanup.light("  你好  world\nnext  line \n"), "你好 world\nnext line")
    }
    func testEmptyTranscriptCannotProceed() async throws {
        let p = Pipeline(detector: Detector(value: true), transcription: ASR(text: "  \n "), refinement: Editor(text: "unexpected"))
        do { _ = try await p.run(samples: [1], language: "auto", mode: .moderate); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? VoiceBuddyError, .emptyTranscript) }
    }
}

extension PipelineTests {
    func testRejectsModelPlaceholderOrLostNumbers() {
        XCTAssertFalse(TextCleanup.looksSafe("<think>reasoning</think>", original: "明天下午三点开会"))
        XCTAssertFalse(TextCleanup.looksSafe("corrected text here", original: "明天下午三点开会"))
        XCTAssertFalse(TextCleanup.looksSafe("I am ready to help", original: "帮我整理这一段"))
        XCTAssertFalse(TextCleanup.looksSafe("As an AI, here is the text", original: "明天下午三点开会"))
        XCTAssertFalse(TextCleanup.looksSafe("明天下午开会", original: "明天下午三点开会"))
        XCTAssertTrue(TextCleanup.looksSafe("明天下午三点开会。", original: "明天下午三点开会"))
    }
    func testLightRemovesFillersAndPreservesSelfCorrection() {
        let input = "明天，啊不，周五跟小王讨论预算，嗯，大概十万"
        let output = TextCleanup.light(input)
        XCTAssertEqual(output, "明天，啊不，周五跟小王讨论预算，大概十万")
        XCTAssertEqual(TextCleanup.light("嗯，今天天气真好"), "今天天气真好")
    }
    func testPreferencesDefaults() {
        let prefs = Preferences()
        XCTAssertEqual(prefs.interfaceLanguage, "system")
        XCTAssertEqual(prefs.speechLanguage, "auto")
        XCTAssertEqual(prefs.speechModel, "mlx-community/Qwen3-ASR-0.6B-8bit")
        XCTAssertEqual(prefs.refinement, .light)
        XCTAssertTrue(prefs.sounds)
        XCTAssertTrue(prefs.autoInsert)
        XCTAssertEqual(prefs.shortcutKeyCode, 49)
        XCTAssertEqual(prefs.shortcutModifiers, 6144)
    }
    func testGestureReset() {
        var gesture = HotkeyGesture()
        XCTAssertEqual(gesture.press(hold: true), .startHold)
        XCTAssertTrue(gesture.isDown)
        gesture.reset()
        XCTAssertFalse(gesture.isDown)
        XCTAssertEqual(gesture.press(hold: true), .startHold)
    }
    func testVoiceBuddyErrorDescriptions() {
        XCTAssertEqual(VoiceBuddyError.noSpeech.errorDescription, "No speech detected.")
        XCTAssertEqual(VoiceBuddyError.emptyTranscript.errorDescription, "No text was recognized.")
        XCTAssertEqual(VoiceBuddyError.unsafeTarget.errorDescription, "The input focus changed. Copy the result manually.")
        XCTAssertEqual(VoiceBuddyError.modelUnavailable("TestModel").errorDescription, "Model unavailable: TestModel")
    }
}

extension PipelineTests {
    func testLegacyPreferencesDefaultToHoldMode() throws {
        let data = try JSONEncoder().encode(Preferences())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); object.removeValue(forKey: "holdToTalk")
        let old = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.holdToTalk ?? true)
    }
}
extension PipelineTests {
    func testHoldGestureStartsOnceAndStopsOnRelease() {
        var gesture = HotkeyGesture()
        XCTAssertEqual(gesture.press(hold: true), .startHold)
        XCTAssertEqual(gesture.press(hold: true), .none)
        XCTAssertEqual(gesture.release(hold: true), .stopHold)
        XCTAssertEqual(gesture.release(hold: true), .none)
    }
    func testToggleGestureIgnoresReleaseAndRepeats() {
        var gesture = HotkeyGesture()
        XCTAssertEqual(gesture.press(hold: false), .toggle)
        XCTAssertEqual(gesture.press(hold: false), .none)
        XCTAssertEqual(gesture.release(hold: false), .none)
        XCTAssertEqual(gesture.press(hold: false), .toggle)
    }
}
