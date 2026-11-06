import XCTest
@testable import VoiceBuddyApp

final class ModelIdentifierTests: XCTestCase {
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
}
