import AVFoundation
import Foundation
import Speech
import VoiceBuddyCore

enum AppleSpeechError: LocalizedError, Equatable {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Apple Speech recognition timed out. Please try again."
        }
    }
}

/// Protocol abstraction for cancellable speech recognition tasks (enables unit testing).
protocol AppleSpeechTaskHandle: AnyObject, Sendable {
    func cancel()
}

extension SFSpeechRecognitionTask: AppleSpeechTaskHandle {}

/// Thread-safe coordinator guaranteeing single continuation resumption, task cancellation, and timeout cleanup.
final class AppleSpeechRecognitionSession: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var taskHandle: (any AppleSpeechTaskHandle)?
    private var isFinished = false
    private var isCancelled = false
    private var timeoutWorkItem: DispatchWorkItem?

    func attach(continuation: CheckedContinuation<String, Error>, timeoutSeconds: TimeInterval) {
        var immediateError: Error?
        lock.lock()
        if isCancelled {
            isFinished = true
            immediateError = CancellationError()
        } else if isFinished {
            immediateError = AppleSpeechError.timedOut
        } else {
            self.continuation = continuation
            if timeoutSeconds > 0 {
                let work = DispatchWorkItem { [weak self] in
                    self?.timeout()
                }
                self.timeoutWorkItem = work
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeoutSeconds, execute: work)
            }
        }
        lock.unlock()

        if let immediateError {
            continuation.resume(throwing: immediateError)
        }
    }

    func setTask(_ task: any AppleSpeechTaskHandle) {
        var shouldCancel = false
        lock.lock()
        self.taskHandle = task
        if isCancelled || isFinished {
            shouldCancel = true
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func complete(with result: Result<String, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let cont = continuation
        continuation = nil
        let work = timeoutWorkItem
        timeoutWorkItem = nil
        taskHandle = nil
        lock.unlock()

        work?.cancel()
        cont?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = taskHandle
        guard !isFinished else {
            lock.unlock()
            task?.cancel()
            return
        }
        isFinished = true
        let cont = continuation
        continuation = nil
        let work = timeoutWorkItem
        timeoutWorkItem = nil
        taskHandle = nil
        lock.unlock()

        work?.cancel()
        task?.cancel()
        cont?.resume(throwing: CancellationError())
    }

    private func timeout() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let cont = continuation
        continuation = nil
        let task = taskHandle
        taskHandle = nil
        timeoutWorkItem = nil
        lock.unlock()

        task?.cancel()
        cont?.resume(throwing: AppleSpeechError.timedOut)
    }
}

/// On-device and system speech recognition through Apple's native Speech framework.
final class AppleSpeechEngine: @unchecked Sendable {
    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval = 60) {
        self.timeoutSeconds = timeoutSeconds
    }

    func transcribe(samples: [Float], sampleRate: Int = 16_000, language: String) async throws -> String {
        guard !samples.isEmpty else { return "" }
        try Task.checkCancellation()

        // 1. Permission check
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            throw VoiceBuddyError.modelUnavailable("Apple Speech authorization denied. Please allow Speech Recognition in macOS System Settings.")
        }
        try Task.checkCancellation()

        // 2. Recognizer resolution
        let locale = localeForLanguage(language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw VoiceBuddyError.modelUnavailable("Apple Speech recognizer unavailable for \(locale.identifier)")
        }
        guard recognizer.isAvailable else {
            throw VoiceBuddyError.modelUnavailable("Apple Speech recognizer is unavailable. Please enable 'Dictation' in macOS System Settings -> Keyboard. (macOS 系统听写或 Siri 未开启，请前往「系统设置 ➔ 键盘 ➔ 听写」开启听写功能，或切换至 SenseVoice/Qwen 独立模型)")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw VoiceBuddyError.modelUnavailable("On-device Apple Speech recognition is unavailable for \(locale.identifier). Download the required language resources or choose another speech model. (此语言的 Apple Speech 本地识别不可用，请下载所需语言资源或选择其他语音模型。)")
        }

        // 3. Audio file writing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("apple_speech_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try writeAudioFile(samples: samples, sampleRate: sampleRate, to: tempURL)

        // 4. Request configuration
        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.requiresOnDeviceRecognition = true

        let session = AppleSpeechRecognitionSession()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.attach(continuation: continuation, timeoutSeconds: timeoutSeconds)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        let nsError = error as NSError
                        let desc = error.localizedDescription.lowercased()
                        if nsError.domain == "kAFAssistantErrorDomain" || desc.contains("siri") || desc.contains("dictation") || desc.contains("disabled") {
                            let friendlyMessage = "Apple Speech requires macOS Dictation to be enabled. Please enable 'Dictation' in System Settings -> Keyboard, or switch to SenseVoice/Qwen. (macOS 系统听写或 Siri 未开启，请前往「系统设置 ➔ 键盘 ➔ 听写」开启听写功能，或切换至 SenseVoice/Qwen 独立模型)"
                            session.complete(with: .failure(VoiceBuddyError.modelUnavailable(friendlyMessage)))
                        } else {
                            session.complete(with: .failure(error))
                        }
                        return
                    }
                    if let result = result, result.isFinal {
                        session.complete(with: .success(result.bestTranscription.formattedString))
                    }
                }
                session.setTask(task)
            }
        } onCancel: {
            session.cancel()
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
