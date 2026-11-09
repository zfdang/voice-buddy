import AVFoundation
import Foundation
import Speech
import VoiceBuddyCore

/// On-device and system speech recognition through Apple's native Speech framework.
final class AppleSpeechEngine: @unchecked Sendable {
    func transcribe(samples: [Float], sampleRate: Int = 16_000, language: String) async throws -> String {
        guard !samples.isEmpty else { return "" }

        // 1. Permission check
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            throw VoiceBuddyError.modelUnavailable("Apple Speech authorization denied. Please allow Speech Recognition in macOS System Settings.")
        }

        // 2. Recognizer resolution
        let locale = localeForLanguage(language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw VoiceBuddyError.modelUnavailable("Apple Speech recognizer unavailable for \(locale.identifier)")
        }
        guard recognizer.isAvailable else {
            throw VoiceBuddyError.modelUnavailable("Apple Speech recognizer is unavailable. Please enable 'Dictation' in macOS System Settings -> Keyboard. (macOS 系统听写或 Siri 未开启，请前往「系统设置 ➔ 键盘 ➔ 听写」开启听写功能，或切换至 SenseVoice/Qwen 独立模型)")
        }

        // 3. Audio file writing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("apple_speech_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try writeAudioFile(samples: samples, sampleRate: sampleRate, to: tempURL)

        // 4. Request configuration
        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    if !hasResumed {
                        hasResumed = true
                        let nsError = error as NSError
                        let desc = error.localizedDescription.lowercased()
                        if nsError.domain == "kAFAssistantErrorDomain" || desc.contains("siri") || desc.contains("dictation") || desc.contains("disabled") {
                            let friendlyMessage = "Apple Speech requires macOS Dictation to be enabled. Please enable 'Dictation' in System Settings -> Keyboard, or switch to SenseVoice/Qwen. (macOS 系统听写或 Siri 未开启，请前往「系统设置 ➔ 键盘 ➔ 听写」开启听写功能，或切换至 SenseVoice/Qwen 独立模型)"
                            continuation.resume(throwing: VoiceBuddyError.modelUnavailable(friendlyMessage))
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                    return
                }
                if let result = result, result.isFinal {
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }
        }
    }

    private func writeAudioFile(samples: [Float], sampleRate: Int, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false) else {
            throw VoiceBuddyError.modelUnavailable("Audio format initialization failed")
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw VoiceBuddyError.modelUnavailable("Audio buffer allocation failed")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channel[i] = samples[i]
        }
        try file.write(from: buffer)
    }

    private func localeForLanguage(_ language: String) -> Locale {
        switch language.lowercased() {
        case "chinese", "zh", "zh-cn", "zh-hans":
            return Locale(identifier: "zh-CN")
        case "cantonese", "yue":
            return Locale(identifier: "zh-HK")
        case "english", "en", "en-us":
            return Locale(identifier: "en-US")
        case "japanese", "ja":
            return Locale(identifier: "ja-JP")
        case "korean", "ko":
            return Locale(identifier: "ko-KR")
        case "french", "fr":
            return Locale(identifier: "fr-FR")
        case "auto":
            return Locale.current
        default:
            return Locale(identifier: language)
        }
    }
}
