import Foundation
import Qwen3ASR
import SpeechVAD
import Qwen3Chat
import VoiceBuddyCore

public struct TextModelSpec: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let size: String
    public let quantization: String
    public let description: String
    public let descriptionEn: String

    public static let allModels: [TextModelSpec] = [
        TextModelSpec(
            id: "qwen35-text-0.8b-int5",
            name: "Qwen 3.5 0.8B",
            size: "494 MB",
            quantization: "INT5",
            description: "极速轻量 · 显存占用极低，推荐日常快速听写与标点整理",
            descriptionEn: "Ultra-lightweight · Minimal memory footprint, recommended for fast dictation and punctuation"
        ),
        TextModelSpec(
            id: "qwen35-text-0.8b-int8",
            name: "Qwen 3.5 0.8B",
            size: "763 MB",
            quantization: "INT8",
            description: "高精量化 · 表达更加严谨细腻，推荐正式长文与重写润色",
            descriptionEn: "Higher precision · Rigorous and nuanced phrasing, recommended for long-form rewrite and polishing"
        )
    ]
}

actor LocalModels: TranscriptionEngine, SpeechDetector, TextRefinementEngine {
    private var asr: Qwen3ASRModel?
    private var vad: SileroVADModel?
    private var editor: Qwen35MLXChat?
    private var selectedID = ""
    private var selectedEditorID = ""
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceBuddy/Models", isDirectory: true)
    private func directory(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
    private func speechDirectory(_ id: String) -> URL { directory(id.contains("1.7B") ? "qwen-asr-1.7b" : "qwen-asr-0.6b") }
    private func textDirectory(_ id: String) -> URL { directory(id) }

    func isSpeechModelCached(id: String) -> Bool {
        let dir = speechDirectory(id)
        let vadDir = directory("silero-vad")
        var isDir: ObjCBool = false
        let hasAsr = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue
        let hasVad = FileManager.default.fileExists(atPath: vadDir.path, isDirectory: &isDir) && isDir.boolValue
        return hasAsr && hasVad
    }

    func isEditorModelCached(id: String? = nil) -> Bool {
        let targetId = id ?? "qwen35-text-0.8b-int5"
        let dir = textDirectory(targetId)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue {
            return true
        }
        if targetId == "qwen35-text-0.8b-int5" {
            let legacy = directory("qwen35-text-0.8b")
            return FileManager.default.fileExists(atPath: legacy.path, isDirectory: &isDir) && isDir.boolValue
        }
        return false
    }

    func prepareSpeech(id: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        if asr == nil || selectedID != id {
            asr = try await Qwen3ASRModel.fromPretrained(modelId: id, cacheDir: speechDirectory(id), progressHandler: { value, message in progress(value * 0.9, message) })
            selectedID = id
        }
        if vad == nil { vad = try await SileroVADModel.fromPretrained(cacheDir: directory("silero-vad"), progressHandler: { value, message in progress(0.9 + value * 0.1, message) }) }
    }

    func prepareEditor(id: String? = nil, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let targetId = id ?? "qwen35-text-0.8b-int5"
        let q: Qwen35MLXChat.Quantization = targetId.contains("int8") ? .int8 : .int5
        var dir = textDirectory(targetId)
        if targetId == "qwen35-text-0.8b-int5" && !FileManager.default.fileExists(atPath: dir.path) {
            let legacy = directory("qwen35-text-0.8b")
            if FileManager.default.fileExists(atPath: legacy.path) {
                dir = legacy
            }
        }
        if editor == nil || selectedEditorID != targetId {
            editor = try await Qwen35MLXChat.fromPretrained(quantization: q, cacheDir: dir, progressHandler: progress)
            selectedEditorID = targetId
        }
    }

    func removeSpeech(id: String) throws {
        if selectedID == id { asr = nil; selectedID = "" }
        let path = speechDirectory(id); if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }

    func removeEditor(id: String? = nil) throws {
        let targetId = id ?? selectedEditorID
        if selectedEditorID == targetId {
            editor = nil
            selectedEditorID = ""
        }
        let path = textDirectory(targetId)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        if targetId == "qwen35-text-0.8b-int5" {
            let legacy = directory("qwen35-text-0.8b")
            if FileManager.default.fileExists(atPath: legacy.path) {
                try FileManager.default.removeItem(at: legacy)
            }
        }
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
