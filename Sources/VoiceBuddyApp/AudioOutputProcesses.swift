import AppKit
import CoreAudio
import Darwin

/// Detects active output streams only; this is not proof of media playback.
enum AudioOutputProcesses {
    static func uniqueApplicationPID() -> pid_t? {
        let candidates = activeCandidatePIDs()
        return uniqueCandidate(candidates)
    }

    static func isAudioRunning(for pid: pid_t) -> Bool {
        activeCandidatePIDs().contains(pid)
    }

    private static func activeCandidatePIDs() -> Set<pid_t> {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0, size % UInt32(MemoryLayout<AudioObjectID>.size) == 0, size <= 65536 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = objects.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return OSStatus(-1) }
            return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, base)
        }
        guard status == noErr else { return [] }
        let applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
        let appIDs = Set(applications.map(\.processIdentifier))
        var candidates = Set<pid_t>()
        for object in objects {
            guard let active = uint32Property(object, kAudioProcessPropertyIsRunningOutput), active != 0 else { continue }
            // Voice Input Buddy writes dictated audio into its virtual microphone.
            // That stream is not background media and must not mask a player.
            if outputsOnlyToVoiceInputBuddyMic(object) { continue }
            guard let rawPID = uint32Property(object, kAudioProcessPropertyPID), rawPID > 0, rawPID <= UInt32(Int32.max) else { continue }
            let pid = pid_t(rawPID)
            if pid == getpid() { continue }
            guard let appPID = owner(of: pid, among: appIDs) else { continue }
            candidates.insert(appPID)
        }
        return candidates
    }

    static func uniqueCandidate(_ candidates: Set<pid_t>) -> pid_t? {
        guard candidates.count == 1 else { return nil }
        return candidates.first
    }

    private static func outputsOnlyToVoiceInputBuddyMic(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyDevices, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(process, &address, 0, nil, &size) == noErr,
              size > 0, size % UInt32(MemoryLayout<AudioObjectID>.size) == 0, size <= 65536 else { return false }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &devices) == noErr else { return false }
        return isVoiceInputBuddyOnly(devices.map(deviceUID))
    }

    static func isVoiceInputBuddyOnly(_ deviceUIDs: [String?]) -> Bool {
        !deviceUIDs.isEmpty && deviceUIDs.allSatisfy { $0 == "BuddyMic2ch_UID" }
    }

    private static func deviceUID(_ device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func uint32Property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, size == MemoryLayout<UInt32>.size else { return nil }
        return value
    }

    private static func owner(of pid: pid_t, among applicationIDs: Set<pid_t>) -> pid_t? {
        var current = pid
        var visited = Set<pid_t>()
        for _ in 0..<16 {
            guard current > 1, visited.insert(current).inserted else { return nil }
            if applicationIDs.contains(current) { return current }
            var info = proc_bsdinfo()
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
            current = pid_t(info.pbi_ppid)
        }
        return nil
    }
}
