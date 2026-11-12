import XCTest
import AVFoundation
import Qwen3ASR
import SpeechVAD
import Qwen3Chat
@testable import VoiceBuddyCore

final class LocalModelIntegrationTests: XCTestCase {
    func testLocallyCachedModelRecognizesSample() async throws {
        guard let path = ProcessInfo.processInfo.environment["VOICE_BUDDY_TEST_AUDIO"] else {
            throw XCTSkip("Set VOICE_BUDDY_TEST_AUDIO to a 16kHz mono WAV to run the real model test.")
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceBuddy/Models")
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        XCTAssertEqual(file.processingFormat.sampleRate, 16000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let vad = try await SileroVADModel.fromPretrained(cacheDir: root.appendingPathComponent("silero-vad"), offlineMode: true)
        XCTAssertFalse(vad.detectSpeech(audio: samples, sampleRate: 16000).isEmpty)
        let asr = try await Qwen3ASRModel.fromPretrained(modelId: "mlx-community/Qwen3-ASR-0.6B-8bit", cacheDir: root.appendingPathComponent("qwen-asr-0.6b"), offlineMode: true)
        let text = try asr.transcribeThrowing(audio: samples, sampleRate: 16000, options: .init(language: "English"))
        XCTAssertTrue(text.lowercased().contains("meeting"), "Expected a meeting in the synthetic English test sample")
    }
}


extension LocalModelIntegrationTests {
    func testLocallyCachedTextModelProducesResponse() async throws {
        guard ProcessInfo.processInfo.environment["VOICE_BUDDY_TEST_TEXT"] == "1" else { throw XCTSkip("Set VOICE_BUDDY_TEST_TEXT=1 to run real text model test.") }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceBuddy/models/qwen35-text-0.8b-int5")
        let model = try await Qwen35MLXChat.fromPretrained(cacheDir: root, offlineMode: false)
        let sampling = ChatSamplingConfig(temperature: 0.15, maxTokens: 512, repetitionPenalty: 1.05)

        for mode in [Refinement.light, Refinement.balanced, Refinement.moderate, Refinement.rewrite] {
            guard let prompt = RefinementPrompts.prompt(for: mode) else { continue }

            let testInputs = [
                "明天下午三点开会，讨论一下那个，呃，新版本的发布计划",
                "帮我写一封给老板的请假邮件吧就说我明天有点发烧去不了",
                "为什么那个macos上的docker这么卡呀是不是内存不够了"
            ]

            for input in testInputs {
                let output = try model.generate(messages: [
                    .init(role: .system, content: prompt),
                    .init(role: .user, content: "<asr_text>\(input)</asr_text>"),
                    .init(role: .assistant, content: "<polished_text>")
                ], sampling: sampling)

                var clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if let endTag = clean.range(of: "</polished_text>") {
                    clean = String(clean[..<endTag.lowerBound])
                } else if let endP = clean.range(of: "</p>") {
                    clean = String(clean[..<endP.lowerBound])
                }
                print("--- [Mode: \(mode.rawValue)] [Input: \(input)] -> [\(clean)] ---")
                XCTAssertFalse(clean.isEmpty, "Output must not be empty")
                XCTAssertNil(TextCleanup.unsafeReason(clean, original: input), "Output must pass safety check")
            }
        }
    }
}
