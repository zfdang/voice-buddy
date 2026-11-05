import SwiftUI
import AppKit
import Carbon
import ApplicationServices
import AVFoundation
import VoiceBuddyCore

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
    @Published var selectedTab = 0
    let models = LocalModels()
    private let recorder = Recorder()
    private let overlay = Overlay()
    private var insertFailure = ""
    private var targetPID: pid_t = 0
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
        registerHotkey()
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
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let element = focusedElement(pid: pid)
        busy = true
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            busy = false
            guard allowed else { status = label("Microphone permission is required.", "需要麦克风权限。"); showWindow(); return }
            guard !whileHeld || gesture.isDown else { status = label("Press and hold to dictate.", "请按住快捷键说话。"); return }
            targetPID = pid; targetElement = element
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
                if settings.refinement.needsModel { status = label("Review edited text before inserting.", "请先确认整理结果。"); showWindow(); return }
                if settings.autoInsert && insertIfSafe(output.result) { status = label("Paste requested; check the target.", "已请求粘贴，请检查目标应用。") }
                else { status = settings.autoInsert && !insertFailure.isEmpty ? insertFailure : label("Result ready to copy.", "文字已准备好，请复制。 "); showWindow() }
            } catch { guard generation == id else { return }; overlay.hide(); busy = false; if let failure = error as? RefinementFailure { original = failure.original; result = failure.original; selectedTab = 3 }; status = error.localizedDescription; showWindow() }
        }
    }
    func insertIfSafe(_ text: String) -> Bool {
        insertFailure = ""
        guard !text.isEmpty else { insertFailure = label("No text to insert.", "没有可插入的文字。"); return false }
        guard AXIsProcessTrusted() else { insertFailure = label("Accessibility access is needed; copy manually.", "需要辅助功能权限，请手动复制。 "); return false }
        guard !IsSecureEventInputEnabled() else { insertFailure = label("Secure input is active; copy manually.", "安全输入模式已启用，请手动复制。 "); return false }
        guard targetPID != 0, let saved = targetElement else { insertFailure = label("Original input field was unavailable; copy manually.", "无法确认原输入框，请手动复制。 "); return false }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else { insertFailure = label("The target app changed; copy manually.", "目标应用已改变，请手动复制。 "); return false }
        guard let focused = focusedElement(pid: targetPID), CFEqual(saved, focused) else { insertFailure = label("The input focus changed; copy manually.", "输入焦点已改变，请手动复制。 "); return false }
        var role: CFTypeRef?, subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &role) == .success,
              let roleName = role as? String, ["AXTextField", "AXTextArea", "AXComboBox"].contains(roleName) else { insertFailure = label("Cannot verify the target field; copy manually.", "无法确认目标输入框，请手动复制。 "); return false }
        if AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subrole) == .success, (subrole as? String) == "AXSecureTextField" { insertFailure = label("Secure input is active; copy manually.", "安全输入模式已启用，请手动复制。 "); return false }
        let board = NSPasteboard.general
        // Avoid overwriting clipboard contents that cannot be safely restored.
        let old = board.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
        if (board.pasteboardItems?.count ?? 0) != old.count || zip(board.pasteboardItems ?? [], old).contains(where: { $0.0.types.count != $0.1.count }) { insertFailure = label("Clipboard cannot be safely restored; copy manually.", "无法安全恢复剪贴板，请手动复制。 "); return false }
        board.clearContents()
        let item = NSPasteboardItem(); item.setString(text, forType: .string)
        for type in ["org.nspasteboard.TransientType", "org.nspasteboard.ConcealedType", "org.nspasteboard.AutoGeneratedType"] { item.setString("", forType: NSPasteboard.PasteboardType(type)) }
        guard board.writeObjects([item]) else { return false }; let count = board.changeCount
        guard let source = CGEventSource(stateID: .combinedSessionState), let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand; down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard board.changeCount == count else { return }
            board.clearContents(); let items: [NSPasteboardItem] = old.map { values in let i = NSPasteboardItem(); for (type, data) in values { i.setData(data, forType: type) }; return i }; if !items.isEmpty { board.writeObjects(items) }
        }
        return true
    }
    private func focusedElement(pid: pid_t) -> AXUIElement? {
        guard pid != 0 else { return nil }; var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func copyResult() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string); status = label("Copied", "已复制") }
    func showWindow() { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil) }
}

@main struct VoiceBuddyApp: App {
    @StateObject private var state = AppState()
    var body: some Scene {
        Window("Voice Buddy", id: "main") { MainView().environmentObject(state).frame(minWidth: 700, minHeight: 540) }
        MenuBarExtra {
            Button(state.recording ? "Stop / 结束" : "Dictate / 听写") { state.toggle() }.keyboardShortcut("d")
            Button("Settings / 设置") { state.showWindow() }
            Button("Quit / 退出") { NSApp.terminate(nil) }
        } label: {
            if let url = Bundle.module.url(forResource: "mascot", withExtension: "png"), let image = NSImage(contentsOf: url) { Image(nsImage: image) } else { Image(systemName: "waveform") }
        }
    }
}
