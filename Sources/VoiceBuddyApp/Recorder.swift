import AVFoundation
import Accelerate
import CoreAudio

struct CaptureDiagnostics {
    var callbacks = 0
    var inputFrames = 0
    var outputFrames = 0
    var allocationFailures = 0
    var conversionFailures = 0
    var emptyOutputBuffers = 0
    var lastConversionErrorCode: Int?

    mutating func record(inputFrames: Int, outputFrames: Int, allocated: Bool, conversionFailed: Bool, errorCode: Int?) {
        callbacks += 1
        self.inputFrames += inputFrames
        self.outputFrames += outputFrames
        if !allocated { allocationFailures += 1 }
        if conversionFailed { conversionFailures += 1; lastConversionErrorCode = errorCode }
        if allocated && !conversionFailed && outputFrames == 0 { emptyOutputBuffers += 1 }
    }
}

final class Recorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var session: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "VoiceBuddy.audioCapture")
    private let lock = NSLock()
    private var samples: [Float] = []
    private var level: Float = 0
    private var diagnostics = CaptureDiagnostics()
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    var currentLevel: Float { lock.lock(); defer { lock.unlock() }; return level }
    var currentSamples: [Float] { lock.lock(); defer { lock.unlock() }; return samples }

    func start(deviceUID: String) throws {
        let device: AVCaptureDevice?
        if deviceUID.isEmpty {
            device = AVCaptureDevice.default(for: .audio)
        } else {
            device = AVCaptureDevice(uniqueID: deviceUID)
        }
        guard let device, device.hasMediaType(.audio), device.isConnected else {
            throw NSError(domain: "VoiceBuddy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected microphone is unavailable."])
        }
        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw NSError(domain: "VoiceBuddy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to configure microphone."])
        }
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: captureQueue)
        session.addOutput(output)
        lock.lock(); samples = []; level = 0; diagnostics = CaptureDiagnostics(); lock.unlock()
        converter = nil; sourceFormat = nil
        session.startRunning()
        guard session.isRunning else {
            output.setSampleBufferDelegate(nil, queue: nil)
            throw NSError(domain: "VoiceBuddy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to configure microphone."])
        }
        self.session = session
        DiagnosticLog.shared.record("recording.capture_session custom_device=\(!deviceUID.isEmpty)")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return }
        if sourceFormat != format {
            sourceFormat = format
            converter = AVAudioConverter(from: format, to: target)
            DiagnosticLog.shared.record("recording.format sample_rate=\(format.sampleRate) channels=\(format.channelCount)")
        }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        var allocated = false
        var conversionFailed = false
        var conversionErrorCode: Int?
        var outputFrames = 0
        defer {
            lock.lock()
            diagnostics.record(inputFrames: Int(frames), outputFrames: outputFrames, allocated: allocated, conversionFailed: conversionFailed, errorCode: conversionErrorCode)
            lock.unlock()
        }
        guard let converter, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else {
            conversionFailed = true; return
        }
        let capacity = AVAudioFrameCount(ceil(Double(frames) * 16000 / format.sampleRate) + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        allocated = true
        var consumed = false; var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, flag in
            if consumed { flag.pointee = .noDataNow; return nil }
            consumed = true; flag.pointee = .haveData; return buffer
        }
        guard status != .error, let data = out.floatChannelData?[0] else {
            conversionFailed = true; conversionErrorCode = error?.code; return
        }
        let n = Int(out.frameLength); var rms: Float = 0
        outputFrames = n
        if n > 0 { vDSP_rmsqv(data, 1, &rms, vDSP_Length(n)) }
        lock.lock(); samples.append(contentsOf: UnsafeBufferPointer(start: data, count: n)); level = rms; lock.unlock()
    }

    func stop() -> (samples: [Float], diagnostics: CaptureDiagnostics) {
        session?.stopRunning()
        captureQueue.sync { }
        session = nil
        lock.lock(); defer { lock.unlock() }
        let result = (samples, diagnostics)
        samples = []; level = 0
        return result
    }
}

enum AudioDevices {
    static func devices() -> [(String, String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var n: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &n) == noErr, n > 0 else { return nil }
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(n), alignment: MemoryLayout<AudioBufferList>.alignment); defer { buffer.deallocate() }
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &n, buffer) == noErr,
                  UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self)).contains(where: { $0.mNumberChannels > 0 }),
                  let uid = property(id, kAudioDevicePropertyDeviceUID), let name = property(id, kAudioObjectPropertyName) else { return nil }
            return (uid, name)
        }
    }
    static func id(for uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return nil }
        return ids.first { property($0, kAudioDevicePropertyDeviceUID) == uid }
    }
    private static func property(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &unmanaged) == noErr, let unmanaged {
            return unmanaged.takeRetainedValue() as String
        }
        return nil
    }
}
