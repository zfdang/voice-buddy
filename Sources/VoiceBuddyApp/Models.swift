import Foundation
import Qwen3ASR
import SpeechVAD
import Qwen3Chat
import VoiceBuddyCore

public struct SpeechModelSpec: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let size: String
    public let quantization: String
    public let description: String
    public let descriptionEn: String

    public static let allModels: [SpeechModelSpec] = [
        SpeechModelSpec(
            id: "qwen-asr-0.6b",
            name: "Qwen 3 ASR 0.6B",
            size: "960 MB",
            quantization: "8-bit",
            description: "极速轻量 · 推荐日常快速听写与中英混说，显存占用极低",
            descriptionEn: "Ultra-fast & lightweight · Recommended for daily dictation, minimal memory footprint"
        ),
        SpeechModelSpec(
            id: "qwen-asr-1.7b",
            name: "Qwen 3 ASR 1.7B",
            size: "1.7 GB",
            quantization: "8-bit",
            description: "高精旗舰 · 复杂术语、长句及多语种识别更严谨细腻",
            descriptionEn: "Flagship precision · Highly accurate for complex terms, long sentences, and multilingual speech"
        )
    ]
}

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
    private func speechDirectory(_ id: String) -> URL { directory(id.contains("1.7") ? "qwen-asr-1.7b" : "qwen-asr-0.6b") }
    private func textDirectory(_ id: String) -> URL { directory(id) }

    func isSpeechModelCached(id: String) -> Bool {
        let dir = speechDirectory(id)
        let vadDir = directory("silero-vad")
        return hasSafetensors(in: dir) && hasSafetensors(in: vadDir)
    }

    func isEditorModelCached(id: String? = nil) -> Bool {
        let targetId = id ?? "qwen35-text-0.8b-int5"
        let dir = textDirectory(targetId)
        if hasSafetensors(in: dir) {
            return true
        }
        if targetId == "qwen35-text-0.8b-int5" {
            let legacy = directory("qwen35-text-0.8b")
            return hasSafetensors(in: legacy)
        }
        return false
    }

    private func hasSafetensors(in dir: URL) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        for f in files {
            if f.hasSuffix(".safetensors") && !f.hasPrefix(".") {
                return true
            }
            var isDir: ObjCBool = false
            let sub = dir.appendingPathComponent(f)
            if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue, !f.hasPrefix(".") {
                if hasSafetensors(in: sub) { return true }
            }
        }
        return false
    }

    func prepareSpeech(id: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard SpeechModelSpec.allModels.contains(where: { $0.id == id }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid speech model identifier")
        }
        let isCached = isSpeechModelCached(id: id)
        let hfModelId = (id.contains("1.7") || id.contains("large")) ? "mlx-community/Qwen3-ASR-1.7B-8bit" : "mlx-community/Qwen3-ASR-0.6B-8bit"
        if asr == nil || selectedID != id {
            asr = try await Qwen3ASRModel.fromPretrained(
                modelId: hfModelId,
                cacheDir: speechDirectory(id),
                offlineMode: isCached,
                progressHandler: { value, message in progress(value * 0.9, message) }
            )
            selectedID = id
        }
        if vad == nil {
            let vadCached = hasSafetensors(in: directory("silero-vad"))
            vad = try await SileroVADModel.fromPretrained(
                cacheDir: directory("silero-vad"),
                offlineMode: vadCached,
                progressHandler: { value, message in progress(0.9 + value * 0.1, message) }
            )
        }
    }

    func prepareEditor(id: String? = nil, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let targetId = id ?? "qwen35-text-0.8b-int5"
        guard TextModelSpec.allModels.contains(where: { $0.id == targetId }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid text model identifier")
        }
        let q: Qwen35MLXChat.Quantization = targetId.contains("int8") ? .int8 : .int5
        var dir = textDirectory(targetId)
        if targetId == "qwen35-text-0.8b-int5" && !FileManager.default.fileExists(atPath: dir.path) {
            let legacy = directory("qwen35-text-0.8b")
            if FileManager.default.fileExists(atPath: legacy.path) {
                dir = legacy
            }
        }
        if editor == nil || selectedEditorID != targetId {
            editor = try await Qwen35MLXChat.fromPretrained(
                quantization: q,
                cacheDir: dir,
                progressHandler: progress
            )
            selectedEditorID = targetId
        }
    }

    func removeSpeech(id: String) throws {
        guard SpeechModelSpec.allModels.contains(where: { $0.id == id }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid speech model identifier")
        }
        if selectedID == id { asr = nil; selectedID = "" }
        let path = speechDirectory(id); if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }

    func removeEditor(id: String? = nil) throws {
        let targetId = id ?? selectedEditorID
        guard TextModelSpec.allModels.contains(where: { $0.id == targetId }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid text model identifier")
        }
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
        let tokenBudget = max(512, min(text.count * 4 + 128, 2048))
        let generated = try editor.generate(
            messages: [.init(role: .system, content: instruction), .init(role: .user, content: text)],
            sampling: .init(temperature: 0, maxTokens: tokenBudget)
        )
        let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenCount = editor.tokenizer.encode(trimmed).count
        if tokenCount >= tokenBudget || (text.count >= 40 && trimmed.count < max(12, text.count / 3)) {
            throw RefinementFailure(original: text, reason: "Refinement output exceeded token budget or was truncated")
        }
        return trimmed
    }
}
