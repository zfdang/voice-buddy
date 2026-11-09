import Accelerate
import AudioCommon
import CoreML
import Foundation
import VoiceBuddyCore

/// Non-autoregressive SenseVoice Small ASR through native CoreML.
public final class SenseVoiceASRModel: @unchecked Sendable {
    public static let defaultModelId = "FluidInference/sensevoice-small-coreml"
    public static let sampleRate = 16_000
    private static let waveformScale: Float = 32_768.0

    private let preprocessor: MLModel
    private let encoder: MLModel
    private let vocabulary: [String]
    private let buckets: [Int]

    public init(preprocessor: MLModel, encoder: MLModel, vocabulary: [String]) {
        self.preprocessor = preprocessor
        self.encoder = encoder
        self.vocabulary = vocabulary
        self.buckets = Self.resolveBuckets(from: encoder)
    }

    /// Load or download SenseVoice CoreML bundle.
    public static func fromPretrained(
        modelId: String = defaultModelId,
        cacheDir: URL,
        offlineMode: Bool = false,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> SenseVoiceASRModel {
        let preprocessorURL = cacheDir.appendingPathComponent("SenseVoicePreprocessor.mlmodelc")
        let encoderURL = cacheDir.appendingPathComponent("SenseVoiceSmall.mlmodelc")
        let vocabURL = cacheDir.appendingPathComponent("vocab.json")

        if !hasCompleteBundle(in: cacheDir) {
            progressHandler?(0.0, "Preparing SenseVoice CoreML bundle...")
            try await HuggingFaceDownloader.downloadWeights(
                modelId: modelId,
                to: cacheDir,
                additionalFiles: [
                    "SenseVoicePreprocessor.mlmodelc/**",
                    "SenseVoiceSmall.mlmodelc/**",
                    "vocab.json",
                    "config.json"
                ],
                offlineMode: offlineMode
            ) { fraction in
                progressHandler?(fraction * 0.85, "Downloading SenseVoice...")
            }
        } else {
            progressHandler?(0.85, "Using cached SenseVoice bundle")
        }

        progressHandler?(0.90, "Loading SenseVoice CoreML models...")

        let preprocessorConfig = MLModelConfiguration()
        preprocessorConfig.computeUnits = .cpuOnly

        let encoderConfig = MLModelConfiguration()
        encoderConfig.computeUnits = .cpuAndGPU

        let preprocessor: MLModel
        let encoder: MLModel
        let vocabulary: [String]
        do {
            preprocessor = try MLModel(contentsOf: preprocessorURL, configuration: preprocessorConfig)
            encoder = try MLModel(contentsOf: encoderURL, configuration: encoderConfig)
            let vocabData = try Data(contentsOf: vocabURL)
            vocabulary = try JSONDecoder().decode([String].self, from: vocabData)
        } catch {
            throw VoiceBuddyError.modelUnavailable("Failed to initialize SenseVoice CoreML: \(error.localizedDescription)")
        }

        progressHandler?(1.0, "SenseVoice ready")
        return SenseVoiceASRModel(preprocessor: preprocessor, encoder: encoder, vocabulary: vocabulary)
    }

    public static func hasCompleteBundle(in directory: URL) -> Bool {
        let fm = FileManager.default
        let required = [
            "SenseVoicePreprocessor.mlmodelc/model.mil",
            "SenseVoiceSmall.mlmodelc/weights/weight.bin",
            "vocab.json"
        ]
        for rel in required {
            let path = directory.appendingPathComponent(rel).path
            guard fm.fileExists(atPath: path),
                  let attr = try? fm.attributesOfItem(atPath: path),
                  let size = attr[.size] as? NSNumber, size.int64Value > 0 else {
                return false
            }
        }
        return true
    }

    /// Transcribe 16 kHz mono float samples.
    public func transcribe(audio: [Float], sampleRate inRate: Int = 16_000, language: String? = nil) async throws -> String {
        guard !audio.isEmpty else { return "" }
        let normalizedAudio: [Float]
        if inRate == Self.sampleRate {
            normalizedAudio = audio
        } else {
            normalizedAudio = AudioFileLoader.resample(audio, from: inRate, to: Self.sampleRate)
        }

        let features = try runPreprocessor(audio: normalizedAudio)
        let langId = languageId(for: language ?? "auto")
        let (logits, validFrames) = try runEncoder(features: features, language: langId)
        return decode(logits: logits, validFrames: validFrames)
    }

    private func runPreprocessor(audio: [Float]) throws -> MLMultiArray {
        let n = audio.count
        let waveform = try MLMultiArray(shape: [1, n as NSNumber], dataType: .float32)
        let wptr = waveform.dataPointer.assumingMemoryBound(to: Float32.self)
        for i in 0..<n {
            wptr[i] = audio[i] * Self.waveformScale
        }

        let input = try MLDictionaryFeatureProvider(dictionary: ["waveform": MLFeatureValue(multiArray: waveform)])
        let out = try preprocessor.prediction(from: input)
        guard let features = out.featureValue(for: "features")?.multiArrayValue else {
            throw VoiceBuddyError.modelUnavailable("SenseVoice preprocessor produced no features")
        }
        return features
    }

    private func runEncoder(features: MLMultiArray, language: Int32) throws -> (MLMultiArray, Int) {
        let dim = 560
        var t = features.shape[1].intValue
        let maxFrames = buckets.last ?? 1800
        if t > maxFrames { t = maxFrames }
        let bucket = buckets.first { $0 >= t } ?? maxFrames

        let speech = try MLMultiArray(shape: [1, bucket as NSNumber, dim as NSNumber], dataType: .float32)
        let sptr = speech.dataPointer.assumingMemoryBound(to: Float32.self)
        memset(sptr, 0, bucket * dim * MemoryLayout<Float32>.size)

        let count = t * dim
        if features.dataType == .float32 {
            memcpy(sptr, features.dataPointer, count * MemoryLayout<Float32>.size)
        } else {
            for i in 0..<count { sptr[i] = features[i].floatValue }
        }

        let lengths = try MLMultiArray(shape: [1], dataType: .int32)
        lengths[0] = NSNumber(value: t)
        let lang = try MLMultiArray(shape: [1], dataType: .int32)
        lang[0] = NSNumber(value: language)
        let tn = try MLMultiArray(shape: [1], dataType: .int32)
        tn[0] = NSNumber(value: 15) // with punctuation

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "speech": MLFeatureValue(multiArray: speech),
            "speech_lengths": MLFeatureValue(multiArray: lengths),
            "language": MLFeatureValue(multiArray: lang),
            "textnorm": MLFeatureValue(multiArray: tn)
        ])
        let out = try encoder.prediction(from: input)
        guard let logits = out.featureValue(for: "ctc_logits")?.multiArrayValue else {
            throw VoiceBuddyError.modelUnavailable("SenseVoice encoder produced no ctc_logits")
        }
        return (logits, 4 + t)
    }

    private func decode(logits: MLMultiArray, validFrames: Int) -> String {
        let frames = min(validFrames, logits.shape[1].intValue)
        let vocab = logits.shape[2].intValue
        let stride = logits.strides[1].intValue

        var ids: [Int] = []
        ids.reserveCapacity(frames)
        var prev = -1

        if logits.dataType == .float32 {
            let ptr = logits.dataPointer.assumingMemoryBound(to: Float32.self)
            for t in 0..<frames {
                var bestVal: Float = 0
                var bestIdx: vDSP_Length = 0
                vDSP_maxvi(ptr + t * stride, 1, &bestVal, &bestIdx, vDSP_Length(vocab))
                let id = Int(bestIdx)
                if id != 0 && id != prev {
                    ids.append(id)
                }
                prev = id
            }
        } else {
            for t in 0..<frames {
                var bestVal: Float = -.infinity
                var bestIdx = 0
                for v in 0..<vocab {
                    let val = logits[[0, t as NSNumber, v as NSNumber]].floatValue
                    if val > bestVal {
                        bestVal = val
                        bestIdx = v
                    }
                }
                if bestIdx != 0 && bestIdx != prev {
                    ids.append(bestIdx)
                }
                prev = bestIdx
            }
        }

        let raw = ids.compactMap { $0 < vocabulary.count ? vocabulary[$0] : nil }
            .joined()
            .replacingOccurrences(of: "\u{2581}", with: " ")
            .replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw
    }

    private func languageId(for language: String) -> Int32 {
        switch language.lowercased() {
        case "zh", "chinese", "zh-cn", "zh-hans":
            return 3
        case "en", "english", "en-us":
            return 4
        case "yue", "cantonese":
            return 7
        case "ja", "japanese":
            return 11
        case "ko", "korean":
            return 12
        default:
            return 0 // auto
        }
    }

    private static func resolveBuckets(from encoder: MLModel) -> [Int] {
        guard let constraint = encoder.modelDescription.inputDescriptionsByName["speech"]?.multiArrayConstraint else {
            return [128, 256, 512, 1024, 1800]
        }
        switch constraint.shapeConstraint.type {
        case .enumerated:
            let frames = constraint.shapeConstraint.enumeratedShapes.compactMap { $0.count == 3 ? $0[1].intValue : nil }.sorted()
            return frames.isEmpty ? [128, 256, 512, 1024, 1800] : frames
        default:
            return [128, 256, 512, 1024, 1800]
        }
    }
}
