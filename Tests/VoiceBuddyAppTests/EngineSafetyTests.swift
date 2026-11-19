import CoreML
import XCTest
@testable import VoiceBuddyApp
@testable import VoiceBuddyCore

private final class MockSpeechTaskHandle: AppleSpeechTaskHandle, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var cancelCount = 0

    func cancel() {
        lock.lock()
        cancelCount += 1
        lock.unlock()
    }
}

final class EngineSafetyTests: XCTestCase {
    func testSenseVoiceCopyFeaturesHandlesPaddedStridesAndSlices() throws {
        let frames = 3
        let dim = 560
        let rowStride = 600 // intentionally > dim to verify stride-aware copy
        var backing = [Float32](repeating: -999, count: frames * rowStride)
        for f in 0..<frames {
            for c in 0..<dim {
                backing[f * rowStride + c] = Float32(f * 1000 + c)
            }
        }

        let array = try backing.withUnsafeMutableBytes { rawBuffer -> MLMultiArray in
            try MLMultiArray(
                dataPointer: rawBuffer.baseAddress!,
                shape: [1, frames as NSNumber, dim as NSNumber],
                dataType: .float32,
                strides: [(frames * rowStride) as NSNumber, rowStride as NSNumber, 1]
            )
        }

        var output = [Float32](repeating: 0, count: 2 * dim)
        try output.withUnsafeMutableBufferPointer { dst in
            try SenseVoiceASRModel.copyFeatures(array, frameOffset: 1, frameCount: 2, expectedDim: dim, to: dst.baseAddress!)
        }

        XCTAssertEqual(output[0], 1000)
        XCTAssertEqual(output[dim - 1], Float32(1000 + dim - 1))
        XCTAssertEqual(output[dim], 2000)
        XCTAssertEqual(output[2 * dim - 1], Float32(2000 + dim - 1))
    }

    func testSenseVoiceCopyFeaturesRejectsUnexpectedDimension() throws {
        let array = try MLMultiArray(shape: [1, 2, 128], dataType: .float32)
        var output = [Float32](repeating: 0, count: 2 * 560)
        XCTAssertThrowsError(try output.withUnsafeMutableBufferPointer { dst in
            try SenseVoiceASRModel.copyFeatures(array, frameOffset: 0, frameCount: 2, expectedDim: 560, to: dst.baseAddress!)
        })
    }

    func testSenseVoiceDecodeCTCHandlesNonUnitVocabStride() throws {
        let frames = 4
        let vocab = 4
        let vocabStride = 2 // non-unit inner stride; vDSP_maxvi must not assume stride == 1
        let frameStride = vocab * vocabStride
        var backing = [Float32](repeating: -10, count: frames * frameStride)
        // Frame 0 -> token 1 ("▁hi"), Frame 1 -> token 1 (dedup), Frame 2 -> token 0 (blank), Frame 3 -> token 2 ("!")
        backing[0 * frameStride + 1 * vocabStride] = 9.0
        backing[1 * frameStride + 1 * vocabStride] = 8.0
        backing[2 * frameStride + 0 * vocabStride] = 7.0
        backing[3 * frameStride + 2 * vocabStride] = 9.5

        let logits = try backing.withUnsafeMutableBytes { rawBuffer -> MLMultiArray in
            try MLMultiArray(
                dataPointer: rawBuffer.baseAddress!,
                shape: [1, frames as NSNumber, vocab as NSNumber],
                dataType: .float32,
                strides: [(frames * frameStride) as NSNumber, frameStride as NSNumber, vocabStride as NSNumber]
            )
        }

        let decoded = SenseVoiceASRModel.decodeCTC(
            logits: logits,
            validFrames: frames,
            vocabulary: ["<blk>", "\u{2581}hi", "!", "<unused>"]
        )
        XCTAssertEqual(decoded, "hi!")
    }

    func testAppleSpeechSessionGuaranteesSingleResumeAndCancelsTask() async {
        let session = AppleSpeechRecognitionSession()
        let taskHandle = MockSpeechTaskHandle()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                session.attach(continuation: cont, timeoutSeconds: 10)
                session.setTask(taskHandle)
                session.cancel()
                session.complete(with: .success("late result should be ignored"))
            }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            XCTAssertEqual(taskHandle.cancelCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppleSpeechSessionCancelsLateAttachedTask() async {
        let session = AppleSpeechRecognitionSession()
        let taskHandle = MockSpeechTaskHandle()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                session.attach(continuation: cont, timeoutSeconds: 10)
                session.cancel()
                session.setTask(taskHandle)
            }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            XCTAssertEqual(taskHandle.cancelCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppleSpeechSessionCancelBeforeAttachResumesImmediately() async {
        let session = AppleSpeechRecognitionSession()
        let taskHandle = MockSpeechTaskHandle()
        session.cancel()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                session.attach(continuation: cont, timeoutSeconds: 10)
                session.setTask(taskHandle)
            }
            XCTFail("Expected CancellationError when cancel() precedes attach()")
        } catch is CancellationError {
            XCTAssertEqual(taskHandle.cancelCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppleSpeechSessionTimesOutAndCancelsTask() async {
        let session = AppleSpeechRecognitionSession()
        let taskHandle = MockSpeechTaskHandle()

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                session.attach(continuation: cont, timeoutSeconds: 0.05)
                session.setTask(taskHandle)
            }
            XCTFail("Expected timeout error")
        } catch let error as AppleSpeechError {
            XCTAssertEqual(taskHandle.cancelCount, 1)
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSenseVoiceMergeChunkTranscriptsHandlesChineseAndOverlap() {
        // Chinese chunks must not inject artificial spaces and must deduplicate overlap
        let zhMerged = SenseVoiceASRModel.mergeChunkTranscripts(
            ["今天天气真不错，我们", "，我们一起去公园散步。"],
            languageId: 3
        )
        XCTAssertEqual(zhMerged, "今天天气真不错，我们一起去公园散步。")

        // Long overlap (> 24 chars) must be deduplicated cleanly
        let longOverlapMerged = SenseVoiceASRModel.mergeChunkTranscripts(
            ["we discussed the quarterly budget and the hiring plan", "the quarterly budget and the hiring plan for Q3"],
            languageId: 4
        )
        XCTAssertEqual(longOverlapMerged, "we discussed the quarterly budget and the hiring plan for Q3")

        // Partial ASCII word collisions ("stop" + "open" sharing "op") must NOT be truncated
        let wordBoundarySafe = SenseVoiceASRModel.mergeChunkTranscripts(
            ["we should stop", "open the window"],
            languageId: 4
        )
        XCTAssertEqual(wordBoundarySafe, "we should stop open the window")

        // Sentence/clause punctuation followed by next English word preserves space
        let englishPunctSpace = SenseVoiceASRModel.mergeChunkTranscripts(
            ["hello world.", "Next sentence."],
            languageId: 0
        )
        XCTAssertEqual(englishPunctSpace, "hello world. Next sentence.")

        let englishCommaSpace = SenseVoiceASRModel.mergeChunkTranscripts(
            ["hello,", "World"],
            languageId: 4
        )
        XCTAssertEqual(englishCommaSpace, "hello, World")

        // Korean chunks preserve word spacing
        let koreanMerged = SenseVoiceASRModel.mergeChunkTranscripts(
            ["안녕하세요", "반갑습니다"],
            languageId: 12
        )
        XCTAssertEqual(koreanMerged, "안녕하세요 반갑습니다")

        // Mixed auto mode avoids spaces around Chinese characters while preserving English word spaces
        let autoZh = SenseVoiceASRModel.mergeChunkTranscripts(
            ["打开项目目录", "然后运行测试"],
            languageId: 0
        )
        XCTAssertEqual(autoZh, "打开项目目录然后运行测试")
    }

    func testEnergyGateRejectsSingleSpikeAndLowNoiseButAcceptsSpeech() {
        XCTAssertFalse(LocalModels.containsSpeechByEnergyGate([]))

        // Single keyboard click spike should not trigger speech
        var spike = [Float](repeating: 0, count: 3200)
        spike[100] = 0.5
        spike[101] = -0.4
        XCTAssertFalse(LocalModels.containsSpeechByEnergyGate(spike))

        // Low background hum / constant DC offset must be rejected
        let lowHum = (0..<6400).map { Float(0.003 * sin(Double($0) * 0.1)) }
        XCTAssertFalse(LocalModels.containsSpeechByEnergyGate(lowHum))
        let dcOffset = [Float](repeating: 0.015, count: 6400)
        XCTAssertFalse(LocalModels.containsSpeechByEnergyGate(dcOffset))

        // Continuous soft speech (0.012 and 0.015 amplitude) without silence MUST still be accepted
        let continuousSoftSpeech = (0..<6400).map { Float(0.012 * sin(Double($0) * 0.2)) }
        XCTAssertTrue(LocalModels.containsSpeechByEnergyGate(continuousSoftSpeech))
        let continuousModerateSoftSpeech = (0..<6400).map { Float(0.015 * sin(Double($0) * 0.2)) }
        XCTAssertTrue(LocalModels.containsSpeechByEnergyGate(continuousModerateSoftSpeech))

        // Soft speech preceded/followed by silence must also be accepted
        let softSpeechWithSilence = (0..<6400).map { $0 < 3200 ? Float(0.012 * sin(Double($0) * 0.2)) : Float(0) }
        XCTAssertTrue(LocalModels.containsSpeechByEnergyGate(softSpeechWithSilence))

        // Sustained voiced signal (~200 ms)
        let speech = (0..<3200).map { Float(0.05 * sin(Double($0) * 0.2)) }
        XCTAssertTrue(LocalModels.containsSpeechByEnergyGate(speech))
    }
}
