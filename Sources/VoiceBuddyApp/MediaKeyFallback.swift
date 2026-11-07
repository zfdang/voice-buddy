import AppKit
import VoiceBuddyCore

/// Fallback for background media players that do not expose readable playback controls.
@MainActor final class MediaKeyFallback: MediaToggleBackend {
    func hasActiveOutput() -> Bool {
        AudioOutputProcesses.hasActiveAudioOutput()
    }

    func toggle() -> Bool {
        // NX_KEYTYPE_PLAY (16) in a system-defined media key event.
        let key = 16 << 16
        guard let down = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: key | (0x0a << 8), data2: -1)?.cgEvent,
              let up = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: key | (0x0b << 8), data2: -1)?.cgEvent else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
