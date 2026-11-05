import Foundation
import Qwen3ASR
import SpeechVAD
import Qwen3Chat
import VoiceBuddyCore

actor LocalModels: TranscriptionEngine, SpeechDetector, TextRefinementEngine {
    private var asr: Qwen3ASRModel?
    private var vad: SileroVADModel?
    private var editor: Qwen35MLXChat?
    private var selectedID = ""
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceBuddy/Models", isDirectory: true)
    private func directory(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
    private func speechDirectory(_ id: String) -> URL { directory(id.contains("1.7B") ? "qwen-asr-1.7b" : "qwen-asr-0.6b") }

    func isSpeechModelCached(id: String) -> Bool {
        let dir = speechDirectory(id)
        let vadDir = directory("silero-vad")
        var isDir: ObjCBool = false
        let hasAsr = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue
        let hasVad = FileManager.default.fileExists(atPath: vadDir.path, isDirectory: &isDir) && isDir.boolValue
        return hasAsr && hasVad
    }

    func isEditorModelCached() -> Bool {
        let dir = directory("qwen35-text-0.8b")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue
    }

    func prepareSpeech(id: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        if asr == nil || selectedID != id {
            asr = try await Qwen3ASRModel.fromPretrained(modelId: id, cacheDir: speechDirectory(id), progressHandler: { value, message in progress(value * 0.9, message) })
            selectedID = id
        }
        if vad == nil { vad = try await SileroVADModel.fromPretrained(cacheDir: directory("silero-vad"), progressHandler: { value, message in progress(0.9 + value * 0.1, message) }) }
    }
    func prepareEditor(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        if editor == nil { editor = try await Qwen35MLXChat.fromPretrained(cacheDir: directory("qwen35-text-0.8b"), progressHandler: progress) }
    }
    func removeSpeech(id: String) throws {
        if selectedID == id { asr = nil; selectedID = "" }
        let path = speechDirectory(id); if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
    func removeEditor() throws {
        editor = nil
        let path = directory("qwen35-text-0.8b"); if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
    func containsSpeech(_ samples: [Float]) async throws -> Bool {
        guard let vad else { throw VoiceBuddyError.modelUnavailable("VAD") }
        vad.resetState()
        return !vad.detectSpeech(audio: samples, sampleRate: 16000).isEmpty
    }
    func transcribe(samples: [Float], language: String) async throws -> String {
        guard let asr else { throw VoiceBuddyError.modelUnavailable("ASR") }
        return try asr.transcribeThrowing(audio: samples, sampleRate: 16000, options: Qwen3DecodingOptions(language: language == "auto" ? nil : language))
    }
    func refine(_ text: String, mode: Refinement) async throws -> String {
        guard let editor else { throw VoiceBuddyError.modelUnavailable("Text model") }
        let instruction = mode == .rewrite ? "Rewrite the dictated text clearly. Preserve facts. Output only the rewritten text." : "Edit the dictated text lightly for clarity and punctuation. Preserve all facts, language and meaning. Output only the edited text."
        return try editor.generate(messages: [.init(role: .system, content: instruction), .init(role: .user, content: text)], sampling: .init(temperature: 0, maxTokens: min(max(text.count * 3, 64), 256)))
    }
}
