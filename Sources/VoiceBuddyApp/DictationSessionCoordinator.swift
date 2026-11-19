import AppKit
import ApplicationServices
import Foundation
import KeyboardShortcuts
import VoiceBuddyCore

/// Coordinates dictation lifecycle, global hotkey/Fn gestures, live streaming preview,
/// AX target capture, and safe clipboard-backed insertion.
@MainActor
final class DictationSessionCoordinator {
    private let preferencesStore: PreferencesStore
    private let permissionsStore: PermissionsStore
    private let modelCatalog: ModelCatalogStore
    private let hud: LiveHUDState

    private let mediaPlayback = MediaPlaybackController(fallbackBackend: AccessibleMediaPlaybackBackend()) { event in
        DiagnosticLog.shared.record("media.\(event.rawValue)")
    }
    private let recorder = Recorder()
    private let overlay = Overlay()
    private let tracker = TranscriptStreamTracker()

    private(set) var insertFailure = ""
    private var targetPID: pid_t = 0
    private var targetAppName = ""
    private var targetElement: AXUIElement?
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionGeneration = UUID()
    private(set) var diagnosticSession = UUID()
    private var liveTask: Task<Void, Never>?
    private var meter: Timer?
    private var gesture = HotkeyGesture()
    private var activePasteboardSession: TemporaryPasteboard?
    private var fnGesture = FnKeyGesture()
    private var fnOtherModifiers: NSEvent.ModifierFlags = []
    private var fnStartedRecording = false
    private var fnGlobalMonitor: Any?
    private var fnLocalMonitor: Any?
    private var escMonitor: Any?

    struct EventMonitorDriver {
        var addGlobalMonitor: (NSEvent.EventTypeMask, @escaping @Sendable (NSEvent) -> Void) -> Any?
        var addLocalMonitor: (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
        var removeMonitor: (Any) -> Void

        static let system = EventMonitorDriver(
            addGlobalMonitor: { mask, handler in
                NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
            },
            addLocalMonitor: { mask, handler in
                NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
            },
            removeMonitor: { monitor in
                NSEvent.removeMonitor(monitor)
            }
        )

        static let noop = EventMonitorDriver(
            addGlobalMonitor: { _, _ in NSObject() },
            addLocalMonitor: { _, _ in NSObject() },
            removeMonitor: { _ in }
        )
    }

    private let isBusy: () -> Bool
    private let setBusy: (Bool) -> Void
    private let onTranscriptProduced: (String, String) -> Void
    private let getResult: () -> String
    private let registerSystemShortcuts: Bool
    private let eventMonitorDriver: EventMonitorDriver
    #if DEBUG
    private(set) var activeShortcutUsesFnForTesting = false
    #endif

    init(
        preferencesStore: PreferencesStore,
        permissionsStore: PermissionsStore,
        modelCatalog: ModelCatalogStore,
        hud: LiveHUDState,
        registerSystemShortcuts: Bool = !AppState.isRunningUnitTests,
        eventMonitorDriver: EventMonitorDriver? = nil,
        isBusy: @escaping () -> Bool,
        setBusy: @escaping (Bool) -> Void,
        onTranscriptProduced: @escaping (String, String) -> Void,
        getResult: @escaping () -> String
    ) {
        self.preferencesStore = preferencesStore
        self.permissionsStore = permissionsStore
        self.modelCatalog = modelCatalog
        self.hud = hud
        self.registerSystemShortcuts = registerSystemShortcuts
        self.eventMonitorDriver = eventMonitorDriver ?? (registerSystemShortcuts ? .system : .noop)
        self.isBusy = isBusy
        self.setBusy = setBusy
        self.onTranscriptProduced = onTranscriptProduced
        self.getResult = getResult
    }

    deinit {
        if let fnGlobalMonitor { eventMonitorDriver.removeMonitor(fnGlobalMonitor) }
        if let fnLocalMonitor { eventMonitorDriver.removeMonitor(fnLocalMonitor) }
        if let escMonitor { eventMonitorDriver.removeMonitor(escMonitor) }
    }

    func setupKeyboardShortcuts() {
        guard registerSystemShortcuts else { return }
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.hotkeyDown()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
            self?.hotkeyUp()
        }
    }

    func configureShortcutMode() {
        fnGesture.reset()
        fnOtherModifiers = registerSystemShortcuts
            ? NSEvent.modifierFlags.intersection([.shift, .control, .option, .command])
            : []
        gesture.reset()
        fnStartedRecording = false
        clearFnMonitors()
        #if DEBUG
        activeShortcutUsesFnForTesting = preferencesStore.preferences.useFnKey
        #endif
        if preferencesStore.preferences.useFnKey {
            if registerSystemShortcuts {
                KeyboardShortcuts.disable(.toggleDictation)
            }
            let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
            fnGlobalMonitor = eventMonitorDriver.addGlobalMonitor(mask) { [weak self] event in
                let flags = event.modifierFlags, type = event.type
                Task { @MainActor in self?.handleFnEvent(flags: flags, type: type) }
            }
            fnLocalMonitor = eventMonitorDriver.addLocalMonitor(mask) { [weak self] event in
                let flags = event.modifierFlags, type = event.type
                Task { @MainActor in self?.handleFnEvent(flags: flags, type: type) }
                return event
            }
            DiagnosticLog.shared.record("shortcut.fn.monitor global=\(fnGlobalMonitor != nil) local=\(fnLocalMonitor != nil)")
        } else {
            if registerSystemShortcuts {
                KeyboardShortcuts.enable(.toggleDictation)
            }
        }
    }

    private func clearFnMonitors() {
        if let fnGlobalMonitor { eventMonitorDriver.removeMonitor(fnGlobalMonitor); self.fnGlobalMonitor = nil }
        if let fnLocalMonitor { eventMonitorDriver.removeMonitor(fnLocalMonitor); self.fnLocalMonitor = nil }
    }

    private func clearEscMonitor() {
        if let escMonitor { eventMonitorDriver.removeMonitor(escMonitor); self.escMonitor = nil }
    }

    private func handleFnEvent(flags: NSEvent.ModifierFlags, type: NSEvent.EventType) {
        guard preferencesStore.preferences.useFnKey else { return }
        let action: FnKeyGesture.Action
        if type == .flagsChanged {
            let fnDown = flags.contains(.function)
            let wasDown = fnGesture.isDown
            let otherModifiers = flags.intersection([.shift, .control, .option, .command])
            let otherModifiersChanged = otherModifiers != fnOtherModifiers
            fnOtherModifiers = otherModifiers
            action = fnGesture.flagsChanged(
                fnDown: fnDown,
                otherModifierChanged: otherModifiersChanged,
                otherModifiersHeld: !otherModifiers.isEmpty,
                holdToTalk: preferencesStore.preferences.holdToTalk ?? true
            )
            if fnDown != wasDown {
                DiagnosticLog.shared.record("shortcut.fn.transition down=\(fnDown) action=\(String(describing: action))")
            }
            if action == .cancel { DiagnosticLog.shared.record("shortcut.fn.chord cancelled=true") }
        } else if type == .keyDown {
            action = fnGesture.otherKeyPressed()
            if action == .cancel { DiagnosticLog.shared.record("shortcut.fn.chord cancelled=true") }
        } else {
            return
        }

        switch action {
        case .press:
            let wasRecording = hud.recording
            hotkeyDown()
            fnStartedRecording = !wasRecording && hud.recording
        case .release:
            hotkeyUp()
            fnStartedRecording = false
        case .cancel:
            if fnStartedRecording && hud.recording { cancel() } else { gesture.reset() }
            fnStartedRecording = false
        case .tap:
            hotkeyDown()
            hotkeyUp()
        case .none:
            break
        }
    }

    func hotkeyDown() {
        switch gesture.press(hold: preferencesStore.preferences.holdToTalk ?? true) {
        case .startHold: start(whileHeld: true)
        case .toggle: toggle()
        default: break
        }
    }

    func hotkeyUp() {
        if gesture.release(hold: preferencesStore.preferences.holdToTalk ?? true) == .stopHold && hud.recording {
            finish()
        }
    }

    func toggle() {
        if hud.recording { finish() } else { start(whileHeld: false) }
    }

    private func start(whileHeld: Bool) {
        guard !modelCatalog.testingRefinement else { return }
        if isBusy() && !hud.recording && transcriptionTask == nil {
            DiagnosticLog.shared.record("session.stale_busy_repaired")
            setBusy(false)
        }
        guard !isBusy() && !hud.recording else {
            DiagnosticLog.shared.record("session.start_ignored busy=\(isBusy()) recording=\(hud.recording)")
            if !hud.recording { gesture.reset() }
            return
        }
        diagnosticSession = UUID()
        let prefs = preferencesStore.preferences
        DiagnosticLog.shared.record("session.start id=\(diagnosticSession) speech_ready=\(modelCatalog.asrReady) editor_ready=\(modelCatalog.editorReady) mode=\(prefs.refinement.rawValue) auto_insert=\(prefs.autoInsert)")
        transcriptionGeneration = UUID()

        guard modelCatalog.asrReady else {
            DiagnosticLog.shared.record("session.stop id=\(diagnosticSession) reason=speech_model_not_ready")
            gesture.reset()
            hud.status = preferencesStore.t("Speech model is still loading, please wait…")
            overlay.showStatus(hud: hud, preferencesStore: preferencesStore)
            if !modelCatalog.isActivatingSpeechModel {
                modelCatalog.prepareSpeech()
            }
            return
        }
        if prefs.refinement.needsModel && !modelCatalog.editorReady {
            DiagnosticLog.shared.record("session.text_model_not_ready_background_prepare id=\(diagnosticSession)")
            if !modelCatalog.isActivatingTextModel {
                modelCatalog.prepareEditor()
            }
        }

        let target = TargetAccessibility.captureTargetFocus()
        let pid = target.pid
        let name = target.name
        let element = target.element
        DiagnosticLog.shared.record("session.target id=\(diagnosticSession) pid=\(pid) focus_present=\(element != nil)")

        permissionsStore.refreshPermissions()
        DiagnosticLog.shared.record("permissions id=\(diagnosticSession) microphone=\(permissionsStore.micAuthorized) accessibility=\(permissionsStore.axAuthorized)")
        guard permissionsStore.micAuthorized else {
            DiagnosticLog.shared.record("session.stop id=\(diagnosticSession) reason=microphone_permission")
            hud.status = preferencesStore.t("Microphone permission required.")
            permissionsStore.requestMicrophoneAccess()
            overlay.showStatus(hud: hud, preferencesStore: preferencesStore)
            return
        }

        guard !whileHeld || gesture.isDown else {
            DiagnosticLog.shared.record("session.stop id=\(diagnosticSession) reason=hotkey_released")
            hud.status = preferencesStore.t("Press and hold to dictate.")
            return
        }

        targetPID = pid
        targetAppName = name
        targetElement = element

        do {
            let microphoneName = try recorder.start(deviceUID: prefs.microphoneUID)
            DiagnosticLog.shared.record("recording.device id=\(diagnosticSession) name=\(microphoneName.debugDescription) selection=\(prefs.microphoneUID.isEmpty ? "default" : "selected")")
            hud.recording = true
            DiagnosticLog.shared.record("recording.started id=\(diagnosticSession)")
            if prefs.pauseMediaDuringRecording {
                mediaPlayback.pauseIfPlaying()
            }
            hud.status = preferencesStore.t("Listening…")
            startLiveStreaming()
            overlay.show(hud: hud, preferencesStore: preferencesStore, screenPoint: targetWindowCenter() ?? targetInsertionPoint() ?? NSEvent.mouseLocation)
            if prefs.sounds { NSSound(named: "Tink")?.play() }
            meter = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.hud.level = self?.recorder.currentLevel ?? 0 }
            }
            escMonitor = eventMonitorDriver.addGlobalMonitor(.keyDown) { [weak self] event in
                if event.keyCode == 53 { Task { @MainActor in self?.cancel() } }
            }
        } catch {
            DiagnosticLog.shared.record("recording.failed id=\(diagnosticSession) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code)")
            hud.status = error.localizedDescription
            overlay.showStatus(hud: hud, preferencesStore: preferencesStore)
        }
    }

    private func startLiveStreaming() {
        liveTask?.cancel()
        tracker.reset()
        tracker.onUpdate = { [weak self] state in
            self?.hud.liveTranscriptState = state
        }
        hud.liveTranscriptState.clear()
        hud.liveTranscript = ""
        let lang = preferencesStore.preferences.speechLanguage
        let logSession = diagnosticSession
        DiagnosticLog.shared.record("stream.started id=\(logSession)")
        liveTask = Task.detached(priority: .userInitiated) { [weak self] in
            var lastCount = 0
            var failureLogged = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard let self else { break }
                let isRec = await self.hud.recording
                guard isRec else { break }
                let samples = await self.recorder.currentSamples
                guard samples.count >= 5600, samples.count >= lastCount + 3200 else { continue }
                lastCount = samples.count
                do {
                    let text = try await self.modelCatalog.models.transcribe(samples: samples, language: lang, context: nil)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        await MainActor.run {
                            if self.hud.recording {
                                self.hud.liveTranscript = trimmed
                                self.hud.liveTranscriptState = self.tracker.update(rawText: trimmed)
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
        mediaPlayback.resumeIfPaused()
        let wasActiveSession = hud.recording || isBusy() || liveTask != nil || transcriptionTask != nil || activePasteboardSession != nil
        guard wasActiveSession else { return }
        DiagnosticLog.shared.record("session.cancel id=\(diagnosticSession)")
        liveTask?.cancel()
        liveTask = nil
        hud.liveTranscript = ""
        hud.liveTranscriptState.clear()
        tracker.reset()
        clearEscMonitor()
        transcriptionGeneration = UUID()
        gesture.reset()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if let session = activePasteboardSession {
            if !session.isPastePosted {
                _ = session.restore()
            }
            activePasteboardSession = nil
        }
        if hud.recording { _ = recorder.stop() }
        hud.recording = false
        setBusy(false)
        meter?.invalidate()
        hud.level = 0
        overlay.hide()
        if preferencesStore.preferences.sounds { NSSound(named: "Basso")?.play() }
        hud.status = preferencesStore.t("Cancelled")
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

            var posVal: CFTypeRef?
            var sizeVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
               let pos = posVal, let size = sizeVal,
               CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                var pt = CGPoint.zero
                var sz = CGSize.zero
                if AXValueGetValue(pos as! AXValue, .cgPoint, &pt),
                   AXValueGetValue(size as! AXValue, .cgSize, &sz), sz.width > 20 && sz.height > 10 {
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

        return NSEvent.mouseLocation
    }

    private func finish() {
        mediaPlayback.resumeIfPaused()
        liveTask?.cancel()
        liveTask = nil
        clearEscMonitor()
        let capture = recorder.stop()
        hud.recording = false
        meter?.invalidate()
        hud.level = 0
        setBusy(true)
        let audio = capture.samples
        let logSession = diagnosticSession
        DiagnosticLog.shared.record("recording.finished id=\(logSession) sample_count=\(audio.count)")
        let stats = capture.diagnostics
        DiagnosticLog.shared.record("recording.capture id=\(logSession) callbacks=\(stats.callbacks) input_frames=\(stats.inputFrames) output_frames=\(stats.outputFrames) allocation_failures=\(stats.allocationFailures) conversion_failures=\(stats.conversionFailures) empty_outputs=\(stats.emptyOutputBuffers) last_conversion_error=\(stats.lastConversionErrorCode.map(String.init) ?? "none")")
        if preferencesStore.preferences.sounds { NSSound(named: "Pop")?.play() }
        guard !audio.isEmpty else {
            setBusy(false)
            hud.liveTranscriptState.clear()
            hud.status = preferencesStore.t("No audio was captured. Check your microphone and try again.")
            DiagnosticLog.shared.record("recording.empty id=\(logSession)")
            overlay.showStatus(hud: hud, preferencesStore: preferencesStore)
            return
        }
        hud.status = preferencesStore.t("Transcribing…")
        overlay.show(hud: hud, preferencesStore: preferencesStore)
        let id = UUID()
        transcriptionGeneration = id
        let boundPID = targetPID
        let boundAppName = targetAppName
        let boundElement = targetElement
        let settings = preferencesStore.preferences
        let pipeline = Pipeline(detector: modelCatalog.models, transcription: modelCatalog.models, refinement: modelCatalog.models) { event in
            DiagnosticLog.shared.record("pipeline.\(event.rawValue) id=\(logSession)")
        }
        transcriptionTask = Task {
            defer {
                if self.transcriptionGeneration == id {
                    self.transcriptionTask = nil
                    self.setBusy(false)
                }
            }
            do {
                let output = try await pipeline.run(
                    samples: audio,
                    language: settings.speechLanguage,
                    mode: settings.refinement,
                    context: DeveloperASRContext.context(enabled: settings.developerContextEnabled)
                )
                guard transcriptionGeneration == id else {
                    DiagnosticLog.shared.record("transcription.discarded id=\(logSession) reason=session_changed")
                    return
                }
                DiagnosticLog.shared.record("transcription.completed id=\(logSession) original_chars=\(output.original.count) refined_chars=\(output.result.count) mode=\(settings.refinement.rawValue)")
                modelCatalog.clearRefinementTestFeedback()
                onTranscriptProduced(output.original, output.result)
                setBusy(false)
                if settings.autoInsert {
                    let targetPt = targetInsertionPoint()
                    overlay.flyAndDismiss(to: targetPt) { [weak self] in
                        guard let self else { return }
                        guard self.transcriptionGeneration == id, !self.hud.recording else { return }
                        self.hud.liveTranscriptState.clear()
                        if self.insertIfSafe(output.result, targetPID: boundPID, targetAppName: boundAppName, targetElement: boundElement, sessionID: id) {
                            self.hud.status = self.preferencesStore.t("Preparing to paste…")
                        } else {
                            let tip = !self.insertFailure.isEmpty ? self.insertFailure : self.preferencesStore.t("Paste failed. Open Result to review the text.")
                            self.hud.status = tip
                            self.overlay.showStatus(hud: self.hud, preferencesStore: self.preferencesStore)
                        }
                    }
                } else {
                    DiagnosticLog.shared.record("result.copy_only id=\(logSession)")
                    guard transcriptionGeneration == id, !hud.recording else { return }
                    overlay.hide()
                    hud.liveTranscriptState.clear()
                    copyResult()
                    hud.status = preferencesStore.t("Content copied to clipboard. Press ⌘V to paste.")
                    overlay.showStatus(hud: hud, preferencesStore: preferencesStore)
                }
            } catch {
                let errDesc = error.localizedDescription
                DiagnosticLog.shared.record("transcription.failed id=\(logSession) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code) error=\(errDesc)")
                guard transcriptionGeneration == id else { return }
                if !hud.recording {
                    hud.liveTranscriptState.clear()
                }
                setBusy(false)
                if let failure = error as? RefinementFailure {
                    modelCatalog.clearRefinementTestFeedback()
                    onTranscriptProduced(failure.original, failure.original)
                    let sample = failure.original.replacingOccurrences(of: "\n", with: " ").prefix(60)
                    DiagnosticLog.shared.record("refinement.failed id=\(logSession) reason=\(failure.reason) original_sample=\"\(sample)\"")
                    if settings.autoInsert {
                        let targetPt = targetInsertionPoint()
                        overlay.flyAndDismiss(to: targetPt) { [weak self] in
                            guard let self else { return }
                            guard self.transcriptionGeneration == id, !self.hud.recording else { return }
                            self.hud.liveTranscriptState.clear()
                            if self.insertIfSafe(failure.original, targetPID: boundPID, targetAppName: boundAppName, targetElement: boundElement, sessionID: id) {
                                self.hud.status = self.preferencesStore.t("Refinement unavailable; inserted original text.")
                            } else {
                                let tip = !self.insertFailure.isEmpty ? self.insertFailure : self.preferencesStore.t("Paste failed. Open Result to review the text.")
                                self.hud.status = tip
                                self.overlay.showStatus(hud: self.hud, preferencesStore: self.preferencesStore)
                            }
                        }
                    } else {
                        if !TargetAccessibility.isSensitiveDestination(element: boundElement) {
                            copyResult()
                            hud.status = preferencesStore.t("Refinement unavailable; original text copied to clipboard.")
                        } else {
                            hud.status = preferencesStore.t("Refinement unavailable. Open Result to review the original text.")
                        }
                        if !hud.recording { overlay.showStatus(hud: hud, preferencesStore: preferencesStore) }
                    }
                    return
                }
                if let voiceError = error as? VoiceBuddyError, voiceError == .noSpeech {
                    hud.status = preferencesStore.t("No speech detected. Please try again.")
                } else {
                    hud.status = error.localizedDescription
                }
                if !hud.recording { overlay.showStatus(hud: hud, preferencesStore: preferencesStore) }
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
        let fallbackChangeCount = NSPasteboard.general.changeCount
        let effPID = targetPID ?? self.targetPID
        let initialElement = targetElement ?? self.targetElement
        let logSession = diagnosticSession
        DiagnosticLog.shared.record("insert.begin id=\(logSession) target_pid=\(effPID) initial_focus=\(initialElement != nil) trusted=\(AXIsProcessTrusted())")

        insertFailure = ""
        permissionsStore.refreshPermissions()
        guard !text.isEmpty else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=empty_text")
            insertFailure = preferencesStore.t("No text to insert.")
            return false
        }
        let currentFocus = TargetAccessibility.captureTargetFocus()
        let currentElem: AXUIElement? = (effPID != 0 ? focusedElement(pid: effPID) : nil) ?? (currentFocus.pid == effPID ? currentFocus.element : nil)
        let focusMatches = initialElement.flatMap { initial in currentElem.map { CFEqual(initial, $0) } } ?? false
        DiagnosticLog.shared.record("insert.focus id=\(logSession) current_pid=\(currentFocus.pid) current_present=\(currentElem != nil) matches_initial=\(focusMatches)")

        let sensitiveTarget = TargetAccessibility.isSensitiveDestination(element: currentElem) || TargetAccessibility.isSensitiveDestination(element: initialElement)
        let myPID = NSRunningApplication.current.processIdentifier
        if effPID == 0 || effPID == myPID {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=no_external_target")
            insertFailure = preferencesStore.t("No external target; open Result to review the text.")
            return false
        }
        guard let targetApp = NSRunningApplication(processIdentifier: effPID), !targetApp.isTerminated else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=target_not_running")
            insertFailure = preferencesStore.t("Target app not running; open Result to review the text.")
            return false
        }
        let currentFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let currentFrontPID, currentFrontPID != effPID && currentFrontPID != myPID {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=frontmost_changed front_pid=\(currentFrontPID)")
            insertFailure = preferencesStore.t("Target application changed; open Result to review the text.")
            if TemporaryPasteboard.copyForManualPaste(text, expectedChangeCount: fallbackChangeCount, sensitive: sensitiveTarget || TargetAccessibility.isSensitiveDestination(element: currentFocus.element)) {
                insertFailure = preferencesStore.t("Focus changed; text copied. Press ⌘V to paste manually.")
            }
            return false
        }
        guard let initial = initialElement, let current = currentElem, CFEqual(initial, current) else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=focus_unverified")
            insertFailure = preferencesStore.t("Cannot verify the focused input; open Result to review the text.")
            if TemporaryPasteboard.copyForManualPaste(text, expectedChangeCount: fallbackChangeCount, sensitive: sensitiveTarget || TargetAccessibility.isSensitiveDestination(element: currentFocus.element)) {
                insertFailure = preferencesStore.t("Focus changed; text copied. Press ⌘V to paste manually.")
            }
            return false
        }
        guard AXIsProcessTrusted() else {
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=accessibility_permission")
            insertFailure = preferencesStore.t("Accessibility access needed; open Result to review the text.")
            return false
        }
        if #available(macOS 14.0, *) {
            targetApp.activate()
        } else {
            targetApp.activate(options: [.activateIgnoringOtherApps])
        }

        let temporaryClipboard = TemporaryPasteboard(board: .general, predecessor: self.activePasteboardSession)
        self.activePasteboardSession = temporaryClipboard
        guard temporaryClipboard.write(text, sensitive: sensitiveTarget) else {
            _ = temporaryClipboard.restore()
            if self.activePasteboardSession === temporaryClipboard { self.activePasteboardSession = nil }
            DiagnosticLog.shared.record("insert.rejected id=\(logSession) reason=clipboard_write_failed")
            insertFailure = preferencesStore.t("Failed to write to clipboard. Open Result to review the text.")
            return false
        }
        DiagnosticLog.shared.record("insert.queued id=\(logSession)")

        TargetAccessibility.waitForModifiersReleased(timeout: 0.25) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard let self, !self.hud.recording else {
                    _ = temporaryClipboard.restore()
                    if self?.activePasteboardSession === temporaryClipboard { self?.activePasteboardSession = nil }
                    DiagnosticLog.shared.record("insert.cancelled id=\(logSession) reason=recording_or_shutdown")
                    return
                }
                if let sid = sessionID, self.transcriptionGeneration != sid {
                    _ = temporaryClipboard.restore()
                    if self.activePasteboardSession === temporaryClipboard { self.activePasteboardSession = nil }
                    DiagnosticLog.shared.record("insert.cancelled id=\(logSession) reason=session_changed")
                    return
                }
                guard temporaryClipboard.owns(text) else {
                    temporaryClipboard.invalidate()
                    if self.activePasteboardSession === temporaryClipboard { self.activePasteboardSession = nil }
                    DiagnosticLog.shared.record("insert.cancelled id=\(logSession) reason=clipboard_changed")
                    self.hud.status = self.preferencesStore.t("Clipboard changed; paste was cancelled.")
                    self.overlay.showStatus(hud: self.hud, preferencesStore: self.preferencesStore)
                    return
                }
                let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                let liveFocus = self.focusedElement(pid: effPID)
                let focusMatches = liveFocus.map { CFEqual(initial, $0) } ?? false
                let sensitive = TargetAccessibility.isSensitiveDestination(element: liveFocus)
                DiagnosticLog.shared.record("insert.final_check id=\(logSession) front_pid=\(frontPID) focus_present=\(liveFocus != nil) focus_matches=\(focusMatches) sensitive=\(sensitive)")
                guard frontPID == effPID, focusMatches, (!sensitive || sensitiveTarget) else {
                    let copied = temporaryClipboard.retainForManualPaste(text, sensitive: sensitiveTarget || sensitive)
                    if !copied { _ = temporaryClipboard.restore() }
                    if self.activePasteboardSession === temporaryClipboard { self.activePasteboardSession = nil }
                    DiagnosticLog.shared.record("insert.cancelled id=\(logSession) reason=final_focus_unverified manual_copy=\(copied)")
                    self.hud.status = copied
                        ? self.preferencesStore.t("Focus changed; text copied. Press ⌘V to paste manually.")
                        : self.preferencesStore.t("Could not verify the target. Open Result to review the text.")
                    self.overlay.showStatus(hud: self.hud, preferencesStore: self.preferencesStore)
                    return
                }
                temporaryClipboard.markPastePosted()
                TargetAccessibility.postPasteShortcutAsync { [weak self] success in
                    guard let self else {
                        _ = temporaryClipboard.restore()
                        return
                    }
                    if let sid = sessionID {
                        guard self.transcriptionGeneration == sid, !self.hud.recording else {
                            _ = temporaryClipboard.restore()
                            if self.activePasteboardSession === temporaryClipboard { self.activePasteboardSession = nil }
                            return
                        }
                    } else {
                        guard !self.hud.recording else {
                            _ = temporaryClipboard.restore()
                            if self.activePasteboardSession === temporaryClipboard { self.activePasteboardSession = nil }
                            return
                        }
                    }
                    guard success else {
                        _ = temporaryClipboard.restore()
                        if self.activePasteboardSession === temporaryClipboard { self.activePasteboardSession = nil }
                        DiagnosticLog.shared.record("insert.failed id=\(logSession) reason=event_creation")
                        self.hud.status = self.preferencesStore.t("Paste could not be sent. Open Result to review the text.")
                        self.overlay.showStatus(hud: self.hud, preferencesStore: self.preferencesStore)
                        return
                    }
                    self.hud.status = self.preferencesStore.t("Paste command sent.")
                    DiagnosticLog.shared.record("insert.paste_posted id=\(logSession)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                        let restored = temporaryClipboard.restore()
                        if self?.activePasteboardSession === temporaryClipboard { self?.activePasteboardSession = nil }
                        DiagnosticLog.shared.record("clipboard.restore id=\(logSession) restored=\(restored)")
                    }
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
        let success = NSPasteboard.general.setString(getResult(), forType: .string)
        DiagnosticLog.shared.record("clipboard.copy id=\(diagnosticSession) success=\(success)")
        hud.status = success ? preferencesStore.t("Copied") : preferencesStore.t("Copy failed")
    }

    #if DEBUG
    func setActivePasteboardSessionForTesting(_ session: TemporaryPasteboard?) {
        self.activePasteboardSession = session
    }

    func getActivePasteboardSessionForTesting() -> TemporaryPasteboard? {
        self.activePasteboardSession
    }

    var isFnMonitorActiveForTesting: Bool {
        fnGlobalMonitor != nil && fnLocalMonitor != nil
    }
    #endif
}
