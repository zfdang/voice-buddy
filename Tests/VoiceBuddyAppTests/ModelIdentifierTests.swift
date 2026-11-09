import XCTest
@testable import VoiceBuddyApp

final class ModelIdentifierTests: XCTestCase {
    func testWhisperSpeechModelSpecExists() {
        let whisper = SpeechModelSpec.allModels.first { $0.id == "whisper-large-v3-turbo" }
        XCTAssertNotNil(whisper)
        XCTAssertEqual(whisper?.name, "Whisper Large v3 Turbo")
        XCTAssertEqual(whisper?.quantization, "CoreML")
        XCTAssertFalse(whisper?.size.isEmpty ?? true)
        XCTAssertFalse(whisper?.description.isEmpty ?? true)
        XCTAssertFalse(whisper?.descriptionEn.isEmpty ?? true)
    }

    func testInvalidSpeechModelCannotBeRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let existingModel = root.appendingPathComponent("qwen-asr-0.6b")
        try FileManager.default.createDirectory(at: existingModel, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = LocalModels(root: root)
        for id in ["", "unknown", "qwen-asr-1.7b/../../other"] {
            do {
                try await models.removeSpeech(id: id)
                XCTFail("Invalid model identifier was accepted: \(id)")
            } catch { }
            XCTAssertTrue(FileManager.default.fileExists(atPath: existingModel.path))
        }
    }

    func testWhisperCacheDetectionAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = LocalModels(root: root)

        // Initially not cached
        let isCachedBefore = await models.isSpeechModelCached(id: "whisper-large-v3-turbo")
        XCTAssertFalse(isCachedBefore)

        // Create silero-vad
        let vadDir = root.appendingPathComponent("silero-vad")
        try FileManager.default.createDirectory(at: vadDir, withIntermediateDirectories: true)
        try Data([0x01]).write(to: vadDir.appendingPathComponent("model.safetensors"))

        // Create whisper files
        let whisperDir = root.appendingPathComponent("whisper-large-v3-turbo")
        let required = [
            "MelSpectrogram.mlmodelc/weights/weight.bin",
            "AudioEncoder.mlmodelc/weights/weight.bin",
            "TextDecoder.mlmodelc/weights/weight.bin",
            "TextDecoderContextPrefill.mlmodelc/weights/weight.bin",
            "generation_config.json",
            "tokenizer.json"
        ]
        for rel in required {
            let fileURL = whisperDir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x01]).write(to: fileURL)
        }

        let isCachedAfter = await models.isSpeechModelCached(id: "whisper-large-v3-turbo")
        XCTAssertTrue(isCachedAfter)

        // Remove model
        try await models.removeSpeech(id: "whisper-large-v3-turbo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: whisperDir.path))
        let isCachedAfterRemove = await models.isSpeechModelCached(id: "whisper-large-v3-turbo")
        XCTAssertFalse(isCachedAfterRemove)
    }
}
