import XCTest
@testable import VoiceBuddyCore

private struct DummySpeechDetector: SpeechDetector {
    func containsSpeech(_ samples: [Float]) async throws -> Bool { !samples.isEmpty }
}

private struct DummyRefiner: TextRefinementEngine {
    func refine(_ text: String, mode: Refinement) async throws -> String { text }
}

private actor ContextCapturingTranscriber: TranscriptionEngine {
    private(set) var recordedContexts: [String?] = []

    func transcribe(samples: [Float], language: String) async throws -> String {
        try await transcribe(samples: samples, language: language, context: nil)
    }

    func transcribe(samples: [Float], language: String, context: String?) async throws -> String {
        recordedContexts.append(context)
        return "ok"
    }
}

final class DeveloperASRContextTests: XCTestCase {
    func testDeveloperVocabularyIsDenseDeduplicatedAndNonEmpty() {
        let terms = DeveloperASRContext.terms
        XCTAssertGreaterThanOrEqual(terms.count, 180)
        XCTAssertEqual(Set(terms).count, terms.count, "Duplicate terms found in DeveloperASRContext.terms")
        XCTAssertTrue(terms.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        XCTAssertTrue(terms.contains("GitHub"))
        XCTAssertTrue(terms.contains("SwiftUI"))
        XCTAssertTrue(terms.contains("Qwen3"))
        XCTAssertTrue(terms.contains("Kubernetes"))
        XCTAssertTrue(terms.contains("TypeScript"))
        XCTAssertTrue(terms.contains("rebase"))
    }

    func testContextHelperRespectsEnabledFlag() {
        XCTAssertNil(DeveloperASRContext.context(enabled: false))
        let enabledContext = DeveloperASRContext.context(enabled: true)
        XCTAssertEqual(enabledContext, DeveloperASRContext.contextString)
        XCTAssertTrue(enabledContext?.contains("SwiftUI") == true)
        XCTAssertTrue(enabledContext?.contains("GitHub") == true)
    }

    func testPreferencesDefaultsAndBackwardCompatibleDecoding() throws {
        let defaults = Preferences()
        XCTAssertTrue(defaults.developerContextEnabled)

        let legacyJSON = Data(#"{"speechModel":"qwen-asr-0.6b","speechLanguage":"auto"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(Preferences.self, from: legacyJSON)
        XCTAssertTrue(decodedLegacy.developerContextEnabled)

        var disabledPrefs = Preferences()
        disabledPrefs.developerContextEnabled = false
        let encoded = try JSONEncoder().encode(disabledPrefs)
        let decodedDisabled = try JSONDecoder().decode(Preferences.self, from: encoded)
        XCTAssertFalse(decodedDisabled.developerContextEnabled)
    }

    func testPipelineForwardsOptionalContextToTranscriptionEngine() async throws {
        let transcriber = ContextCapturingTranscriber()
        let pipeline = Pipeline(
            detector: DummySpeechDetector(),
            transcription: transcriber,
            refinement: DummyRefiner()
        )

        _ = try await pipeline.run(samples: [0.1, 0.2], language: "auto", mode: .original)
        _ = try await pipeline.run(
            samples: [0.1, 0.2],
            language: "auto",
            mode: .original,
            context: DeveloperASRContext.context(enabled: true)
        )

        let captured = await transcriber.recordedContexts
        XCTAssertEqual(captured.count, 2)
        XCTAssertNil(captured[0])
        XCTAssertEqual(captured[1], DeveloperASRContext.contextString)
    }
}
