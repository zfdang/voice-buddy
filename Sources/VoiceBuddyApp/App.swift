import AppKit
import AVFoundation
import Foundation
import SwiftUI
import VoiceBuddyCore

/// Thin top-level coordinator wiring focused `@Observable` stores and session controllers.
/// Views observe individual stores (`hud`, `preferencesStore`, `permissionsStore`, `modelCatalog`)
/// so high-frequency streaming updates do not trigger global settings redraws.
@MainActor
final class AppState: ObservableObject {
    let hud = LiveHUDState()
    let preferencesStore: PreferencesStore
    let permissionsStore = PermissionsStore()
    private(set) var modelCatalog: ModelCatalogStore!
    private(set) var dictation: DictationSessionCoordinator!
    let updater = UpdaterViewModel()

    @Published var selectedTab: AppTab = .general
    @Published var result = ""
    @Published var original = ""
    @Published var busy = false

    private var menuBarController: MenuBarController?

    nonisolated static let isRunningUnitTests: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    init(
        skipModelPreload: Bool = AppState.isRunningUnitTests,
        skipMenuBar: Bool = AppState.isRunningUnitTests,
        defaults: UserDefaults = .standard,
        defaultsKey: String = "VoiceBuddy.preferences",
        models: LocalModels = LocalModels()
    ) {
        let prefsStore = PreferencesStore(defaults: defaults, defaultsKey: defaultsKey)
        self.preferencesStore = prefsStore

        self.modelCatalog = ModelCatalogStore(
            models: models,
            preferencesStore: prefsStore,
            hud: hud,
            isBusy: { [weak self] in self?.busy ?? false },
            setBusy: { [weak self] value in self?.busy = value },
            getOriginal: { [weak self] in self?.original ?? "" },
            setResult: { [weak self] value in self?.result = value }
        )

        self.dictation = DictationSessionCoordinator(
            preferencesStore: prefsStore,
            permissionsStore: permissionsStore,
            modelCatalog: modelCatalog,
            hud: hud,
            isBusy: { [weak self] in self?.busy ?? false },
            setBusy: { [weak self] value in self?.busy = value },
            onTranscriptProduced: { [weak self] originalText, resultText in
                self?.original = originalText
                self?.result = resultText
            },
            getResult: { [weak self] in self?.result ?? "" }
        )

        prefsStore.onPreferencesChanged = { [weak self] oldValue, newValue in
            guard let self else { return }
            if oldValue.useFnKey != newValue.useFnKey {
                self.dictation.configureShortcutMode()
            }
            if oldValue.refinement != newValue.refinement {
                self.modelCatalog.handleRefinementChanged(from: oldValue.refinement, to: newValue.refinement)
            }
        }

        DiagnosticLog.shared.record("app.start version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        permissionsStore.refreshPermissions()
        dictation.setupKeyboardShortcuts()
        dictation.configureShortcutMode()
        if !skipModelPreload {
            modelCatalog.autoPreloadModels()
        }
        menuBarController = skipMenuBar ? nil : MenuBarController(appState: self)
        hud.onRecordingChanged = { [weak self] isRecording in
            self?.menuBarController?.updateIcon(isRecording: isRecording)
        }
    }

    // MARK: - Store Forwarding & Compatibility API

    var preferences: Preferences {
        get { preferencesStore.preferences }
        set { preferencesStore.preferences = newValue }
    }

    var recording: Bool {
        get { hud.recording }
        set {
            hud.recording = newValue
            menuBarController?.updateIcon(isRecording: newValue)
        }
    }

    var status: String {
        get { hud.status }
        set { hud.status = newValue }
    }

    var level: Float {
        get { hud.level }
        set { hud.level = newValue }
    }

    var liveTranscript: String {
        get { hud.liveTranscript }
        set { hud.liveTranscript = newValue }
    }

    var liveTranscriptState: LiveTranscriptState {
        get { hud.liveTranscriptState }
        set { hud.liveTranscriptState = newValue }
    }

    var models: LocalModels { modelCatalog.models }
    var asrReady: Bool {
        get { modelCatalog.asrReady }
        set { modelCatalog.asrReady = newValue }
    }
    var ready: Bool {
        get { modelCatalog.asrReady }
        set { modelCatalog.asrReady = newValue }
    }
    var editorReady: Bool {
        get { modelCatalog.editorReady }
        set { modelCatalog.editorReady = newValue }
    }
    var isSpeechDownloaded: Bool { modelCatalog.isSpeechDownloaded }
    var isEditorDownloaded: Bool { modelCatalog.isEditorDownloaded }
    var cachedSpeechModelIDs: Set<String> {
        get { modelCatalog.cachedSpeechModelIDs }
        set { modelCatalog.cachedSpeechModelIDs = newValue }
    }
    var downloadingSpeechModelIDs: Set<String> {
        get { modelCatalog.downloadingSpeechModelIDs }
        set { modelCatalog.downloadingSpeechModelIDs = newValue }
    }
    var speechDownloadProgress: [String: Double] {
        get { modelCatalog.speechDownloadProgress }
        set { modelCatalog.speechDownloadProgress = newValue }
    }
    var isActivatingSpeechModel: Bool {
        get { modelCatalog.isActivatingSpeechModel }
        set { modelCatalog.isActivatingSpeechModel = newValue }
    }
    var cachedTextModelIDs: Set<String> {
        get { modelCatalog.cachedTextModelIDs }
        set { modelCatalog.cachedTextModelIDs = newValue }
    }
    var downloadingTextModelIDs: Set<String> {
        get { modelCatalog.downloadingTextModelIDs }
        set { modelCatalog.downloadingTextModelIDs = newValue }
    }
    var textDownloadProgress: [String: Double] {
        get { modelCatalog.textDownloadProgress }
        set { modelCatalog.textDownloadProgress = newValue }
    }
    var activeDownloadingSpeechModelID: String? {
        get { modelCatalog.activeDownloadingSpeechModelID }
        set { modelCatalog.activeDownloadingSpeechModelID = newValue }
    }
    var speechPreparing: Bool {
        get { modelCatalog.speechPreparing }
        set { modelCatalog.speechPreparing = newValue }
    }
    var activeDownloadingTextModelID: String? {
        get { modelCatalog.activeDownloadingTextModelID }
        set { modelCatalog.activeDownloadingTextModelID = newValue }
    }
    var modelPreparing: Bool {
        get { modelCatalog.modelPreparing }
        set { modelCatalog.modelPreparing = newValue }
    }
    var isActivatingTextModel: Bool {
        get { modelCatalog.isActivatingTextModel }
        set { modelCatalog.isActivatingTextModel = newValue }
    }
    var editorPreparing: Bool {
        get { modelCatalog.editorPreparing }
        set { modelCatalog.editorPreparing = newValue }
    }
    var testingRefinement: Bool { modelCatalog.testingRefinement }
    var refinementTestStatus: String { modelCatalog.refinementTestStatus }
    var refinementTestSummary: String { modelCatalog.refinementTestSummary }

    var micAuthorized: Bool { permissionsStore.micAuthorized }
    var axAuthorized: Bool { permissionsStore.axAuthorized }
    var micStatus: AVAuthorizationStatus { permissionsStore.micStatus }
    var waitingForSystemSettingsReturn: Bool {
        get { permissionsStore.waitingForSystemSettingsReturn }
        set { permissionsStore.waitingForSystemSettingsReturn = newValue }
    }

    var insertFailure: String { dictation.insertFailure }

    // MARK: - Localization Helpers

    func t(_ key: String) -> String { preferencesStore.t(key) }
    func label(_ en: String, _ zh: String) -> String { preferencesStore.label(en, zh) }

    // MARK: - Actions

    func checkForUpdates() { updater.checkForUpdates() }
    func checkModelCacheStatus(completion: (@MainActor @Sendable () -> Void)? = nil) {
        modelCatalog.checkModelCacheStatus(completion: completion)
    }
    func refreshPermissions() { permissionsStore.refreshPermissions() }
    func requestMicrophoneAccess() { permissionsStore.requestMicrophoneAccess() }
    func requestAccessibilityAccess() { permissionsStore.requestAccessibilityAccess() }
    func openSystemSettings(for permission: String) { permissionsStore.openSystemSettings(for: permission) }
    func bringMainWindowToFront() { VoiceBuddyAppDelegate.shared?.showSettingsWindow() }
    func setupMenuBar() { menuBarController?.setupStatusItem() }

    func loadActiveSpeechModel() { modelCatalog.loadActiveSpeechModel() }
    func selectSpeechModel(id: String) { modelCatalog.selectSpeechModel(id: id) }
    func downloadSpeechModel(id: String) { modelCatalog.downloadSpeechModel(id: id) }
    func cancelSpeechDownload(id: String) { modelCatalog.cancelSpeechDownload(id: id) }
    func prepareSpeech(id: String? = nil, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        modelCatalog.prepareSpeech(id: id, completion: completion)
    }
    func removeSpeechModel(id: String? = nil) { modelCatalog.removeSpeechModel(id: id) }

    func testRefinement(mode: Refinement) async { await modelCatalog.testRefinement(mode: mode) }
    func loadActiveEditorModel(force: Bool = false) { modelCatalog.loadActiveEditorModel(force: force) }
    func unloadEditor() { modelCatalog.unloadEditor() }
    func selectTextModel(id: String) { modelCatalog.selectTextModel(id: id) }
    func downloadTextModel(id: String) { modelCatalog.downloadTextModel(id: id) }
    func cancelTextDownload(id: String) { modelCatalog.cancelTextDownload(id: id) }
    func prepareEditor(id: String? = nil, force: Bool = false, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        modelCatalog.prepareEditor(id: id, force: force, completion: completion)
    }
    func removeTextModel(id: String? = nil) { modelCatalog.removeTextModel(id: id) }

    func hotkeyDown() { dictation.hotkeyDown() }
    func hotkeyUp() { dictation.hotkeyUp() }
    func toggle() { dictation.toggle() }
    func cancel() { dictation.cancel() }

    func insertIfSafe(
        _ text: String,
        targetPID: pid_t? = nil,
        targetAppName: String? = nil,
        targetElement: AXUIElement? = nil,
        sessionID: UUID? = nil
    ) -> Bool {
        dictation.insertIfSafe(
            text,
            targetPID: targetPID,
            targetAppName: targetAppName,
            targetElement: targetElement,
            sessionID: sessionID
        )
    }

    func copyResult() { dictation.copyResult() }

    func showWindow(tab: AppTab? = nil, targetScreen: NSScreen? = nil) {
        VoiceBuddyAppDelegate.shared?.showSettingsWindow(tab: tab, targetScreen: targetScreen)
    }

    @MainActor
    static func closeKeyWindow() {
        VoiceBuddyAppDelegate.shared?.closeKeyWindow()
    }

    static var menuBarMascotIcon: NSImage { AppMascotIcons.menuBarMascotIcon }
    static var menuBarActiveIcon: NSImage { AppMascotIcons.menuBarActiveIcon }
    static var appMascotColorIcon: NSImage { AppMascotIcons.appMascotColorIcon }

    #if DEBUG
    func setActivePasteboardSessionForTesting(_ session: TemporaryPasteboard?) {
        dictation.setActivePasteboardSessionForTesting(session)
    }
    func getActivePasteboardSessionForTesting() -> TemporaryPasteboard? {
        dictation.getActivePasteboardSessionForTesting()
    }
    var hasMenuBarControllerForTesting: Bool {
        menuBarController != nil
    }
    #endif
}
