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
        let totalFrames = features.shape.count >= 2 ? features.shape[1].intValue : 0
        guard totalFrames > 0 else { return "" }

        let maxFrames = buckets.last ?? 1800
        if totalFrames <= maxFrames {
            let (logits, validFrames) = try runEncoder(features: features, frameOffset: 0, frameCount: totalFrames, language: langId)
            return decode(logits: logits, validFrames: validFrames)
        }

        let overlapFrames = min(60, max(1, maxFrames / 10))
        let stepFrames = max(1, maxFrames - overlapFrames)
        DiagnosticLog.shared.record("sensevoice.chunked_inference total_frames=\(totalFrames) max_frames=\(maxFrames) overlap=\(overlapFrames)")
        var chunks: [String] = []
        var offset = 0
        while offset < totalFrames {
            let count = min(maxFrames, totalFrames - offset)
            let (logits, validFrames) = try runEncoder(features: features, frameOffset: offset, frameCount: count, language: langId)
            let text = decode(logits: logits, validFrames: validFrames)
            if !text.isEmpty {
                chunks.append(text)
            }
            if offset + count >= totalFrames {
                break
            }
            offset += stepFrames
        }
        return Self.mergeChunkTranscripts(chunks, languageId: langId)
    }

    static func mergeChunkTranscripts(_ chunks: [String], languageId: Int32) -> String {
        let cleaned = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard var merged = cleaned.first else { return "" }

        for next in cleaned.dropFirst() {
            let overlapCount = longestBoundaryOverlap(suffixOf: merged, prefixOf: next, maxChars: 24)
            let remainder = overlapCount > 0
                ? String(next.dropFirst(overlapCount)).trimmingCharacters(in: .whitespaces)
                : next
            guard !remainder.isEmpty else { continue }

            if needsSpaceBetween(merged.last, remainder.first, languageId: languageId) {
                merged += " " + remainder
            } else {
                merged += remainder
            }
        }
        return merged
    }

    private static func longestBoundaryOverlap(suffixOf lhs: String, prefixOf rhs: String, maxChars: Int) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let limit = min(maxChars, lhsChars.count, rhsChars.count)
        guard limit > 0 else { return 0 }

        for len in stride(from: limit, through: 1, by: -1) {
            let lhsSlice = lhsChars[(lhsChars.count - len)..<lhsChars.count]
            let rhsSlice = rhsChars[0..<len]
            if zip(lhsSlice, rhsSlice).allSatisfy({ $0 == $1 }) {
                if len >= 2 || rhsChars[0].unicodeScalars.allSatisfy({ !($0.isASCII && $0.properties.isAlphabetic) }) {
                    return len
                }
            }
        }
        return 0
    }

    private static func needsSpaceBetween(_ left: Character?, _ right: Character?, languageId: Int32) -> Bool {
        guard let left, let right else { return false }
        let cjkSpaceFreeLanguage = (languageId == 3 || languageId == 7 || languageId == 11)
        let leftIsASCIILetterOrDigit = left.isASCII && (left.isLetter || left.isNumber)
        let rightIsASCIILetterOrDigit = right.isASCII && (right.isLetter || right.isNumber)
        if cjkSpaceFreeLanguage && !(leftIsASCIILetterOrDigit && rightIsASCIILetterOrDigit) {
            return false
        }
        return leftIsASCIILetterOrDigit && rightIsASCIILetterOrDigit
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

    private func runEncoder(features: MLMultiArray, frameOffset: Int, frameCount: Int, language: Int32) throws -> (MLMultiArray, Int) {
        let dim = 560
        let maxFrames = buckets.last ?? 1800
        let t = min(frameCount, maxFrames)
        let bucket = buckets.first { $0 >= t } ?? maxFrames

        let speech = try MLMultiArray(shape: [1, bucket as NSNumber, dim as NSNumber], dataType: .float32)
        let sptr = speech.dataPointer.assumingMemoryBound(to: Float32.self)
        memset(sptr, 0, bucket * dim * MemoryLayout<Float32>.size)

        try Self.copyFeatures(features, frameOffset: frameOffset, frameCount: t, expectedDim: dim, to: sptr)

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

    static func copyFeatures(
        _ features: MLMultiArray,
        frameOffset: Int,
        frameCount: Int,
        expectedDim: Int = 560,
        to destination: UnsafeMutablePointer<Float32>
    ) throws {
        guard features.shape.count == 3 else {
            throw VoiceBuddyError.modelUnavailable("Unexpected SenseVoice feature rank: \(features.shape.count)")
        }
        let totalFrames = features.shape[1].intValue
        let featureDim = features.shape[2].intValue
        guard featureDim == expectedDim else {
            throw VoiceBuddyError.modelUnavailable("Unexpected SenseVoice feature dimension: \(featureDim), expected \(expectedDim)")
        }
        guard frameOffset >= 0, frameCount >= 0, frameOffset + frameCount <= totalFrames else {
            throw VoiceBuddyError.modelUnavailable("SenseVoice feature slice out of bounds: offset=\(frameOffset) count=\(frameCount) total=\(totalFrames)")
        }
        guard frameCount > 0 else { return }

        let strides = features.strides.map(\.intValue)
        let rowStride = strides.count >= 2 ? strides[1] : expectedDim
        let colStride = strides.count >= 3 ? strides[2] : 1

        if features.dataType == .float32 && colStride == 1 && rowStride == expectedDim {
            let src = features.dataPointer.assumingMemoryBound(to: Float32.self) + frameOffset * rowStride
            memcpy(destination, src, frameCount * expectedDim * MemoryLayout<Float32>.size)
        } else if features.dataType == .float32 && colStride == 1 && rowStride > expectedDim {
            let srcBase = features.dataPointer.assumingMemoryBound(to: Float32.self)
            for frame in 0..<frameCount {
                let srcRow = srcBase + (frameOffset + frame) * rowStride
                let dstRow = destination + frame * expectedDim
                memcpy(dstRow, srcRow, expectedDim * MemoryLayout<Float32>.size)
            }
        } else {
            for frame in 0..<frameCount {
                let srcFrame = frameOffset + frame
                let dstOffset = frame * expectedDim
                for col in 0..<expectedDim {
                    destination[dstOffset + col] = features[[0, srcFrame as NSNumber, col as NSNumber]].floatValue
                }
            }
        }
    }

    private func decode(logits: MLMultiArray, validFrames: Int) -> String {
        Self.decodeCTC(logits: logits, validFrames: validFrames, vocabulary: vocabulary)
    }

    static func decodeCTC(logits: MLMultiArray, validFrames: Int, vocabulary: [String]) -> String {
        guard logits.shape.count >= 3, logits.strides.count >= 3 else { return "" }
        let frames = min(validFrames, logits.shape[1].intValue)
        let vocab = logits.shape[2].intValue
        guard frames > 0, vocab > 0 else { return "" }
        let frameStride = logits.strides[1].intValue
        let vocabStride = logits.strides[2].intValue

        var ids: [Int] = []
        ids.reserveCapacity(frames)
        var prev = -1

        if logits.dataType == .float32 && vocabStride == 1 {
            let ptr = logits.dataPointer.assumingMemoryBound(to: Float32.self)
            for t in 0..<frames {
                var bestVal: Float = 0
                var bestIdx: vDSP_Length = 0
                vDSP_maxvi(ptr + t * frameStride, 1, &bestVal, &bestIdx, vDSP_Length(vocab))
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
