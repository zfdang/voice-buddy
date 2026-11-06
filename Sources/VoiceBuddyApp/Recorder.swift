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

final class Recorder {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var level: Float = 0
    private var diagnostics = CaptureDiagnostics()
    var currentLevel: Float { lock.lock(); defer { lock.unlock() }; return level }
    var currentSamples: [Float] { lock.lock(); defer { lock.unlock() }; return samples }

    func start(deviceUID: String) throws {
        let engine = AVAudioEngine()
        if !deviceUID.isEmpty, let device = AudioDevices.id(for: deviceUID), let unit = engine.inputNode.audioUnit {
            var id = device
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        } else if !deviceUID.isEmpty { throw NSError(domain: "VoiceBuddy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected microphone is unavailable."]) }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        DiagnosticLog.shared.record("recording.format custom_device=\(!deviceUID.isEmpty) sample_rate=\(format.sampleRate) channels=\(format.channelCount)")
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else {
            throw NSError(domain: "VoiceBuddy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to configure microphone."])
        }
        lock.lock(); samples = []; level = 0; diagnostics = CaptureDiagnostics(); lock.unlock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            var allocated = false
            var conversionFailed = false
            var conversionErrorCode: Int?
            var outputFrames = 0
            defer {
                self.lock.lock()
                self.diagnostics.record(inputFrames: Int(buffer.frameLength), outputFrames: outputFrames, allocated: allocated, conversionFailed: conversionFailed, errorCode: conversionErrorCode)
                self.lock.unlock()
            }
            let count = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / format.sampleRate) + 64)
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: count) else { return }
            allocated = true
            var consumed = false; var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, flag in
                if consumed { flag.pointee = .noDataNow; return nil }
                consumed = true; flag.pointee = .haveData; return buffer
            }
            guard status != .error, let data = out.floatChannelData?[0] else {
                conversionFailed = true
                conversionErrorCode = error?.code
                return
            }
            let n = Int(out.frameLength); var rms: Float = 0
            outputFrames = n
            if n > 0 { vDSP_rmsqv(data, 1, &rms, vDSP_Length(n)) }
            self.lock.lock(); self.samples.append(contentsOf: UnsafeBufferPointer(start: data, count: n)); self.level = rms; self.lock.unlock()
        }
        do { try engine.start(); self.engine = engine } catch { input.removeTap(onBus: 0); throw error }
    }
    func stop() -> (samples: [Float], diagnostics: CaptureDiagnostics) {
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
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
