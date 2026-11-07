import AppKit
import ApplicationServices
import VoiceBuddyCore

/// Uses an identifiable audio-producing app and an unambiguous accessible media control.
@MainActor final class AccessibleMediaPlaybackBackend: MediaPlaybackBackend {
    private var generation = 0
    private var control: AXUIElement?
    private var processID: pid_t = 0
    private var trackedPID: pid_t = 0

    func beginSession() {
        generation += 1
        control = nil; processID = 0; trackedPID = 0
    }

    func snapshot(completion: @escaping (MediaPlaybackSnapshot?) -> Void) {
        generation += 1
        let current = generation
        control = nil; processID = 0
        guard AXIsProcessTrusted() else { completion(nil); return }
        // Once a player is selected, retain its identity after output stops.
        let pid = trackedPID != 0 ? trackedPID : (AudioOutputProcesses.uniqueApplicationPID() ?? 0)
        guard pid != 0, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            DiagnosticLog.shared.record("media.audio_candidate available=false")
            completion(nil)
            return
        }
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
                self.control = found.element; self.processID = pid; self.trackedPID = pid
                DiagnosticLog.shared.record("media.player_control available=true playing=\(found.isPlaying)")
                completion(MediaPlaybackSnapshot(processID: pid, isPlaying: found.isPlaying))
            }
        }
    }

    func pause() -> Bool { perform(expectedPlaying: true) }
    func play() -> Bool { perform(expectedPlaying: false) }

    private func perform(expectedPlaying: Bool) -> Bool {
        guard let control, processID != 0,
              let app = NSRunningApplication(processIdentifier: processID), !app.isTerminated else { return false }
        _ = AXUIElementSetMessagingTimeout(control, 0.2)
        guard Self.controlState(control) == expectedPlaying else { return false }
        let result = AXUIElementPerformAction(control, kAXPressAction as CFString)
        DiagnosticLog.shared.record("media.player_action result=\(result.rawValue)")
        return result == .success
    }

    nonisolated private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    nonisolated static func playbackState(forLabel label: String?) -> Bool? {
        switch label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "暂停 (space)", "pause (space)", "暂停播放", "pause playback", "pause video": return true
        case "播放 (space)", "play (space)", "开始播放", "恢复播放", "play playback", "resume playback", "play video": return false
        default: return nil
        }
    }

    nonisolated static func isPlaybackMenu(title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["playback", "controls", "control", "播放", "控制"].contains(t)
    }

    nonisolated static func menuPlaybackState(forLabel label: String?) -> Bool? {
        switch label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "暂停", "pause", "暫停", "暂停 (space)", "pause (space)", "暂停播放", "pause playback", "pause video", "一時停止", "일시 정지": return true
        case "播放", "play", "resume", "播放 (space)", "play (space)", "开始播放", "恢复播放", "play playback", "resume playback", "play video", "繼續播放", "再生", "재생": return false
        default: return nil
        }
    }

    nonisolated static func isPlaybackProgress(_ label: String?) -> Bool {
        guard let label = label?.lowercased() else { return false }
        return ["播放进度", "playback progress", "playback position", "seek", "timeline"].contains { label.contains($0) }
    }

    nonisolated private static func controlState(_ element: AXUIElement) -> Bool? {
        for attribute in [kAXHelpAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            let label = stringAttribute(element, attribute as CFString)
            if let result = playbackState(forLabel: label) ?? menuPlaybackState(forLabel: label) { return result }
        }
        return nil
    }

    nonisolated static func findControl(pid: pid_t) -> (element: AXUIElement, isPlaying: Bool)? {
        let app = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(app, 0.1)
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // 1. First, search standard application menu bar (AXMenuBar).
        // This reliably controls desktop players (e.g. Movist Pro, IINA, QuickTime, VLC)
        // even when full-screen or on-screen controls are auto-hidden.
        if let menuControl = findMenuBarControl(app: app) {
            return menuControl
        }

        // 2. Second, search application windows for accessible media buttons.
        return findWindowControl(app: app)
    }

    nonisolated private static func findMenuBarControl(app: AXUIElement) -> (element: AXUIElement, isPlaying: Bool)? {
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBar = menuBarValue else { return nil }

        var barItemsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &barItemsValue) == .success,
              let barItems = barItemsValue as? [AXUIElement] else { return nil }

        for barItem in barItems {
            guard let barTitle = stringAttribute(barItem, kAXTitleAttribute as CFString),
                  isPlaybackMenu(title: barTitle) else { continue }
            var menuValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(barItem, kAXChildrenAttribute as CFString, &menuValue) == .success,
                  let menus = menuValue as? [AXUIElement] else { continue }
            for menu in menus {
                var itemsValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &itemsValue) == .success,
                      let items = itemsValue as? [AXUIElement] else { continue }
                for item in items {
                    guard let title = stringAttribute(item, kAXTitleAttribute as CFString) else { continue }
                    var enabledValue: CFTypeRef?
                    if AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabledValue) == .success,
                       let enabled = enabledValue as? Bool, !enabled {
                        continue
                    }
                    if let playing = menuPlaybackState(forLabel: title) {
                        return (item, playing)
                    }
                }
            }
        }
        return nil
    }

    nonisolated private static func findWindowControl(app: AXUIElement) -> (element: AXUIElement, isPlaying: Bool)? {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return nil }
        var overall: (element: AXUIElement, isPlaying: Bool)?
        for window in windows {
            var queue: [AXUIElement] = [window]
            var position = 0
            var truncated = false
            var hasProgress = false
            var match: (element: AXUIElement, isPlaying: Bool)?
            var ambiguous = false
            while position < queue.count && position < 2000 {
                let element = queue[position]; position += 1
                let role = stringAttribute(element, kAXRoleAttribute as CFString)
                if role == kAXButtonRole as String, let playing = controlState(element) {
                    if match != nil { ambiguous = true }
                    match = (element, playing)
                }
                if role == kAXSliderRole as String {
                    for attribute in [kAXHelpAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                        if isPlaybackProgress(stringAttribute(element, attribute as CFString)) { hasProgress = true; break }
                    }
                }
                var children: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                   let values = children as? [AXUIElement] {
                    let room = max(0, 2000 - queue.count)
                    if values.count > room { truncated = true }
                    queue.append(contentsOf: values.prefix(room))
                }
            }
            guard !truncated, !ambiguous else { return nil }
            if hasProgress, let match {
                guard overall == nil else { return nil }
                overall = match
            }
        }
        return overall
    }
}
