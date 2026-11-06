import AppKit
import ApplicationServices
import VoiceBuddyCore

/// Uses the player's accessible, state-labelled control without activating its window.
@MainActor final class RedFruitMediaPlaybackBackend: MediaPlaybackBackend {
    private static let bundleID = "com.zfdang.hongguo.openplayer"
    private var generation = 0
    private var control: AXUIElement?
    private var processID: pid_t = 0

    func snapshot(completion: @escaping (MediaPlaybackSnapshot?) -> Void) {
        generation += 1
        let current = generation
        control = nil; processID = 0
        let players = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).filter { !$0.isTerminated }
        guard AXIsProcessTrusted(), players.count == 1, let player = players.first else {
            DiagnosticLog.shared.record("media.player_accessible available=false")
            completion(nil)
            return
        }
        let pid = player.processIdentifier
        findControl(pid: pid, generation: current, attemptsRemaining: 3, completion: completion)
    }

    private func findControl(pid: pid_t, generation current: Int, attemptsRemaining: Int, completion: @escaping (MediaPlaybackSnapshot?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Self.findControl(pid: pid)
            DispatchQueue.main.async {
                guard let self, self.generation == current else { completion(nil); return }
                guard let found else {
                    if attemptsRemaining > 1 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                            guard let self, self.generation == current else { completion(nil); return }
                            self.findControl(pid: pid, generation: current, attemptsRemaining: attemptsRemaining - 1, completion: completion)
                        }
                        return
                    }
                    DiagnosticLog.shared.record("media.player_control available=false")
                    completion(nil)
                    return
                }
                self.control = found.element; self.processID = pid
                DiagnosticLog.shared.record("media.player_control available=true playing=\(found.isPlaying)")
                completion(MediaPlaybackSnapshot(processID: pid, isPlaying: found.isPlaying))
            }
        }
    }

    func pause() -> Bool { perform(expectedHelp: "暂停 (Space)") }
    func play() -> Bool { perform(expectedHelp: "播放 (Space)") }

    private func perform(expectedHelp: String) -> Bool {
        guard let control, processID != 0,
              let app = NSRunningApplication(processIdentifier: processID), !app.isTerminated else { return false }
        _ = AXUIElementSetMessagingTimeout(control, 0.2)
        guard Self.stringAttribute(control, kAXHelpAttribute as CFString) == expectedHelp else { return false }
        let result = AXUIElementPerformAction(control, kAXPressAction as CFString)
        DiagnosticLog.shared.record("media.player_action result=\(result.rawValue)")
        return result == .success
    }

    nonisolated private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    nonisolated static func playbackState(forHelp help: String?) -> Bool? {
        switch help {
        case "暂停 (Space)": return true
        case "播放 (Space)": return false
        default: return nil
        }
    }

    nonisolated private static func findControl(pid: pid_t) -> (element: AXUIElement, isPlaying: Bool)? {
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(app, 0.1)
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var queue: [AXUIElement] = [app]
        var position = 0
        var truncated = false
        var match: (element: AXUIElement, isPlaying: Bool)?
        while position < queue.count && position < 2000 {
            let element = queue[position]; position += 1
            if stringAttribute(element, kAXRoleAttribute as CFString) == kAXButtonRole as String,
               let playing = playbackState(forHelp: stringAttribute(element, kAXHelpAttribute as CFString)) {
                guard match == nil else { return nil }
                match = (element, playing)
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let values = children as? [AXUIElement] {
                let room = max(0, 2000 - queue.count)
                if values.count > room { truncated = true }
                queue.append(contentsOf: values.prefix(room))
            }
        }
        return truncated ? nil : match
    }
}
