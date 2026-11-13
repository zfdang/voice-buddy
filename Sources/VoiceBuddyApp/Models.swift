import Foundation
import Qwen3ASR
import SpeechVAD
import Qwen3Chat
import VoiceBuddyCore
import WhisperASR

public struct SpeechModelSpec: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let size: String
    public let quantization: String
    public let latency: String
    public let speedRating: Int
    public let languagesZh: String
    public let languagesEn: String
    public let accuracyScore: String
    public let accuracyScoreEn: String
    public let memoryUsage: String
    public let bestForZh: String
    public let bestForEn: String
    public let description: String
    public let descriptionEn: String

    public static let allModels: [SpeechModelSpec] = [
        SpeechModelSpec(
            id: "qwen-asr-0.6b",
            name: "Qwen 3 ASR 0.6B",
            size: "960 MB",
            quantization: "MLX 8-bit",
            latency: "200~400ms",
            speedRating: 4,
            languagesZh: "中文、英文、中英双语混说",
            languagesEn: "Chinese, English, Mixed Speech",
            accuracyScore: "98 分 · 中英混说日常首选",
            accuracyScoreEn: "98 / 100 · Best for Chinglish",
            memoryUsage: "约 1.0 GB 统一内存",
            bestForZh: "日常快速打字、中英夹杂沟通，低资源消耗平衡首选",
            bestForEn: "Daily chat, Chinglish conversation, low memory footprint",
            description: "极速轻量 · 推荐日常快速听写与中英混说，显存占用极低，平衡首选",
            descriptionEn: "Fast & lightweight · Best for daily dictation & Chinglish, minimal memory footprint"
        ),
        SpeechModelSpec(
            id: "qwen-asr-1.7b",
            name: "Qwen 3 ASR 1.7B",
            size: "1.7 GB",
            quantization: "MLX 8-bit",
            latency: "500~900ms",
            speedRating: 3,
            languagesZh: "中英双语、专业术语、多国语种",
            languagesEn: "Chinese, English, Jargon, Global",
            accuracyScore: "99 分 · 专业术语与长句旗舰",
            accuracyScoreEn: "99 / 100 · Flagship for Jargon & Complex Speech",
            memoryUsage: "约 1.8 GB 统一内存",
            bestForZh: "长篇正式讲座、编程代码术语、学术论文等严谨听写",
            bestForEn: "Formal speeches, code dictation, academic and technical terms",
            description: "高精旗舰 · 适合长句、专业学术与编程术语，多语种更严谨细腻",
            descriptionEn: "Flagship precision · Highly accurate for long sentences, technical terms, and multilingual speech"
        ),
        SpeechModelSpec(
            id: "whisper-large-v3-turbo",
            name: "Whisper Large v3 Turbo",
            size: "980 MB",
            quantization: "CoreML",
            latency: "300~600ms",
            speedRating: 4,
            languagesZh: "全球 90+ 语言全覆盖、专业纯英文",
            languagesEn: "90+ Global Languages, Native English",
            accuracyScore: "99 分 · 跨国语言与专业英文霸主",
            accuracyScoreEn: "99 / 100 · SOTA for 90+ Global Languages",
            memoryUsage: "约 1.0 GB 统一内存",
            bestForZh: "国际跨国会议、多语种互译办公、纯英文与专业学术场景",
            bestForEn: "Global meetings, multilingual dictation, and professional English",
            description: "多语旗舰 · 全球 90+ 语言高精听写（首次载入需神经引擎编译约 1~2 分钟，仅一次，后续秒开）",
            descriptionEn: "Multilingual flagship · 90+ languages (First load requires Neural Engine compilation ~1-2 mins, once only, instant thereafter)"
        ),
        SpeechModelSpec(
            id: "sensevoice-small",
            name: "SenseVoice Small",
            size: "230 MB",
            quantization: "CoreML",
            latency: "30~80ms (极速瞬时)",
            speedRating: 5,
            languagesZh: "普通话、粤语、英语、日语、韩语",
            languagesEn: "Mandarin, Cantonese, English, Japanese, Korean",
            accuracyScore: "96 分 · 毫秒级非自回归极速响应",
            accuracyScoreEn: "96 / 100 · Sub-100ms ultra-fast non-autoregressive",
            memoryUsage: "约 250 MB (超低显存)",
            bestForZh: "说话松开按键秒上屏！8GB 内存设备与粤语、日韩语首选",
            bestForEn: "Instant output on key release! Best for 8GB Macs, Cantonese, Japanese, and Korean",
            description: "毫秒极速 · 阿里 FunASR 出品，松键秒上屏，中英粤日韩五语首选，超低显存",
            descriptionEn: "Ultra-fast response · Alibaba FunASR, instant output on key release, ZH/EN/YUE/JA/KO, tiny footprint"
        ),
        SpeechModelSpec(
            id: "apple-speech",
            name: "Apple Speech (系统内置)",
            size: "0 MB (免下载)",
            quantization: "系统原生",
            latency: "100~200ms",
            speedRating: 4,
            languagesZh: "普通话、英语等系统语言",
            languagesEn: "Mandarin, English & System Locales",
            accuracyScore: "90 分 · 开箱即用免下载等待",
            accuracyScoreEn: "90 / 100 · Built-in zero-wait dictation",
            memoryUsage: "近乎 0 MB (系统共享)",
            bestForZh: "依赖系统「听写」开启；免等待下载、离线无网兜底、0 磁盘占用",
            bestForEn: "Requires macOS Dictation enabled; zero download waiting & 0 MB disk footprint",
            description: "系统内置 · 依赖 macOS 听写服务开启，0 磁盘占用，免下载即刻可用",
            descriptionEn: "macOS built-in · Requires macOS Dictation enabled, 0 MB download & disk footprint"
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
        ),
        TextModelSpec(
            id: "qwen3-text-1.7b-4bit",
            name: "Qwen 3 1.7B",
            size: "923 MB",
            quantization: "4-bit",
            description: "逻辑进阶 · Dense 架构，倒装句理顺与口语重构更自然，理解力强",
            descriptionEn: "Advanced logic · Dense transformer, natural spoken-syntax cleanup and strong comprehension"
        ),
        TextModelSpec(
            id: "qwen3-text-4b-4bit",
            name: "Qwen 3 4B",
            size: "2.26 GB",
            quantization: "4-bit",
            description: "深度重写 · 旗舰级指令遵循，深度段落逻辑重构与书面文风润色",
            descriptionEn: "Deep rewrite · Flagship instruction following, structural rewriting and polished prose"
        )
    ]
}

actor LocalModels: TranscriptionEngine, SpeechDetector, TextRefinementEngine {
    private var asr: Qwen3ASRModel?
    private var whisper: WhisperASRModel?
    private var senseVoice: SenseVoiceASRModel?
    private var appleSpeech: AppleSpeechEngine?
    private var vad: SileroVADModel?
    private var qwen35Editor: Qwen35MLXChat?
    private var denseEditor: Qwen3DenseChat?
    private var selectedID = ""
    private var selectedEditorID = ""
    private let root: URL
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceBuddy/Models", isDirectory: true)) {
        self.root = root
    }
    private func directory(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
    private func speechDirectory(_ id: String) -> URL {
        if id.contains("sensevoice") {
            return directory("sensevoice-small")
        }
        if id.contains("whisper") {
            return directory("whisper-large-v3-turbo")
        }
        return directory(id.contains("1.7") ? "qwen-asr-1.7b" : "qwen-asr-0.6b")
    }
    private func textDirectory(_ id: String) -> URL { directory(id) }

    func isSpeechModelCached(id: String) -> Bool {
        if id == "apple-speech" {
            return true
        }
        let dir = speechDirectory(id)
        let vadDir = directory("silero-vad")
        let vadCached = hasSafetensors(in: vadDir)
        if id.contains("sensevoice") {
            return SenseVoiceASRModel.hasCompleteBundle(in: dir) && vadCached
        }
        if id.contains("whisper") {
            return hasWhisperBundle(in: dir) && vadCached
        }
        return hasSafetensors(in: dir) && vadCached
    }

    private func hasWhisperBundle(in dir: URL) -> Bool {
        let required = [
            "MelSpectrogram.mlmodelc/weights/weight.bin",
            "AudioEncoder.mlmodelc/weights/weight.bin",
            "TextDecoder.mlmodelc/weights/weight.bin",
            "TextDecoderContextPrefill.mlmodelc/weights/weight.bin",
            "generation_config.json",
            "tokenizer.json"
        ]
        let fm = FileManager.default
        for file in required {
            let path = dir.appendingPathComponent(file).path
            guard fm.fileExists(atPath: path),
                  let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? NSNumber,
                  size.int64Value > 0 else {
                return false
            }
        }
        return true
    }

    func isEditorModelCached(id: String? = nil) -> Bool {
        let targetId = id ?? "qwen35-text-0.8b-int5"
        var dir = textDirectory(targetId)
        if targetId == "qwen35-text-0.8b-int5" && !FileManager.default.fileExists(atPath: dir.path) {
            let legacy = directory("qwen35-text-0.8b")
            if FileManager.default.fileExists(atPath: legacy.path) {
                dir = legacy
            }
        }
        if targetId.hasPrefix("qwen35-text-0.8b") {
            let q = targetId.contains("int8") ? "int8" : "int5"
            let variantDir = dir.appendingPathComponent(q)
            if FileManager.default.fileExists(atPath: variantDir.appendingPathComponent("model.safetensors").path) {
                return true
            }
        }
        return hasSafetensors(in: dir)
    }

    private func hasSafetensors(in dir: URL) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        for f in files {
            if f.hasSuffix(".safetensors") && !f.hasPrefix(".") {
                let filePath = dir.appendingPathComponent(f).path
                if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                   let size = attrs[.size] as? NSNumber,
                   size.int64Value > 0 {
                    return true
                }
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
        if id == "apple-speech" {
            if appleSpeech == nil || selectedID != id {
                asr = nil
                whisper = nil
                senseVoice = nil
                appleSpeech = AppleSpeechEngine()
                selectedID = id
            }
            progress(0.9, "Apple Speech ready")
        } else if id.contains("sensevoice") {
            if senseVoice == nil || selectedID != id {
                asr = nil
                whisper = nil
                appleSpeech = nil
                senseVoice = try await SenseVoiceASRModel.fromPretrained(
                    cacheDir: speechDirectory(id),
                    offlineMode: isCached,
                    progressHandler: { value, message in progress(value * 0.9, message) }
                )
                selectedID = id
            }
        } else if id.contains("whisper") {
            if whisper == nil || selectedID != id {
                asr = nil
                senseVoice = nil
                appleSpeech = nil
                whisper = try await WhisperASRModel.fromPretrained(
                    cacheDir: speechDirectory(id),
                    offlineMode: isCached,
                    progressHandler: { value, message in progress(value * 0.9, message) }
                )
                selectedID = id
            }
        } else {
            let hfModelId = id.contains("1.7") ? "mlx-community/Qwen3-ASR-1.7B-8bit" : "mlx-community/Qwen3-ASR-0.6B-8bit"
            if asr == nil || selectedID != id {
                whisper = nil
                senseVoice = nil
                appleSpeech = nil
                asr = try await Qwen3ASRModel.fromPretrained(
                    modelId: hfModelId,
                    cacheDir: speechDirectory(id),
                    offlineMode: isCached,
                    progressHandler: { value, message in progress(value * 0.9, message) }
                )
                selectedID = id
            }
        }
        if id == "apple-speech" {
            // Apple Speech is completely built into macOS and does not use Silero VAD.
            progress(1.0, "Apple Speech ready")
            return
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

    func downloadSpeech(id: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard SpeechModelSpec.allModels.contains(where: { $0.id == id }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid speech model identifier")
        }
        if id == "apple-speech" {
            progress(1.0, "Ready")
            return
        }
        let isCached = isSpeechModelCached(id: id)
        if id.contains("sensevoice") {
            _ = try await SenseVoiceASRModel.fromPretrained(
                cacheDir: speechDirectory(id),
                offlineMode: isCached,
                progressHandler: { value, message in progress(value * 0.9, message) }
            )
        } else if id.contains("whisper") {
            _ = try await WhisperASRModel.fromPretrained(
                cacheDir: speechDirectory(id),
                offlineMode: isCached,
                progressHandler: { value, message in progress(value * 0.9, message) }
            )
        } else {
            let hfModelId = id.contains("1.7") ? "mlx-community/Qwen3-ASR-1.7B-8bit" : "mlx-community/Qwen3-ASR-0.6B-8bit"
            _ = try await Qwen3ASRModel.fromPretrained(
                modelId: hfModelId,
                cacheDir: speechDirectory(id),
                offlineMode: isCached,
                progressHandler: { value, message in progress(value * 0.9, message) }
            )
        }
        let vadCached = hasSafetensors(in: directory("silero-vad"))
        if !vadCached {
            _ = try await SileroVADModel.fromPretrained(
                cacheDir: directory("silero-vad"),
                offlineMode: vadCached,
                progressHandler: { value, message in progress(0.9 + value * 0.1, message) }
            )
        }
        progress(1.0, "Completed")
    }

    func downloadEditor(id: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard TextModelSpec.allModels.contains(where: { $0.id == id }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid text model identifier")
        }
        let isCached = isEditorModelCached(id: id)
        var dir = textDirectory(id)

        if id.hasPrefix("qwen35-text-0.8b") {
            let q: Qwen35MLXChat.Quantization = id.contains("int8") ? .int8 : .int5
            if id == "qwen35-text-0.8b-int5" && !FileManager.default.fileExists(atPath: dir.path) {
                let legacy = directory("qwen35-text-0.8b")
                if FileManager.default.fileExists(atPath: legacy.path) {
                    dir = legacy
                }
            }
            _ = try await Qwen35MLXChat.fromPretrained(
                quantization: q,
                cacheDir: dir,
                offlineMode: isCached,
                progressHandler: progress
            )
        } else {
            let hfModelId = (id == "qwen3-text-4b-4bit")
                ? "aufklarer/Qwen3-4B-Instruct-2507-MLX-4bit"
                : "mlx-community/Qwen3-1.7B-4bit"
            _ = try await Qwen3DenseChat.fromPretrained(
                modelId: hfModelId,
                cacheDir: dir,
                offlineMode: isCached,
                progressHandler: progress
            )
        }
        progress(1.0, "Completed")
    }

    func prepareEditor(id: String? = nil, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let targetId = id ?? "qwen35-text-0.8b-int5"
        guard TextModelSpec.allModels.contains(where: { $0.id == targetId }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid text model identifier")
        }
        let isCached = isEditorModelCached(id: targetId)
        var dir = textDirectory(targetId)

        if targetId.hasPrefix("qwen35-text-0.8b") {
            let q: Qwen35MLXChat.Quantization = targetId.contains("int8") ? .int8 : .int5
            if targetId == "qwen35-text-0.8b-int5" && !FileManager.default.fileExists(atPath: dir.path) {
                let legacy = directory("qwen35-text-0.8b")
                if FileManager.default.fileExists(atPath: legacy.path) {
                    dir = legacy
                }
            }
            let variantDir = dir.appendingPathComponent(q.rawValue)
            let isLocalVariantCached = FileManager.default.fileExists(atPath: variantDir.appendingPathComponent("model.safetensors").path)

            if qwen35Editor == nil || selectedEditorID != targetId {
                denseEditor = nil
                if isLocalVariantCached {
                    qwen35Editor = try await Qwen35MLXChat.fromLocal(
                        directory: variantDir,
                        progressHandler: progress
                    )
                } else {
                    qwen35Editor = try await Qwen35MLXChat.fromPretrained(
                        quantization: q,
                        cacheDir: dir,
                        offlineMode: isCached,
                        progressHandler: progress
                    )
                }
                selectedEditorID = targetId
            }
        } else {
            let hfModelId = (targetId == "qwen3-text-4b-4bit")
                ? "aufklarer/Qwen3-4B-Instruct-2507-MLX-4bit"
                : "mlx-community/Qwen3-1.7B-4bit"
            let isDenseLocalCached = FileManager.default.fileExists(atPath: dir.appendingPathComponent("model.safetensors").path)

            if denseEditor == nil || selectedEditorID != targetId {
                qwen35Editor = nil
                if isDenseLocalCached {
                    denseEditor = try Qwen3DenseChat.fromDirectory(dir, progressHandler: { progress(0.5 + $0 * 0.5, $1) })
                } else {
                    denseEditor = try await Qwen3DenseChat.fromPretrained(
                        modelId: hfModelId,
                        cacheDir: dir,
                        offlineMode: isCached,
                        progressHandler: progress
                    )
                }
                selectedEditorID = targetId
            }
        }
    }

    func removeSpeech(id: String) throws {
        guard SpeechModelSpec.allModels.contains(where: { $0.id == id }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid speech model identifier")
        }
        if id == "apple-speech" {
            // Built-in system model, cannot be removed from disk
            return
        }
        if selectedID == id {
            asr = nil
            whisper = nil
            senseVoice = nil
            appleSpeech = nil
            selectedID = ""
        }
        let path = speechDirectory(id)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    func unloadEditor() {
        qwen35Editor?.unload()
        qwen35Editor = nil
        denseEditor = nil
        selectedEditorID = ""
        Qwen35MLXChat.clearGPUCache()
    }

    func removeEditor(id: String? = nil) throws {
        let targetId = id ?? selectedEditorID
        guard TextModelSpec.allModels.contains(where: { $0.id == targetId }) else {
            throw VoiceBuddyError.modelUnavailable("Invalid text model identifier")
        }
        if selectedEditorID == targetId {
            unloadEditor()
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
        if selectedID == "apple-speech" {
            guard !samples.isEmpty else { return false }
            // Filter out digital silence / zero audio; SFSpeechRecognizer has built-in acoustic
            // speech recognition and returns emptyTranscript on background noise / non-speech.
            var maxAbs: Float = 0
            for s in samples {
                let a = abs(s)
                if a > maxAbs { maxAbs = a }
                if maxAbs > 0.005 { return true }
            }
            return false
        }
        if let vad {
            vad.resetState()
            return !vad.detectSpeech(audio: samples, sampleRate: 16000).isEmpty
        }
        throw VoiceBuddyError.modelUnavailable("VAD")
    }
    func transcribe(samples: [Float], language: String) async throws -> String {
        if selectedID == "apple-speech" {
            guard let appleSpeech else { throw VoiceBuddyError.modelUnavailable("Apple Speech") }
            return try await appleSpeech.transcribe(samples: samples, sampleRate: 16000, language: language)
        }
        if selectedID.contains("sensevoice") {
            guard let senseVoice else { throw VoiceBuddyError.modelUnavailable("SenseVoice") }
            return try await senseVoice.transcribe(audio: samples, sampleRate: 16000, language: language)
        }
        if selectedID.contains("whisper") {
            guard let whisper else { throw VoiceBuddyError.modelUnavailable("Whisper") }
            let whisperLang = whisperLanguageCode(from: language)
            return try await whisper.transcribeAudio(samples, sampleRate: 16000, language: whisperLang)
        }
        guard let asr else { throw VoiceBuddyError.modelUnavailable("ASR") }
        return try asr.transcribeThrowing(audio: samples, sampleRate: 16000, options: Qwen3DecodingOptions(language: language == "auto" ? nil : language))
    }

    private func whisperLanguageCode(from language: String) -> String? {
        if language == "auto" { return nil }
        switch language.lowercased() {
        case "chinese", "zh", "zh-cn", "zh-hans", "zh-hant":
            return "zh"
        case "cantonese", "yue":
            return "yue"
        case "english", "en", "en-us", "en-gb":
            return "en"
        case "japanese", "ja":
            return "ja"
        case "korean", "ko":
            return "ko"
        case "french", "fr":
            return "fr"
        default:
            return language
        }
    }
    func refine(_ text: String, mode: Refinement) async throws -> String {
        if mode == .light { return TextCleanup.light(text) }
        guard let instruction = RefinementPrompts.prompt(for: mode) else {
            return text
        }
        let userMessage = "<asr_text>\(text)</asr_text>"
        let tokenBudget = max(512, min(text.count * 4 + 128, 2048))
        let messages: [ChatMessage] = [
            .init(role: .system, content: instruction),
            .init(role: .user, content: userMessage),
            .init(role: .assistant, content: "<polished_text>")
        ]
        let sampling = ChatSamplingConfig(
            temperature: 0.15,
            maxTokens: tokenBudget,
            // Editing should reuse the source words. The sampler includes input
            // tokens in its repetition history, so do not penalize copying them.
            repetitionPenalty: 1.0
        )

        let startTime = CFAbsoluteTimeGetCurrent()
        let generated: String
        let tokenizer: ChatTokenizer

        if let editor = qwen35Editor {
            tokenizer = editor.tokenizer
            generated = try editor.generate(messages: messages, sampling: sampling)
        } else if let editor = denseEditor {
            tokenizer = editor.tokenizer
            var output = ""
            for try await chunk in editor.generateStream(messages: messages, sampling: sampling) {
                output += chunk
            }
            generated = output
        } else {
            throw VoiceBuddyError.modelUnavailable("Text model")
        }

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        var trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        if let thinkEnd = trimmed.range(of: "</think>") {
            trimmed = String(trimmed[thinkEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.hasPrefix("<think>") {
            // Unclosed think tag: model ran out of token budget inside reasoning block
            throw RefinementFailure(original: text, reason: "Model exceeded token budget inside reasoning block")
        }

        // Clean <polished_text> tags (both standard </polished_text> and quantized variant </p>)
        if let endTag = trimmed.range(of: "</polished_text>") {
            trimmed = String(trimmed[..<endTag.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let endP = trimmed.range(of: "</p>") {
            trimmed = String(trimmed[..<endP.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let startTag = trimmed.range(of: "<polished_text>") {
            trimmed = String(trimmed[startTag.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Clean any echoed <asr_text> or <asr_input> tags
        trimmed = trimmed.replacingOccurrences(of: "</?asr_(?:text|input)>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tokenCount = tokenizer.encode(trimmed).count
        if tokenCount >= tokenBudget || (text.count >= 40 && trimmed.count < max(12, text.count / 3)) {
            throw RefinementFailure(original: text, reason: "Refinement output exceeded token budget (\(tokenCount)/\(tokenBudget)) or was truncated (\(trimmed.count) chars)")
        }
        DiagnosticLog.shared.record("model.text.refine_completed mode=\(mode.rawValue) duration_ms=\(elapsedMs) in_chars=\(text.count) out_chars=\(trimmed.count)")
        return trimmed
    }
}
