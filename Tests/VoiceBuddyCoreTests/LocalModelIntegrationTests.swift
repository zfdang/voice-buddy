import XCTest
import AVFoundation
import Qwen3ASR
import SpeechVAD
import Qwen3Chat

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
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceBuddy/Models/qwen35-text-0.8b")
        let model = try await Qwen35MLXChat.fromPretrained(cacheDir: root, offlineMode: false)
        let output = try model.generate(messages: [.init(role: .system, content: "正确添加标点，保留全部信息，只输出修改后的文本。"), .init(role: .user, content: "明天下午三点开会")])
        print("Synthetic test output: \(output)")
        XCTAssertTrue(output.contains("三点") || output.contains("3点") || output.contains("3 点"), "Model must preserve the meeting time in the synthetic fixture")
    }
}
