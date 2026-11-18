import XCTest
import AVFoundation
import Qwen3ASR
@testable import VoiceBuddyCore
@testable import VoiceBuddyApp

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
    func testDeveloperVocabularyIsCompactDeduplicatedAndFreeOfEverydayAmbiguousWords() {
        let terms = DeveloperASRContext.terms
        XCTAssertTrue((55...85).contains(terms.count), "Expected compact vocabulary in 55...85, got \(terms.count)")
        XCTAssertEqual(Set(terms).count, terms.count, "Duplicate terms found in DeveloperASRContext.terms")
        XCTAssertTrue(terms.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        // Verify semantic duplicates and common everyday homographs are excluded
        for excluded in ["k8s", "Postgres", "Go", "main", "log", "class", "index", "bug", "fix", "cache"] {
            XCTAssertFalse(terms.contains(excluded), "Ambiguous or duplicate term '\(excluded)' should be excluded")
        }

        // Core proper nouns remain
        for required in ["GitHub", "SwiftUI", "Kubernetes", "PostgreSQL", "TypeScript", "rebase", "Qwen"] {
            XCTAssertTrue(terms.contains(required))
        }
    }

    func testContextHelperAndNormalizer() {
        XCTAssertNil(DeveloperASRContext.context(enabled: false))
        let enabled = DeveloperASRContext.context(enabled: true)
        XCTAssertEqual(enabled, DeveloperASRContext.contextString)
        XCTAssertFalse(enabled?.contains("Software engineering") ?? true)

        XCTAssertNil(Qwen3ASRContextNormalizer.normalize(nil))
        XCTAssertNil(Qwen3ASRContextNormalizer.normalize(""))
        XCTAssertNil(Qwen3ASRContextNormalizer.normalize("   \n\t  "))
        XCTAssertEqual(Qwen3ASRContextNormalizer.normalize("  GitHub, SwiftUI \n "), "GitHub, SwiftUI")
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
            detector: AlwaysSpeechDetector(),
            transcription: transcriber,
            refinement: IdentityRefiner()
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

    func testRealCachedQwen3ASRContextABEvaluation() async throws {
        guard let dir = ProcessInfo.processInfo.environment["VOICE_BUDDY_BENCH_ASR_DIR"] else {
            throw XCTSkip("Set VOICE_BUDDY_BENCH_ASR_DIR to run real Qwen3-ASR A/B benchmark.")
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceBuddy/Models/qwen-asr-0.6b")
        let asr = try await Qwen3ASRModel.fromPretrained(
            modelId: "mlx-community/Qwen3-ASR-0.6B-8bit",
            cacheDir: root,
            offlineMode: true
        )

        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".wav") }.sorted()
        XCTAssertFalse(files.isEmpty)
        for name in files {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: dir).appendingPathComponent(name))
            let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buf)
            let samples = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))

            let t0 = CFAbsoluteTimeGetCurrent()
            let baseline = try asr.transcribeThrowing(audio: samples, sampleRate: 16000, options: Qwen3DecodingOptions(language: nil, context: nil))
            let baseMs = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)

            let t1 = CFAbsoluteTimeGetCurrent()
            let withCtx = try asr.transcribeThrowing(audio: samples, sampleRate: 16000, options: Qwen3DecodingOptions(language: nil, context: DeveloperASRContext.contextString))
            let ctxMs = Int((CFAbsoluteTimeGetCurrent() - t1) * 1000)

            print("AB[\(name)] baseline(\(baseMs)ms)=\(baseline) | dev_ctx(\(ctxMs)ms)=\(withCtx)")
        }
    }
}

private struct AlwaysSpeechDetector: SpeechDetector {
    func containsSpeech(_ samples: [Float]) async throws -> Bool { !samples.isEmpty }
}

private struct IdentityRefiner: TextRefinementEngine {
    func refine(_ text: String, mode: Refinement) async throws -> String { text }
}
