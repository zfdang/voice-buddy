import SwiftUI
import AppKit
import ApplicationServices
import AVFoundation
import VoiceBuddyCore
import KeyboardShortcuts
import Sparkle
import LaunchAtLogin

public enum AppTab: Int, CaseIterable, Identifiable {
    case general = 0
    case permissions = 1
    case speech = 2
    case editor = 3
    case recovery = 4
    case about = 5
    public var id: Int { rawValue }
}

@MainActor final class AppState: ObservableObject {
    @Published var preferences: Preferences { didSet { save(); if oldValue.useFnKey != preferences.useFnKey { configureShortcutMode() } } }
    @Published var status = "Ready"
    @Published var liveTranscript = ""
    @Published var liveTranscriptState = LiveTranscriptState()
    private let tracker = TranscriptStreamTracker()
    @Published var result = ""
    @Published var original = ""
    @Published var recording = false
    @Published var ready = false
    @Published var editorReady = false
    @Published var isSpeechDownloaded = false
    @Published var isEditorDownloaded = false
    @Published var cachedSpeechModelIDs: Set<String> = []
    @Published var activeDownloadingSpeechModelID: String? = nil
    @Published var cachedTextModelIDs: Set<String> = []
    @Published var activeDownloadingTextModelID: String? = nil
    @Published var speechPreparing = false
    @Published var speechProgress: Double = 0
    @Published var speechProgressMessage = ""
    @Published var editorPreparing = false
    @Published var editorProgress: Double = 0
    @Published var editorProgressMessage = ""
    @Published var busy = false
    @Published var modelProgress: Double = 0
    @Published var modelPreparing = false
    @Published var level: Float = 0
    @Published var selectedTab: AppTab = .general
    @Published var micAuthorized = false
    @Published var axAuthorized = false
    @Published var micStatus: AVAuthorizationStatus = .notDetermined
    let models = LocalModels()
    let updater = UpdaterViewModel()
    private let mediaPlayback = MediaPlaybackController(fallbackBackend: AccessibleMediaPlaybackBackend()) { event in
        DiagnosticLog.shared.record("media.\(event.rawValue)")
    }
    private let recorder = Recorder()
    private let overlay = Overlay()
    private(set) var insertFailure = ""
    private var targetPID: pid_t = 0
    private var targetAppName = ""
    private var targetElement: AXUIElement?
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionGeneration = UUID()
    private var diagnosticSession = UUID()
    private var speechTask: Task<Void, Never>?
    private var speechGeneration = UUID()
    private var editorTask: Task<Void, Never>?
    private var editorGeneration = UUID()
    private var liveTask: Task<Void, Never>?
    private var meter: Timer?
    private var gesture = HotkeyGesture()
    private var fnGesture = FnKeyGesture()
    private var fnOtherModifiers: NSEvent.ModifierFlags = []
    private var fnStartedRecording = false
    private var fnGlobalMonitor: Any?
    private var fnLocalMonitor: Any?
    private var escMonitor: Any?
    private let defaultsKey = "VoiceBuddy.preferences"

    init() {
        preferences = UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        DiagnosticLog.shared.record("app.start version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        refreshPermissions()
        setupKeyboardShortcuts()
        configureShortcutMode()
        autoPreloadModels()
    }
    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            Task { @MainActor in self?.hotkeyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
            Task { @MainActor in self?.hotkeyUp() }
        }
    }
    private func configureShortcutMode() {
        fnGesture.reset()
        fnOtherModifiers = NSEvent.modifierFlags.intersection([.shift, .control, .option, .command])
        gesture.reset()
        fnStartedRecording = false
        if let fnGlobalMonitor { NSEvent.removeMonitor(fnGlobalMonitor); self.fnGlobalMonitor = nil }
        if let fnLocalMonitor { NSEvent.removeMonitor(fnLocalMonitor); self.fnLocalMonitor = nil }
        if preferences.useFnKey {
            KeyboardShortcuts.disable(.toggleDictation)
            let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
            fnGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                let flags = event.modifierFlags, type = event.type
                Task { @MainActor in self?.handleFnEvent(flags: flags, type: type) }
            }
            fnLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                let flags = event.modifierFlags, type = event.type
                Task { @MainActor in self?.handleFnEvent(flags: flags, type: type) }
                return event
            }
            DiagnosticLog.shared.record("shortcut.fn.monitor global=\(fnGlobalMonitor != nil) local=\(fnLocalMonitor != nil)")
        } else {
            KeyboardShortcuts.enable(.toggleDictation)
        }
    }
    private func handleFnEvent(flags: NSEvent.ModifierFlags, type: NSEvent.EventType) {
        guard preferences.useFnKey else { return }
        let action: FnKeyGesture.Action
        if type == .flagsChanged {
            let fnDown = flags.contains(.function)
            let wasDown = fnGesture.isDown
            let otherModifiers = flags.intersection([.shift, .control, .option, .command])
            let otherModifiersChanged = otherModifiers != fnOtherModifiers
            fnOtherModifiers = otherModifiers
            action = fnGesture.flagsChanged(fnDown: fnDown, otherModifierChanged: otherModifiersChanged, otherModifiersHeld: !otherModifiers.isEmpty, holdToTalk: preferences.holdToTalk ?? true)
            if fnDown != wasDown { DiagnosticLog.shared.record("shortcut.fn.transition down=\(fnDown) action=\(String(describing: action))") }
            if action == .cancel { DiagnosticLog.shared.record("shortcut.fn.chord cancelled=true") }
        } else if type == .keyDown {
            action = fnGesture.otherKeyPressed()
            if action == .cancel { DiagnosticLog.shared.record("shortcut.fn.chord cancelled=true") }
        } else { return }
        switch action {
        case .press:
            let wasRecording = recording
            hotkeyDown()
            fnStartedRecording = !wasRecording && recording
        case .release:
            hotkeyUp(); fnStartedRecording = false
        case .cancel:
            if fnStartedRecording && recording { cancel() } else { gesture.reset() }
            fnStartedRecording = false
        case .tap:
            hotkeyDown(); hotkeyUp()
        case .none: break
        }
    }
    func checkForUpdates() {
        updater.checkForUpdates()
    }
    func checkModelCacheStatus(completion: (@MainActor @Sendable () -> Void)? = nil) {
        Task {
            var cachedSpeeches = Set<String>()
            for spec in SpeechModelSpec.allModels {
                if await models.isSpeechModelCached(id: spec.id) {
                    cachedSpeeches.insert(spec.id)
                }
            }
            var cachedTexts = Set<String>()
            for spec in TextModelSpec.allModels {
                if await models.isEditorModelCached(id: spec.id) {
                    cachedTexts.insert(spec.id)
                }
            }
            await MainActor.run {
                self.cachedSpeechModelIDs = cachedSpeeches
                self.cachedTextModelIDs = cachedTexts

                if !cachedSpeeches.contains(self.preferences.speechModel), let first = SpeechModelSpec.allModels.first(where: { cachedSpeeches.contains($0.id) }) {
                    self.preferences.speechModel = first.id
                }
                self.isSpeechDownloaded = self.cachedSpeechModelIDs.contains(self.preferences.speechModel)

                if !cachedTexts.contains(self.preferences.textModel), let first = TextModelSpec.allModels.first(where: { cachedTexts.contains($0.id) }) {
                    self.preferences.textModel = first.id
                }
                self.isEditorDownloaded = self.cachedTextModelIDs.contains(self.preferences.textModel)

                completion?()
            }
        }
    }
    func autoPreloadModels() {
        checkModelCacheStatus { [weak self] in
            guard let self else { return }
            if self.isSpeechDownloaded && !self.ready && !self.speechPreparing {
                self.loadActiveSpeechModel()
            }
            if self.isEditorDownloaded && !self.editorReady && !self.editorPreparing {
                self.loadActiveEditorModel()
            }
        }
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
    func loadActiveSpeechModel() {
        prepareSpeech(id: preferences.speechModel)
    }

    func selectSpeechModel(id: String) {
        guard preferences.speechModel != id else { return }
        preferences.speechModel = id
        ready = false
        if cachedSpeechModelIDs.contains(id) {
            prepareSpeech(id: id)
        }
    }

    func downloadSpeechModel(id: String) {
        prepareSpeech(id: id) { [weak self] success in
            guard let self, success else { return }
            if !self.cachedSpeechModelIDs.contains(self.preferences.speechModel) || self.preferences.speechModel == id {
                self.preferences.speechModel = id
                self.ready = true
            } else {
                // Restore active model in memory if user was using another model
                self.loadActiveSpeechModel()
            }
        }
    }

    func prepareSpeech(id: String? = nil, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        guard !speechPreparing && !recording else { completion?(false); return }
        speechPreparing = true
        let targetId = id ?? preferences.speechModel
        let isSelectedModel = (targetId == preferences.speechModel)
        if isSelectedModel {
            modelPreparing = true
            modelProgress = 0
            status = label("Preparing speech model…", "正在准备语音识别模型…")
        }
        speechProgress = 0
        activeDownloadingSpeechModelID = targetId
        speechProgressMessage = label("Preparing speech model…", "正在准备语音识别模型…")
        let operation = UUID()
        DiagnosticLog.shared.record("model.speech.prepare id=\(operation) known_model=\(SpeechModelSpec.allModels.contains { $0.id == targetId })")
        speechGeneration = operation
        speechTask = Task {
            do {
                try await models.prepareSpeech(id: targetId) { [weak self] value, msg in
                    Task { @MainActor in
                        guard self?.speechGeneration == operation else { return }
                        self?.speechProgress = value
                        if isSelectedModel {
                            self?.modelProgress = value
                        }
                        self?.speechProgressMessage = msg
                    }
                }
                DiagnosticLog.shared.record("model.speech.prepared id=\(operation)")
                guard speechGeneration == operation else {
                    await MainActor.run {
                        if self.speechGeneration == operation {
                            self.speechPreparing = false
                            self.activeDownloadingSpeechModelID = nil
                        }
                        completion?(false)
                    }
                    return
                }
                await MainActor.run {
                    self.cachedSpeechModelIDs.insert(targetId)
                    if isSelectedModel {
                        self.ready = true
                    }
                    self.isSpeechDownloaded = self.cachedSpeechModelIDs.contains(self.preferences.speechModel)
                    self.speechPreparing = false
                    if isSelectedModel {
                        self.modelPreparing = false
                        self.status = self.label("Speech model ready", "语音识别已就绪")
                    }
                    self.activeDownloadingSpeechModelID = nil
                    completion?(true)
                }
            } catch {
                DiagnosticLog.shared.record("model.speech.failed id=\(operation) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code)")
                guard speechGeneration == operation else {
                    await MainActor.run {
                        if self.speechGeneration == operation {
                            self.speechPreparing = false
                            self.activeDownloadingSpeechModelID = nil
                        }
                        completion?(false)
                    }
                    return
                }
                await MainActor.run {
                    if isSelectedModel {
                        self.status = error.localizedDescription
                    }
                    self.speechProgressMessage = error.localizedDescription
                    self.speechPreparing = false
                    if isSelectedModel {
                        self.modelPreparing = false
                    }
                    self.activeDownloadingSpeechModelID = nil
                    completion?(false)
                }
            }
        }
    }

    func loadActiveEditorModel() {
        prepareEditor(id: preferences.textModel)
    }

    func selectTextModel(id: String) {
        guard preferences.textModel != id else { return }
        preferences.textModel = id
        editorReady = false
        if cachedTextModelIDs.contains(id) {
            prepareEditor(id: id)
        }
    }

    func downloadTextModel(id: String) {
        prepareEditor(id: id) { [weak self] success in
            guard let self, success else { return }
            if !self.cachedTextModelIDs.contains(self.preferences.textModel) || self.preferences.textModel == id {
                self.preferences.textModel = id
                self.editorReady = true
            } else {
                // Restore active model in memory if user was using another model
                self.loadActiveEditorModel()
            }
        }
    }

    func prepareEditor(id: String? = nil, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        guard !editorPreparing && !recording else { completion?(false); return }
        editorPreparing = true
        let targetId = id ?? preferences.textModel
        let isSelectedModel = (targetId == preferences.textModel)
        if isSelectedModel {
            modelPreparing = true
            modelProgress = 0
            status = label("Preparing text model…", "正在准备文本模型…")
        }
        editorProgress = 0
        activeDownloadingTextModelID = targetId
        editorProgressMessage = label("Preparing text model…", "正在准备文本模型…")
        let operation = UUID()
        DiagnosticLog.shared.record("model.text.prepare id=\(operation) known_model=\(TextModelSpec.allModels.contains { $0.id == targetId })")
        editorGeneration = operation
        editorTask = Task {
            do {
                try await models.prepareEditor(id: targetId) { [weak self] value, msg in
                    Task { @MainActor in
                        guard self?.editorGeneration == operation else { return }
                        self?.editorProgress = value
                        if isSelectedModel {
                            self?.modelProgress = value
                        }
                        self?.editorProgressMessage = msg
                    }
                }
                DiagnosticLog.shared.record("model.text.prepared id=\(operation)")
                guard editorGeneration == operation else {
                    await MainActor.run {
                        if self.editorGeneration == operation {
                            self.editorPreparing = false
                            self.activeDownloadingTextModelID = nil
                        }
                        completion?(false)
                    }
                    return
                }
                await MainActor.run {
                    self.cachedTextModelIDs.insert(targetId)
                    if isSelectedModel {
                        self.editorReady = true
                    }
                    self.isEditorDownloaded = self.cachedTextModelIDs.contains(self.preferences.textModel)
                    self.editorPreparing = false
                    if isSelectedModel {
                        self.modelPreparing = false
                        self.status = self.label("Text model ready", "文本模型已就绪")
                    }
                    self.activeDownloadingTextModelID = nil
                    completion?(true)
                }
            } catch {
                DiagnosticLog.shared.record("model.text.failed id=\(operation) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code)")
                guard editorGeneration == operation else {
                    await MainActor.run {
                        if self.editorGeneration == operation {
                            self.editorPreparing = false
                            self.activeDownloadingTextModelID = nil
                        }
                        completion?(false)
                    }
                    return
                }
                await MainActor.run {
                    if isSelectedModel {
                        self.status = error.localizedDescription
                    }
                    self.editorProgressMessage = error.localizedDescription
                    self.editorPreparing = false
                    if isSelectedModel {
                        self.modelPreparing = false
                    }
                    self.activeDownloadingTextModelID = nil
                    completion?(false)
                }
            }
        }
    }

    func removeSpeechModel(id: String? = nil) {
        guard !busy && !recording else { return }
        let targetId = id ?? preferences.speechModel
        busy = true
        Task {
            do {
                try await models.removeSpeech(id: targetId)
                await MainActor.run {
                    self.cachedSpeechModelIDs.remove(targetId)
                    if self.preferences.speechModel == targetId {
                        self.ready = false
                        self.isSpeechDownloaded = false
                        if let next = SpeechModelSpec.allModels.first(where: { self.cachedSpeechModelIDs.contains($0.id) }) {
                            self.preferences.speechModel = next.id
                            self.prepareSpeech(id: next.id)
                        }
                    }
                    self.status = self.label("Speech model removed", "语音模型已删除")
                }
            } catch {
                await MainActor.run {
                    self.status = error.localizedDescription
                }
            }
            await MainActor.run {
                self.busy = false
                self.checkModelCacheStatus()
            }
        }
    }

    func removeTextModel(id: String? = nil) {
        guard !busy && !recording else { return }
        let targetId = id ?? preferences.textModel
        busy = true
        Task {
            do {
                try await models.removeEditor(id: targetId)
                await MainActor.run {
                    self.cachedTextModelIDs.remove(targetId)
                    if self.preferences.textModel == targetId {
                        self.editorReady = false
                        self.isEditorDownloaded = false
                        if let next = TextModelSpec.allModels.first(where: { self.cachedTextModelIDs.contains($0.id) }) {
                            self.preferences.textModel = next.id
                            self.prepareEditor(id: next.id)
                        }
                    }
                    self.status = self.label("Text model removed", "文本模型已删除")
                }
            } catch {
                await MainActor.run {
                    self.status = error.localizedDescription
                }
            }
            await MainActor.run {
                self.busy = false
                self.checkModelCacheStatus()
            }
        }
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
        guard !busy && !recording else { DiagnosticLog.shared.record("session.start_ignored busy=\(busy) recording=\(recording)"); return }
        diagnosticSession = UUID()
        DiagnosticLog.shared.record("session.start id=\(diagnosticSession) speech_ready=\(ready) editor_ready=\(editorReady) mode=\(preferences.refinement.rawValue) auto_insert=\(preferences.autoInsert)")
        // Invalidate any delayed insertion from the previous session.
        transcriptionGeneration = UUID()
        guard ready else {
            DiagnosticLog.shared.record("session.stop id=\(diagnosticSession) reason=speech_model_not_ready")
            status = label("Loading speech model…", "正在加载语音模型…")
            overlay.show(state: self)
            if !speechPreparing {
                prepareSpeech { [weak self] success in
                    guard let self else { return }
                    if success {
                        self.status = self.label("Speech model ready. Press hotkey to talk.", "语音模型已就绪，请按快捷键说话。")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if !self.recording { self.overlay.hide() }
                        }
                    } else {
                        self.overlay.hide()
                    }
                }
            }
            return
        }
        if preferences.refinement.needsModel && !editorReady {
            DiagnosticLog.shared.record("session.stop id=\(diagnosticSession) reason=text_model_not_ready")
            status = label("Loading text model…", "正在加载文本模型…")
            overlay.show(state: self)
            if !editorPreparing {
                prepareEditor { [weak self] success in
                    guard let self else { return }
                    if success {
                        self.status = self.label("Text model ready. Press hotkey to talk.", "文本模型已就绪，请按快捷键说话。")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if !self.recording { self.overlay.hide() }
                        }
                    } else {
                        self.overlay.hide()
                    }
                }
            }
            return
        }
        // Snapshot the destination with system-wide + frontmost fallbacks and wake accessibility
        let target = TargetAccessibility.captureTargetFocus()
        let pid = target.pid
        let name = target.name
        let element = target.element
        DiagnosticLog.shared.record("session.target id=\(diagnosticSession) pid=\(pid) focus_present=\(element != nil)")

        refreshPermissions()
        DiagnosticLog.shared.record("permissions id=\(diagnosticSession) microphone=\(micAuthorized) accessibility=\(axAuthorized)")
        guard micAuthorized else {
            DiagnosticLog.shared.record("session.stop id=\(diagnosticSession) reason=microphone_permission")
            status = label("Microphone permission required.", "需要麦克风权限。")
            requestMicrophoneAccess()
            overlay.showStatus(state: self)
            return
        }

        guard !whileHeld || gesture.isDown else {
            DiagnosticLog.shared.record("session.stop id=\(diagnosticSession) reason=hotkey_released")
            status = label("Press and hold to dictate.", "请按住快捷键说话。")
            return
        }

        targetPID = pid
        targetAppName = name
        targetElement = element

        do {
            try recorder.start(deviceUID: preferences.microphoneUID)
            recording = true
            DiagnosticLog.shared.record("recording.started id=\(diagnosticSession)")
            if preferences.pauseMediaDuringRecording {
                mediaPlayback.pauseIfPlaying()
            }
            status = label("Listening…", "正在听你说…")
            startLiveStreaming()
            overlay.show(state: self, screenPoint: targetWindowCenter() ?? targetInsertionPoint() ?? NSEvent.mouseLocation)
            if preferences.sounds { NSSound(named: "Tink")?.play() }
            meter = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.level = self?.recorder.currentLevel ?? 0 }
            }
            escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { Task { @MainActor in self?.cancel() } }
            }
        } catch {
            DiagnosticLog.shared.record("recording.failed id=\(diagnosticSession) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code)")
            status = error.localizedDescription
            overlay.showStatus(state: self)
        }
    }
    private func startLiveStreaming() {
        liveTask?.cancel()
        tracker.reset()
        tracker.onUpdate = { [weak self] state in
            self?.liveTranscriptState = state
        }
        liveTranscriptState.clear()
        liveTranscript = ""
        let lang = preferences.speechLanguage
        let logSession = diagnosticSession
        DiagnosticLog.shared.record("stream.started id=\(logSession)")
        liveTask = Task.detached(priority: .userInitiated) { [weak self] in
            var lastCount = 0
            var failureLogged = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard let self else { break }
                let isRec = await self.recording
                guard isRec else { break }
                let samples = await self.recorder.currentSamples
                guard samples.count >= 5600, samples.count >= lastCount + 3200 else { continue }
                lastCount = samples.count
                do {
                    let text = try await self.models.transcribe(samples: samples, language: lang)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        await MainActor.run {
                            if self.recording {
                                self.liveTranscript = trimmed
                                self.liveTranscriptState = self.tracker.update(rawText: trimmed)
                            }
                        }
                    }
                } catch {
                    if !failureLogged && !Task.isCancelled {
                        DiagnosticLog.shared.record("stream.failed id=\(logSession) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code)")
                        failureLogged = true
                    }
                }
            }
            DiagnosticLog.shared.record("stream.stopped id=\(logSession)")
        }
    }
    func cancel() {
        DiagnosticLog.shared.record("session.cancel id=\(diagnosticSession)")
        mediaPlayback.resumeIfPaused()
        liveTask?.cancel(); liveTask = nil; liveTranscript = ""; liveTranscriptState.clear(); tracker.reset()
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor); escMonitor = nil }
        transcriptionGeneration = UUID()
        speechGeneration = UUID()
        editorGeneration = UUID()
        gesture.reset()
        transcriptionTask?.cancel(); transcriptionTask = nil
        speechTask?.cancel(); speechTask = nil
        editorTask?.cancel(); editorTask = nil
        if recording { _ = recorder.stop() }
        recording = false
        busy = false
        modelPreparing = false
        speechPreparing = false
        editorPreparing = false
        activeDownloadingSpeechModelID = nil
        activeDownloadingTextModelID = nil
        meter?.invalidate()
        level = 0
        overlay.hide(); if preferences.sounds { NSSound(named: "Basso")?.play() }
        status = label("Cancelled", "已取消")
    }
    private func targetWindowCenter() -> CGPoint? {
        guard targetPID != 0, let primary = NSScreen.screens.first else { return nil }
        let application = AXUIElementCreateApplication(targetPID)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let value = windowValue, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        let center = CGPoint(x: position.x + size.width / 2, y: primary.frame.maxY - position.y - size.height / 2)
        return NSScreen.screens.contains(where: { $0.frame.contains(center) }) ? center : nil
    }

    func targetInsertionPoint() -> CGPoint? {
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let primaryHeight = primaryScreen.frame.height
        let element = targetElement ?? (targetPID != 0 ? focusedElement(pid: targetPID) : nil)

        if let element {
            // 1. Try cursor bounds from selected text range (standard native text inputs)
            var rangeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
               let rv = rangeValue, CFGetTypeID(rv) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(rv as! AXValue, .cfRange, &range) {
                    var boundsValue: CFTypeRef?
                    if let axRange = AXValueCreate(.cfRange, &range),
                       AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &boundsValue) == .success,
                       let bv = boundsValue, CFGetTypeID(bv) == AXValueGetTypeID() {
                        var rect = CGRect.zero
                        if AXValueGetValue(bv as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 || rect.origin.x > 0 || rect.origin.y > 0 {
                            let cocoaY = primaryHeight - rect.midY
                            return CGPoint(x: rect.midX, y: cocoaY)
                        }
                    }
                }
            }

            // 2. Try element position & size (custom controls / editors like Sublime, Word, Chrome canvas)
            var posVal: CFTypeRef?
            var sizeVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
               let pos = posVal, let size = sizeVal {
                var pt = CGPoint.zero
                var sz = CGSize.zero
                AXValueGetValue(pos as! AXValue, .cgPoint, &pt)
                AXValueGetValue(size as! AXValue, .cgSize, &sz)
                if sz.width > 20 && sz.height > 10 {
                    let mouse = NSEvent.mouseLocation
                    let cocoaY = primaryHeight - pt.y - sz.height
                    let elementCocoaRect = CGRect(x: pt.x, y: cocoaY, width: sz.width, height: sz.height)
                    if elementCocoaRect.contains(mouse) {
                        return mouse
                    }
                    return CGPoint(x: pt.x + min(160, sz.width * 0.35), y: cocoaY + sz.height * 0.65)
                }
            }
        }

        // 3. Fallback: mouse pointer location
        let mouse = NSEvent.mouseLocation
        return mouse
    }
    private func finish() {
        mediaPlayback.resumeIfPaused()
        liveTask?.cancel(); liveTask = nil
        if let monitor = escMonitor { NSEvent.removeMonitor(monitor); escMonitor = nil }
        let capture = recorder.stop(); recording = false; meter?.invalidate(); level = 0; busy = true
        let audio = capture.samples
        let logSession = diagnosticSession
        DiagnosticLog.shared.record("recording.finished id=\(logSession) sample_count=\(audio.count)")
        let stats = capture.diagnostics
        DiagnosticLog.shared.record("recording.capture id=\(logSession) callbacks=\(stats.callbacks) input_frames=\(stats.inputFrames) output_frames=\(stats.outputFrames) allocation_failures=\(stats.allocationFailures) conversion_failures=\(stats.conversionFailures) empty_outputs=\(stats.emptyOutputBuffers) last_conversion_error=\(stats.lastConversionErrorCode.map(String.init) ?? "none")")
        if preferences.sounds { NSSound(named: "Pop")?.play() }
        guard !audio.isEmpty else {
            busy = false
            liveTranscriptState.clear()
            status = label("No audio was captured. Check your microphone and try again.", "没有采集到音频，请检查麦克风后重试。")
            DiagnosticLog.shared.record("recording.empty id=\(logSession)")
            overlay.showStatus(state: self)
            return
        }
        status = label("Transcribing…", "正在识别…"); overlay.show(state: self)
        let id = UUID()
        transcriptionGeneration = id
        let boundPID = targetPID
        let boundAppName = targetAppName
        let boundElement = targetElement
        let settings = preferences
        let pipeline = Pipeline(detector: models, transcription: models, refinement: models) { event in
            DiagnosticLog.shared.record("pipeline.\(event.rawValue) id=\(logSession)")
        }
        transcriptionTask = Task {
            do {
                let output = try await pipeline.run(samples: audio, language: settings.speechLanguage, mode: settings.refinement)
                guard transcriptionGeneration == id else {
                    DiagnosticLog.shared.record("transcription.discarded id=\(logSession) reason=session_changed")
                    return
                }
                DiagnosticLog.shared.record("transcription.completed id=\(logSession) mode=\(settings.refinement.rawValue)")
                original = output.original
                result = output.result
                busy = false
                if settings.refinement.needsModel {
                    DiagnosticLog.shared.record("result.review_mode id=\(logSession)")
                    overlay.hide()
                    liveTranscriptState.clear()
                    copyResult()
                    status = label("Edited text copied. Review it before pasting; open Result to compare the original.", "整理后的文字已复制，请检查后粘贴；可打开结果页查看原文。")
                    overlay.showStatus(state: self)
                    return
                }
                if settings.autoInsert {
                    let targetPt = targetInsertionPoint()
                    overlay.flyAndDismiss(to: targetPt) { [weak self] in
                        guard let self else { return }
                        guard self.transcriptionGeneration == id, !self.recording else { return }
                        self.liveTranscriptState.clear()
                        if self.insertIfSafe(output.result, targetPID: boundPID, targetAppName: boundAppName, targetElement: boundElement, sessionID: id) {
                            self.status = self.label("Preparing to paste…", "正在准备粘贴…")
                        } else {
                            self.copyResult()
                            let tip = !self.insertFailure.isEmpty ? self.insertFailure : self.label("Content copied to clipboard. Press ⌘V to paste.", "内容已复制到剪贴板，直接按 ⌘V 即可粘贴。")
                            self.status = tip
                            self.overlay.showStatus(state: self)
                        }
                    }
                } else {
                    DiagnosticLog.shared.record("result.copy_only id=\(logSession)")
                    guard transcriptionGeneration == id, !recording else { return }
                    overlay.hide()
                    liveTranscriptState.clear()
                    copyResult()
                    status = label("Content copied to clipboard. Press ⌘V to paste.", "内容已复制到剪贴板，直接按 ⌘V 即可粘贴。")
                    overlay.showStatus(state: self)
                }
            } catch {
                DiagnosticLog.shared.record("transcription.failed id=\(logSession) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code)")
                guard transcriptionGeneration == id else { return }
                if !recording {
                    liveTranscriptState.clear()
                }
                busy = false
                if let failure = error as? RefinementFailure {
                    original = failure.original
                    result = failure.original
                    copyResult()
                }
                if let voiceError = error as? VoiceBuddyError, voiceError == .noSpeech {
                    status = label("No speech detected. Please try again.", "没有检测到语音，请重试。")
                } else {
                    status = error.localizedDescription
                }
                if !recording { overlay.showStatus(state: self) }
            }
        }
    }
    func insertIfSafe(
        _ text: String,
        targetPID: pid_t? = nil,
        targetAppName: String? = nil,
        targetElement: AXUIElement? = nil,
        sessionID: UUID? = nil
    ) -> Bool {
        let effPID = targetPID ?? self.targetPID
        let initialElement = targetElement ?? self.targetElement
        let logSession = diagnosticSession
        DiagnosticLog.shared.record("insert.begin id=\(logSession) target_pid=\(effPID) initial_focus=\(initialElement != nil) trusted=\(AXIsProcessTrusted())")

        insertFailure = ""
        refreshPermissions()
        guard !text.isEmpty else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=empty_text")
            insertFailure = label("No text to insert.", "没有可插入的文字。")
            return false
        }
        // 1. Password & Sensitive Field Protection (Check BOTH current actual focus and initial focus)
        let currentFocus = TargetAccessibility.captureTargetFocus()
        let currentElem: AXUIElement? = (effPID != 0 ? focusedElement(pid: effPID) : nil) ?? (currentFocus.pid == effPID ? currentFocus.element : nil)
        let focusMatches = initialElement.flatMap { initial in currentElem.map { CFEqual(initial, $0) } } ?? false
        DiagnosticLog.shared.record("insert.focus id=\(logSession) current_pid=\(currentFocus.pid) current_present=\(currentElem != nil) matches_initial=\(focusMatches)")

        if TargetAccessibility.isSensitiveDestination(element: currentElem) || TargetAccessibility.isSensitiveDestination(element: initialElement) {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=sensitive_destination")
            insertFailure = label("Sensitive field detected; content copied to clipboard. Press ⌘V to paste.", "检测到敏感输入框，内容已复制到剪贴板，直接按 ⌘V 即可粘贴。")
            copyResult()
            return false
        }
        // 2. Check if target was Voice Buddy itself (e.g. testing in Editor tab)
        let myPID = NSRunningApplication.current.processIdentifier
        if effPID == 0 || effPID == myPID {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=no_external_target")
            copyResult()
            insertFailure = label("No external target; content copied to clipboard.", "没有外部目标，内容已复制到剪贴板。")
            return false
        }
        // 3. Ensure target application is still running
        guard let targetApp = NSRunningApplication(processIdentifier: effPID), !targetApp.isTerminated else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=target_not_running")
            insertFailure = label("Target app not running; content copied to clipboard. Press ⌘V to paste.", "目标应用未在运行，内容已复制到剪贴板，直接按 ⌘V 即可粘贴。")
            copyResult()
            return false
        }
        // 4. Target Change Protection (prevent pasting into wrong app or different focus in same app)
        // 4a. Check if frontmost application switched
        if let currentFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           currentFrontPID != effPID && currentFrontPID != myPID {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=frontmost_changed front_pid=\(currentFrontPID)")
            insertFailure = label("Target application changed; content copied to clipboard. Press ⌘V to paste.", "目标应用已切换，内容已复制到剪贴板，直接按 ⌘V 即可粘贴。")
            copyResult()
            return false
        }
        // 4b. Check if focused element switched within the same application
        guard let initial = initialElement, let current = currentElem, CFEqual(initial, current) else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=focus_unverified")
            insertFailure = label("Cannot verify the focused input; content copied to clipboard. Press ⌘V to paste.", "无法确认输入框焦点，内容已复制到剪贴板，直接按 ⌘V 即可粘贴。")
            copyResult()
            return false
        }
        // 5. Universal Insertion via Clipboard + Hardware-level Synthesized ⌘V (100% of apps supported)
        guard AXIsProcessTrusted() else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=accessibility_permission")
            insertFailure = label("Accessibility access needed; content copied to clipboard. Press ⌘V to paste.", "需要辅助功能权限以自动上屏，内容已复制到剪贴板，直接按 ⌘V 即可粘贴。")
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
        // Mark as transient & autogenerated so clipboard managers don't permanently archive it
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        guard board.writeObjects([item]) else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=clipboard_write_failed")
            insertFailure = label("Failed to write to clipboard.", "写入剪贴板失败。")
            return false
        }
        let count = board.changeCount
        DiagnosticLog.shared.record("insert.queued id=\(logSession)")

        // Avoid hardware modifier collisions (Shift, Ctrl, Alt) before sending ⌘V
        TargetAccessibility.waitForModifiersReleased(timeout: 0.25) { [weak self] in
            // Give target app's window server activation time to settle before posting ⌘V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard let self, !self.recording else { DiagnosticLog.shared.record("insert.cancelled id=\(logSession) reason=recording_or_shutdown"); return }
                if let sid = sessionID, self.transcriptionGeneration != sid { DiagnosticLog.shared.record("insert.cancelled id=\(logSession) reason=session_changed"); return }
                guard board.changeCount == count, board.string(forType: .string) == text else {
                    DiagnosticLog.shared.record("insert.cancelled id=\(logSession) reason=clipboard_changed")
                    self.status = self.label("Clipboard changed; paste was cancelled.", "剪贴板已改变，已取消粘贴。")
                    self.overlay.showStatus(state: self)
                    return
                }
                let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                let liveFocus = self.focusedElement(pid: effPID)
                let focusMatches = liveFocus.map { CFEqual(initial, $0) } ?? false
                let sensitive = TargetAccessibility.isSensitiveDestination(element: liveFocus)
                DiagnosticLog.shared.record("insert.final_check id=\(logSession) front_pid=\(frontPID) focus_present=\(liveFocus != nil) focus_matches=\(focusMatches) sensitive=\(sensitive)")
                guard frontPID == effPID, focusMatches, !sensitive else {
                    DiagnosticLog.shared.record("insert.cancelled id=\(logSession) reason=final_focus_unverified")
                    self.status = self.label("Could not verify the target; text remains on the clipboard.", "无法确认目标输入框，文字仍在剪贴板中。")
                    self.overlay.showStatus(state: self)
                    return
                }
                guard TargetAccessibility.postPasteShortcut() else {
                    DiagnosticLog.shared.record("insert.failed id=\(logSession) reason=event_creation")
                    self.status = self.label("Paste could not be sent; text remains on the clipboard.", "无法发送粘贴命令，文字仍在剪贴板中。")
                    self.overlay.showStatus(state: self)
                    return
                }
                self.status = self.label("Paste command sent.", "已发送粘贴命令。")
                DiagnosticLog.shared.record("insert.paste_posted id=\(logSession)")
                // Restoring on a timer is still best-effort: AppKit does not report
                // when the receiving app has consumed the clipboard.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    guard board.changeCount == count else { DiagnosticLog.shared.record("clipboard.restore_skipped id=\(logSession) reason=ownership_changed"); return }
                    board.clearContents()
                    if !savedItems.isEmpty {
                        let restored: [NSPasteboardItem] = savedItems.compactMap { entries in
                            guard !entries.isEmpty else { return nil }
                            let item = NSPasteboardItem()
                            for (type, data) in entries { item.setData(data, forType: type) }
                            return item
                        }
                        if !restored.isEmpty { board.writeObjects(restored) }
                    }
                    DiagnosticLog.shared.record("clipboard.restore_attempted id=\(logSession)")
                }
            }
        }
        return true
    }
    private func focusedElement(pid: pid_t) -> AXUIElement? {
        TargetAccessibility.focusedElement(processIdentifier: pid)
    }
    func copyResult() {
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(result, forType: .string)
        DiagnosticLog.shared.record("clipboard.copy id=\(diagnosticSession) success=\(success)")
        status = success ? label("Copied", "已复制") : label("Copy failed", "复制失败")
    }
    static let menuBarMascotIcon: NSImage = {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size)

        let url1x = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
        let url2x = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png")

        if let url1x, let data1x = try? Data(contentsOf: url1x), let rep1x = NSBitmapImageRep(data: data1x) {
            rep1x.size = size
            img.addRepresentation(rep1x)
        }
        if let url2x, let data2x = try? Data(contentsOf: url2x), let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = size
            img.addRepresentation(rep2x)
        }

        if !img.representations.isEmpty {
            img.isTemplate = true
            return img
        }

        if let url = url1x ?? url2x, let raw = NSImage(contentsOf: url) {
            raw.size = size
            raw.isTemplate = true
            return raw
        }

        let fallback = NSImage(systemSymbolName: "figure.wave", accessibilityDescription: "Voice Buddy") ?? NSImage()
        fallback.size = size
        fallback.isTemplate = true
        return fallback
    }()
    static let menuBarActiveIcon: NSImage = {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size)

        let url1x = Bundle.main.url(forResource: "MenuBarIconColor", withExtension: "png")
        let url2x = Bundle.main.url(forResource: "MenuBarIconColor@2x", withExtension: "png")

        if let url1x, let data1x = try? Data(contentsOf: url1x), let rep1x = NSBitmapImageRep(data: data1x) {
            rep1x.size = size
            img.addRepresentation(rep1x)
        }
        if let url2x, let data2x = try? Data(contentsOf: url2x), let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = size
            img.addRepresentation(rep2x)
        }

        if !img.representations.isEmpty {
            img.isTemplate = false
            return img
        }

        if let url = url1x ?? url2x, let raw = NSImage(contentsOf: url) {
            raw.size = size
            raw.isTemplate = false
            return raw
        }

        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording") ?? NSImage()
        fallback.size = size
        return fallback
    }()
    static let appMascotColorIcon: NSImage = {
        let size = NSSize(width: 44, height: 44)
        let img = NSImage(size: size)

        let url1x = Bundle.main.url(forResource: "MenuBarIconColor", withExtension: "png")
        let url2x = Bundle.main.url(forResource: "MenuBarIconColor@2x", withExtension: "png")

        if let url2x, let data2x = try? Data(contentsOf: url2x), let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = size
            img.addRepresentation(rep2x)
        } else if let url1x, let data1x = try? Data(contentsOf: url1x), let rep1x = NSBitmapImageRep(data: data1x) {
            rep1x.size = size
            img.addRepresentation(rep1x)
        }

        if !img.representations.isEmpty {
            img.isTemplate = false
            return img
        }

        if let url = url2x ?? url1x, let raw = NSImage(contentsOf: url) {
            raw.size = size
            raw.isTemplate = false
            return raw
        }

        return menuBarActiveIcon
    }()
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
        MenuBarExtra {
            Button(state.label("Settings…", "设置…")) {
                state.showWindow(tab: .general)
            }.keyboardShortcut(",")
            Button(state.label("Recognition Result…", "识别结果…")) {
                state.showWindow(tab: .recovery)
            }
            Divider()
            Button(state.label("About Voice Buddy…", "关于 Voice Buddy…")) {
                state.showWindow(tab: .about)
            }
            Button(state.label("Check for Updates…", "检查更新…")) {
                state.checkForUpdates()
            }
            Divider()
            Button(state.label("Quit Voice Buddy", "退出 Voice Buddy")) {
                NSApp.terminate(nil)
            }.keyboardShortcut("q")
        } label: {
            if state.recording {
                Image(nsImage: AppState.menuBarActiveIcon)
            } else {
                Image(nsImage: AppState.menuBarMascotIcon)
            }
        }
    }
}
