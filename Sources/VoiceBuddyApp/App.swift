import SwiftUI
import AppKit
import Carbon
import ApplicationServices
import AVFoundation
import VoiceBuddyCore

public enum AppTab: Int, CaseIterable, Identifiable {
    case general = 0
    case permissions = 1
    case speech = 2
    case editor = 3
    case recovery = 4
    public var id: Int { rawValue }
}

@MainActor final class AppState: ObservableObject {
    @Published var preferences: Preferences { didSet { save() } }
    @Published var status = "Ready"
    @Published var result = ""
    @Published var original = ""
    @Published var recording = false
    @Published var ready = false
    @Published var editorReady = false
    @Published var busy = false
    @Published var modelProgress: Double = 0
    @Published var modelPreparing = false
    @Published var level: Float = 0
    @Published var selectedTab: AppTab = .general
    @Published var micAuthorized = false
    @Published var axAuthorized = false
    @Published var micStatus: AVAuthorizationStatus = .notDetermined
    let models = LocalModels()
    private let recorder = Recorder()
    private let overlay = Overlay()
    private var insertFailure = ""
    private var targetPID: pid_t = 0
    private var targetAppName = ""
    private var targetElement: AXUIElement?
    private var task: Task<Void, Never>?
    private var meter: Timer?
    private var generation = UUID()
    private var hotKey: EventHotKeyRef?
    private var hotKeyID: UInt32 = 0
    private var gesture = HotkeyGesture()
    private var eventHandler: EventHandlerRef?
    private var escMonitor: Any?
    private let defaultsKey = "VoiceBuddy.preferences"

    init() {
        preferences = UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        refreshPermissions()
        registerHotkey()
    }
    func refreshPermissions() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        micAuthorized = (micStatus == .authorized)
        axAuthorized = AXIsProcessTrusted()
    }
    func requestMicrophoneAccess() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshPermissions()
        }
    }
    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
    }
    func openSystemSettings(for permission: String) {
        let urlString = permission == "microphone"
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
    func label(_ en: String, _ zh: String) -> String {
        let chinese = preferences.interfaceLanguage == "zh" || (preferences.interfaceLanguage == "system" && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
        return chinese ? zh : en
    }
    private func save() { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: defaultsKey) } }
    @discardableResult func registerHotkey(keyCode: UInt32? = nil, modifiers: UInt32? = nil) -> Bool {
        if eventHandler == nil {
            var events = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            InstallEventHandler(GetApplicationEventTarget(), { _, event, info in
                guard let info, let event else { return OSStatus(eventNotHandledErr) }
                let state = Unmanaged<AppState>.fromOpaque(info).takeUnretainedValue()
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                Task { @MainActor in if pressed { state.hotkeyDown() } else { state.hotkeyUp() } }
                return noErr
            }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        let key = keyCode ?? preferences.shortcutKeyCode, mods = modifiers ?? preferences.shortcutModifiers
        if hotKey != nil && key == preferences.shortcutKeyCode && mods == preferences.shortcutModifiers { return true }
        hotKeyID &+= 1
        let id = EventHotKeyID(signature: 0x56425544, id: hotKeyID)
        var replacement: EventHotKeyRef?
        let code = RegisterEventHotKey(key, mods, id, GetApplicationEventTarget(), 0, &replacement)
        guard code == noErr, let replacement else { status = label("Shortcut unavailable; previous shortcut retained.", "快捷键不可用，已保留原快捷键。 "); return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = replacement
        preferences.shortcutKeyCode = key; preferences.shortcutModifiers = mods
        return true
    }
    func prepareSpeech() {
        guard !busy else { return }; busy = true; modelPreparing = true; modelProgress = 0; ready = false; status = label("Preparing speech model…", "正在准备语音模型…")
        let id = preferences.speechModel, operation = UUID(); generation = operation
        task = Task {
            do {
                try await models.prepareSpeech(id: id) { [weak self] value, _ in Task { @MainActor in guard self?.generation == operation else { return }; self?.modelProgress = value } }
                guard generation == operation else { return }; ready = true; status = label("Speech model ready", "语音模型已就绪")
            } catch { guard generation == operation else { return }; status = error.localizedDescription }
            modelPreparing = false; busy = false
        }
    }
    func prepareEditor() {
        guard !busy else { return }; busy = true; modelPreparing = true; modelProgress = 0; editorReady = false; status = label("Preparing text model…", "正在准备文本模型…")
        let operation = UUID(); generation = operation
        task = Task {
            do {
                try await models.prepareEditor { [weak self] value, _ in Task { @MainActor in guard self?.generation == operation else { return }; self?.modelProgress = value } }
                guard generation == operation else { return }; editorReady = true; status = label("Text model ready", "文本模型已就绪")
            } catch { guard generation == operation else { return }; status = error.localizedDescription }
            modelPreparing = false; busy = false
        }
    }
    func removeSpeechModel() {
        guard !busy && !recording else { return }; let id = preferences.speechModel; busy = true
        Task { do { try await models.removeSpeech(id: id); ready = false; status = label("Speech model removed", "语音模型已删除") } catch { status = error.localizedDescription }; busy = false }
    }
    func removeTextModel() {
        guard !busy && !recording else { return }; busy = true
        Task { do { try await models.removeEditor(); editorReady = false; status = label("Text model removed", "文本模型已删除") } catch { status = error.localizedDescription }; busy = false }
    }
    func hotkeyDown() {
        switch gesture.press(hold: preferences.holdToTalk ?? true) {
        case .startHold: start(whileHeld: true)
        case .toggle: toggle()
        default: break
        }
    }
    func hotkeyUp() {
        if gesture.release(hold: preferences.holdToTalk ?? true) == .stopHold && recording { finish() }
    }
    // The window button remains a toggle for accessibility and manual use.
    func toggle() { if recording { finish() } else { start(whileHeld: false) } }
    private func start(whileHeld: Bool) {
        guard !busy && !recording else { return }
        guard ready else { status = label("Prepare the speech model first.", "请先准备语音模型。"); showWindow(); return }
        if preferences.refinement.needsModel && !editorReady { status = label("Prepare the text model first.", "请先准备文本模型。"); showWindow(); return }
        // Snapshot the destination before requesting permissions or presenting UI.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let pid = frontmost?.processIdentifier ?? 0
        let name = frontmost?.localizedName ?? ""
        let element = focusedElement(pid: pid)
        busy = true
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            busy = false
            refreshPermissions()
            guard allowed else { status = label("Microphone permission is required.", "需要麦克风权限。"); showWindow(tab: .permissions); return }
            guard !whileHeld || gesture.isDown else { status = label("Press and hold to dictate.", "请按住快捷键说话。"); return }
            targetPID = pid
            targetAppName = name
            targetElement = element
            do {
                try recorder.start(deviceUID: preferences.microphoneUID); recording = true; status = label("Listening…", "正在听你说…"); overlay.show(state: self)
                if preferences.sounds { NSSound(named: "Tink")?.play() }
                meter = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.level = self?.recorder.currentLevel ?? 0 } }
                escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    if event.keyCode == 53 { Task { @MainActor in self?.cancel() } }
                }
            } catch { status = error.localizedDescription; showWindow() }
        }
    }
    func cancel() {
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor); escMonitor = nil }
        generation = UUID(); gesture.reset(); task?.cancel(); task = nil
        if recording { _ = recorder.stop() }; recording = false; busy = false; modelPreparing = false; meter?.invalidate(); level = 0
        overlay.hide(); if preferences.sounds { NSSound(named: "Basso")?.play() }
        status = label("Cancelled", "已取消")
    }
    private func finish() {
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor); escMonitor = nil }
        let audio = recorder.stop(); recording = false; meter?.invalidate(); level = 0; busy = true
        if preferences.sounds { NSSound(named: "Pop")?.play() }
        status = label("Transcribing…", "正在识别…"); overlay.show(state: self); let id = UUID(); generation = id
        let settings = preferences; let pipeline = Pipeline(detector: models, transcription: models, refinement: models)
        task = Task {
            do {
                let output = try await pipeline.run(samples: audio, language: settings.speechLanguage, mode: settings.refinement)
                guard generation == id else { return }; overlay.hide(); original = output.original; result = output.result; busy = false
                if settings.refinement.needsModel { status = label("Review edited text before inserting.", "请先确认整理结果。"); showWindow(tab: .recovery); return }
                if settings.autoInsert && insertIfSafe(output.result) {
                    let appName = targetAppName.isEmpty ? label("target application", "目标应用") : targetAppName
                    status = label("Inserted into \(appName)", "已插入到 \(appName)")
                } else {
                    status = settings.autoInsert && !insertFailure.isEmpty ? insertFailure : label("Result ready to copy.", "文字已准备好，请复制。 ");
                    showWindow(tab: .recovery)
                }
            } catch {
                guard generation == id else { return }
                overlay.hide()
                busy = false
                if let failure = error as? RefinementFailure {
                    original = failure.original
                    result = failure.original
                    selectedTab = .recovery
                }
                status = error.localizedDescription
                showWindow(tab: .recovery)
            }
        }
    }
    func insertIfSafe(_ text: String) -> Bool {
        insertFailure = ""
        refreshPermissions()
        guard !text.isEmpty else {
            insertFailure = label("No text to insert.", "没有可插入的文字。")
            return false
        }
        // 1. Password & Secure Input Protection
        if IsSecureEventInputEnabled() {
            insertFailure = label("Secure input is active; copied to clipboard.", "安全输入模式已启用，已复制到剪贴板。")
            copyResult()
            return false
        }
        if let element = targetElement ?? (targetPID != 0 ? focusedElement(pid: targetPID) : nil) {
            var subrole: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
               (subrole as? String) == "AXSecureTextField" {
                insertFailure = label("Password field detected; copied to clipboard.", "检测到密码输入框，已复制到剪贴板。")
                copyResult()
                return false
            }
        }
        // 2. Check if target was Voice Buddy itself (e.g. testing in Editor tab)
        let myPID = NSRunningApplication.current.processIdentifier
        if targetPID == 0 || targetPID == myPID {
            copyResult()
            return true
        }
        // 3. Ensure target application is still running
        guard let targetApp = NSRunningApplication(processIdentifier: targetPID), !targetApp.isTerminated else {
            insertFailure = label("Target application is no longer running.", "目标应用已退出，已复制到剪贴板。")
            copyResult()
            return false
        }
        // 4. Try Direct Accessibility Insertion (if supported by standard controls)
        if AXIsProcessTrusted(), let element = targetElement ?? focusedElement(pid: targetPID) {
            var isSettable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSettable) == .success,
               isSettable.boolValue {
                if AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
                    return true
                }
            }
        }
        // 5. Universal Insertion via Clipboard + Synthesized ⌘V (Sublime Text, Word, Chrome, etc.)
        guard AXIsProcessTrusted() else {
            insertFailure = label("Accessibility access needed for auto-paste; copied to clipboard.", "需要辅助功能权限以自动粘贴，文字已复制到剪贴板。")
            copyResult()
            return false
        }
        // Re-activate target app so it receives the paste event
        if #available(macOS 14.0, *) {
            targetApp.activate()
        } else {
            targetApp.activate(options: [.activateIgnoringOtherApps])
        }

        // Backup current clipboard
        let board = NSPasteboard.general
        let savedItems: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }

        // Put recognized text on pasteboard
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for marker in ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType"] {
            item.setString("", forType: NSPasteboard.PasteboardType(marker))
        }
        guard board.writeObjects([item]) else {
            insertFailure = label("Failed to write to clipboard.", "写入剪贴板失败。")
            return false
        }
        let count = board.changeCount

        // Give target app's window server activation a brief moment to settle before posting ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        // Restore original clipboard after target app has had time to read it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard board.changeCount == count else { return }
            if !savedItems.isEmpty {
                board.clearContents()
                let restored: [NSPasteboardItem] = savedItems.compactMap { entries in
                    guard !entries.isEmpty else { return nil }
                    let item = NSPasteboardItem()
                    for (type, data) in entries {
                        item.setData(data, forType: type)
                    }
                    return item
                }
                if !restored.isEmpty {
                    board.writeObjects(restored)
                }
            }
        }
        return true
    }
    private func focusedElement(pid: pid_t) -> AXUIElement? {
        guard pid != 0 else { return nil }; var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func copyResult() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string); status = label("Copied", "已复制") }
    func showWindow(tab: AppTab? = nil) {
        if let tab { selectedTab = tab }
        refreshPermissions()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
        } else {
            for window in NSApp.windows where !window.isFloatingPanel && !(window is NSPanel) {
                window.isReleasedWhenClosed = false
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}

@main struct VoiceBuddyApp: App {
    @StateObject private var state = AppState()
    var body: some Scene {
        Window("Voice Buddy", id: "main") {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 700, minHeight: 540)
        }
        MenuBarExtra("Voice Buddy", systemImage: state.recording ? "waveform.circle.fill" : "waveform") {
            Text("Voice Buddy: \(state.status)")
            Divider()
            Button(state.recording ? state.label("Stop Dictation", "结束听写") : state.label("Start Dictation", "开始听写")) {
                state.toggle()
            }.keyboardShortcut("d")
            Divider()
            Button(state.label("Settings…", "设置…")) {
                state.showWindow(tab: .general)
            }
            Button(state.label("Permissions…", "权限检查…")) {
                state.showWindow(tab: .permissions)
            }
            Button(state.label("Result Editor…", "文本编辑器…")) {
                state.showWindow(tab: .recovery)
            }
            Divider()
            Button(state.label("Quit Voice Buddy", "退出 Voice Buddy")) {
                NSApp.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
