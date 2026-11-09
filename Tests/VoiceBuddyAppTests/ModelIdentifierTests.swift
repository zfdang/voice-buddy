import XCTest
@testable import VoiceBuddyApp

final class ModelIdentifierTests: XCTestCase {
    func testAllSpeechModelSpecsExistAndHaveRichMetadata() {
        let expectedIds = ["qwen-asr-0.6b", "qwen-asr-1.7b", "whisper-large-v3-turbo", "sensevoice-small", "apple-speech"]
        XCTAssertEqual(SpeechModelSpec.allModels.count, expectedIds.count)
        for id in expectedIds {
            guard let spec = SpeechModelSpec.allModels.first(where: { $0.id == id }) else {
                XCTFail("Missing expected model: \(id)")
                continue
            }
            XCTAssertFalse(spec.name.isEmpty)
            XCTAssertFalse(spec.size.isEmpty)
            XCTAssertFalse(spec.quantization.isEmpty)
            XCTAssertFalse(spec.latency.isEmpty)
            XCTAssertTrue(spec.speedRating >= 1 && spec.speedRating <= 5)
            XCTAssertFalse(spec.languagesZh.isEmpty)
            XCTAssertFalse(spec.languagesEn.isEmpty)
            XCTAssertFalse(spec.accuracyScore.isEmpty)
            XCTAssertFalse(spec.accuracyScoreEn.isEmpty)
            XCTAssertFalse(spec.memoryUsage.isEmpty)
            XCTAssertFalse(spec.bestForZh.isEmpty)
            XCTAssertFalse(spec.bestForEn.isEmpty)
            XCTAssertFalse(spec.description.isEmpty)
            XCTAssertFalse(spec.descriptionEn.isEmpty)
        }
    }

    func testAppleSpeechAlwaysCachedAndNonRemovable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = LocalModels(root: root)

        // Apple Speech is system built-in, always cached
        let isCached = await models.isSpeechModelCached(id: "apple-speech")
        XCTAssertTrue(isCached)

        // Removing Apple Speech is a safe no-op
        try await models.removeSpeech(id: "apple-speech")
        let isStillCached = await models.isSpeechModelCached(id: "apple-speech")
        XCTAssertTrue(isStillCached)
    }

    func testSenseVoiceCacheDetectionAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = LocalModels(root: root)

        let isCachedBefore = await models.isSpeechModelCached(id: "sensevoice-small")
        XCTAssertFalse(isCachedBefore)

        // Create silero-vad
        let vadDir = root.appendingPathComponent("silero-vad")
        try FileManager.default.createDirectory(at: vadDir, withIntermediateDirectories: true)
        try Data([0x01]).write(to: vadDir.appendingPathComponent("model.safetensors"))

        // Create SenseVoice files
        let senseVoiceDir = root.appendingPathComponent("sensevoice-small")
        let preprocessorFile = senseVoiceDir.appendingPathComponent("SenseVoicePreprocessor.mlmodelc/model.mil")
        let encoderFile = senseVoiceDir.appendingPathComponent("SenseVoiceSmall.mlmodelc/weights/weight.bin")
        let vocabFile = senseVoiceDir.appendingPathComponent("vocab.json")

        try FileManager.default.createDirectory(at: preprocessorFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: encoderFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x01]).write(to: preprocessorFile)
        try Data([0x01]).write(to: encoderFile)
        try Data("[]".utf8).write(to: vocabFile)

        let isCachedAfter = await models.isSpeechModelCached(id: "sensevoice-small")
        XCTAssertTrue(isCachedAfter)

        try await models.removeSpeech(id: "sensevoice-small")
        XCTAssertFalse(FileManager.default.fileExists(atPath: senseVoiceDir.path))
        let isCachedAfterRemove = await models.isSpeechModelCached(id: "sensevoice-small")
        XCTAssertFalse(isCachedAfterRemove)
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

    func testDownloadSpeechInstantForAppleSpeech() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = LocalModels(root: root)

        final class ProgressBox: @unchecked Sendable {
            var completed = false
        }
        let box = ProgressBox()

        try await models.downloadSpeech(id: "apple-speech") { progress, message in
            if progress >= 1.0 {
                box.completed = true
            }
        }
        XCTAssertTrue(box.completed)
    }

    func testDownloadSpeechRejectsInvalidModel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = LocalModels(root: root)

        do {
            try await models.downloadSpeech(id: "non-existent-model") { _, _ in }
            XCTFail("Should throw for invalid model")
        } catch {
            // Success
        }
    }
}
