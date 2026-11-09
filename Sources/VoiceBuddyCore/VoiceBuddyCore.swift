import Foundation

public enum Refinement: String, CaseIterable, Codable, Identifiable {
    case original, light, moderate, rewrite
    public var id: String { rawValue }
    public var needsModel: Bool { self == .moderate || self == .rewrite }
}

public struct Preferences: Codable, Equatable {
    public var interfaceLanguage = "system"
    public var speechLanguage = "auto"
    public var microphoneUID = ""
    public var speechModel = "qwen-asr-0.6b"
    public var textModel = "qwen35-text-0.8b-int5"
    public var refinement: Refinement = .light
    public var holdToTalk: Bool? = nil // nil preserves older settings and defaults to hold
    public var useFnKey = false
    public var sounds = true
    public var autoInsert = true
    public var pauseMediaDuringRecording = true
    public var shortcutKeyCode: UInt32 = 49
    public var shortcutModifiers: UInt32 = 6144 // Carbon controlKey + optionKey
    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interfaceLanguage = try container.decodeIfPresent(String.self, forKey: .interfaceLanguage) ?? "system"
        speechLanguage = try container.decodeIfPresent(String.self, forKey: .speechLanguage) ?? "auto"
        microphoneUID = try container.decodeIfPresent(String.self, forKey: .microphoneUID) ?? ""
        let rawSpeech = try container.decodeIfPresent(String.self, forKey: .speechModel) ?? "qwen-asr-0.6b"
        if rawSpeech.contains("whisper") {
            speechModel = "whisper-large-v3-turbo"
        } else if rawSpeech.contains("1.7") {
            speechModel = "qwen-asr-1.7b"
        } else {
            speechModel = "qwen-asr-0.6b"
        }
        textModel = try container.decodeIfPresent(String.self, forKey: .textModel) ?? "qwen35-text-0.8b-int5"
        refinement = try container.decodeIfPresent(Refinement.self, forKey: .refinement) ?? .light
        holdToTalk = try container.decodeIfPresent(Bool.self, forKey: .holdToTalk)
        useFnKey = try container.decodeIfPresent(Bool.self, forKey: .useFnKey) ?? false
        sounds = try container.decodeIfPresent(Bool.self, forKey: .sounds) ?? true
        autoInsert = try container.decodeIfPresent(Bool.self, forKey: .autoInsert) ?? true
        pauseMediaDuringRecording = try container.decodeIfPresent(Bool.self, forKey: .pauseMediaDuringRecording) ?? true
        shortcutKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .shortcutKeyCode) ?? 49
        shortcutModifiers = try container.decodeIfPresent(UInt32.self, forKey: .shortcutModifiers) ?? 6144
    }
}

public enum VoiceBuddyError: LocalizedError, Equatable {
    case noSpeech, emptyTranscript, unsafeTarget, modelUnavailable(String)
    public var errorDescription: String? {
        switch self {
        case .noSpeech: return "No speech detected."
        case .emptyTranscript: return "No text was recognized."
        case .unsafeTarget: return "The input focus changed. Copy the result manually."
        case .modelUnavailable(let name): return "Model unavailable: \(name)"
        }
    }
}

public struct RefinementFailure: LocalizedError {
    public let original: String
    public let reason: String
    public var errorDescription: String? { reason }
    public init(original: String, reason: String) { self.original = original; self.reason = reason }
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(samples: [Float], language: String) async throws -> String
}
public protocol TextRefinementEngine: Sendable {
    func refine(_ text: String, mode: Refinement) async throws -> String
}
public protocol SpeechDetector: Sendable {
    func containsSpeech(_ samples: [Float]) async throws -> Bool
}

public enum TextCleanup {
    public static func looksSafe(_ result: String, original: String) -> Bool {
        let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= max(original.count * 4, original.count + 200) else { return false }
        if original.count >= 40 && text.count < max(12, original.count / 3) { return false }
        let lower = text.lowercased()
        guard !lower.contains("<think>") && !lower.contains("</think>") && !lower.contains("corrected text here") && !lower.contains("i am ready to help") && !lower.contains("as an ai") else { return false }
        let chinese = original.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }
        if chinese.count >= 3 {
            let unique = Set(chinese)
            let matching = unique.filter { text.unicodeScalars.contains($0) }.count
            if matching < min(2, unique.count) { return false }
        }
        let numerals = CharacterSet(charactersIn: "0123456789零〇一二两三四五六七八九十百千万亿")
        if original.unicodeScalars.contains(where: { numerals.contains($0) }) && !text.unicodeScalars.contains(where: { numerals.contains($0) }) { return false }
        return true
    }
    public static func light(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?:^|[，,])[ \\t]*[嗯呃啊][，,][ \\t]*", with: "，", options: .regularExpression)
        text = text.replacingOccurrences(of: "^[，,\\s]+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum PipelineEvent: String, Sendable {
    case detectionStarted, detectionCompleted, detectionFailed
    case transcriptionStarted, transcriptionCompleted, transcriptionFailed
    case refinementStarted, refinementCompleted, refinementFailed
}

public struct Pipeline: Sendable {
    public let detector: any SpeechDetector
    public let transcription: any TranscriptionEngine
    public let refinement: any TextRefinementEngine
    public let onEvent: @Sendable (PipelineEvent) -> Void
    public init(detector: any SpeechDetector, transcription: any TranscriptionEngine, refinement: any TextRefinementEngine, onEvent: @escaping @Sendable (PipelineEvent) -> Void = { _ in }) {
        self.detector = detector; self.transcription = transcription; self.refinement = refinement
        self.onEvent = onEvent
    }
    public func run(samples: [Float], language: String, mode: Refinement) async throws -> (original: String, result: String) {
        onEvent(.detectionStarted)
        do {
            guard !samples.isEmpty, try await detector.containsSpeech(samples) else { throw VoiceBuddyError.noSpeech }
            onEvent(.detectionCompleted)
        } catch { onEvent(.detectionFailed); throw error }
        try Task.checkCancellation()
        onEvent(.transcriptionStarted)
        let original: String
        do {
            original = try await transcription.transcribe(samples: samples, language: language).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else { throw VoiceBuddyError.emptyTranscript }
            onEvent(.transcriptionCompleted)
        } catch { onEvent(.transcriptionFailed); throw error }
        try Task.checkCancellation()
        switch mode {
        case .original: return (original, original)
        case .light:
            onEvent(.refinementStarted)
            let result = TextCleanup.light(original)
            onEvent(.refinementCompleted)
            return (original, result)
        case .moderate, .rewrite:
            onEvent(.refinementStarted)
            do {
                let result = try await refinement.refine(original, mode: mode).trimmingCharacters(in: .whitespacesAndNewlines)
                guard TextCleanup.looksSafe(result, original: original) else { throw VoiceBuddyError.modelUnavailable("Text model returned an unsafe or empty result") }
                onEvent(.refinementCompleted)
                return (original, result)
            } catch is CancellationError { onEvent(.refinementFailed); throw CancellationError() }
            catch { onEvent(.refinementFailed); throw RefinementFailure(original: original, reason: error.localizedDescription) }
        }
    }
}

public struct HotkeyGesture {
    public enum Action: Equatable { case none, startHold, stopHold, toggle }
    public private(set) var isDown = false
    public init() {}
    public mutating func press(hold: Bool) -> Action {
        guard !isDown else { return .none }
        isDown = true
        return hold ? .startHold : .toggle
    }
    public mutating func release(hold: Bool) -> Action {
        guard isDown else { return .none }
        isDown = false
        return hold ? .stopHold : .none
    }
    public mutating func reset() { isDown = false }
}

/// Fn can be used as a modifier, so a chord must not be treated as a dictation tap.
public struct FnKeyGesture {
    public enum Action: Equatable { case none, press, release, cancel, tap }
    public private(set) var isDown = false
    private var chord = false
    private var hold = false
    public init() {}
    public mutating func flagsChanged(fnDown: Bool, otherModifierChanged: Bool, otherModifiersHeld: Bool, holdToTalk: Bool) -> Action {
        if fnDown != isDown {
            let action = fnChanged(down: fnDown, holdToTalk: holdToTalk)
            if fnDown && otherModifiersHeld {
                _ = otherKeyPressed()
                return .none
            }
            return action
        }
        return fnDown && otherModifierChanged ? otherKeyPressed() : .none
    }
    public mutating func fnChanged(down: Bool, holdToTalk: Bool) -> Action {
        if down {
            guard !isDown else { return .none }
            isDown = true; chord = false; hold = holdToTalk
            return hold ? .press : .none
        }
        guard isDown else { return .none }
        isDown = false
        guard !chord else { return .none }
        return hold ? .release : .tap
    }
    public mutating func otherKeyPressed() -> Action {
        guard isDown, !chord else { return .none }
        chord = true
        return hold ? .cancel : .none
    }
    public mutating func reset() { isDown = false; chord = false; hold = false }
}
