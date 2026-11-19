import Foundation
import Observation
import VoiceBuddyCore

/// Owns local speech/text model cache tracking, downloads, activation, unloading, and refinement preview testing.
@MainActor
@Observable
final class ModelCatalogStore {
    let models: LocalModels

    var asrReady = false
    var editorReady = false
    var isSpeechDownloaded = false
    var isEditorDownloaded = false

    var cachedSpeechModelIDs: Set<String> = []
    var downloadingSpeechModelIDs: Set<String> = []
    var speechDownloadProgress: [String: Double] = [:]
    var speechDownloadMessages: [String: String] = [:]
    var activeDownloadingSpeechModelID: String? = nil
    var isActivatingSpeechModel = false

    var cachedTextModelIDs: Set<String> = []
    var downloadingTextModelIDs: Set<String> = []
    var textDownloadProgress: [String: Double] = [:]
    var textDownloadMessages: [String: String] = [:]
    var activeDownloadingTextModelID: String? = nil
    var isActivatingTextModel = false

    var speechPreparing = false
    var speechProgress: Double = 0
    var speechProgressMessage = ""
    var editorPreparing = false
    var editorProgress: Double = 0
    var editorProgressMessage = ""
    var modelProgress: Double = 0
    var modelPreparing = false

    private(set) var testingRefinement = false
    private(set) var refinementTestStatus = ""
    private(set) var refinementTestSummary = ""

    @ObservationIgnored private var speechDownloadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var textDownloadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    @ObservationIgnored private var speechGeneration = UUID()
    @ObservationIgnored private var editorTask: Task<Void, Never>?
    @ObservationIgnored private var editorGeneration = UUID()

    @ObservationIgnored private let preferencesStore: PreferencesStore
    @ObservationIgnored private let hud: LiveHUDState
    @ObservationIgnored private let isBusy: () -> Bool
    @ObservationIgnored private let setBusy: (Bool) -> Void
    @ObservationIgnored private let getOriginal: () -> String
    @ObservationIgnored private let setResult: (String) -> Void

    init(
        models: LocalModels = LocalModels(),
        preferencesStore: PreferencesStore,
        hud: LiveHUDState,
        isBusy: @escaping () -> Bool,
        setBusy: @escaping (Bool) -> Void,
        getOriginal: @escaping () -> String,
        setResult: @escaping (String) -> Void
    ) {
        self.models = models
        self.preferencesStore = preferencesStore
        self.hud = hud
        self.isBusy = isBusy
        self.setBusy = setBusy
        self.getOriginal = getOriginal
        self.setResult = setResult
    }

    func clearRefinementTestFeedback() {
        refinementTestSummary = ""
        refinementTestStatus = ""
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
                self.isSpeechDownloaded = self.cachedSpeechModelIDs.contains(self.preferencesStore.preferences.speechModel)
                self.isEditorDownloaded = self.cachedTextModelIDs.contains(self.preferencesStore.preferences.textModel)
                completion?()
            }
        }
    }

    func autoPreloadModels() {
        checkModelCacheStatus { [weak self] in
            guard let self else { return }
            if self.isSpeechDownloaded && !self.asrReady && !self.speechPreparing {
                self.loadActiveSpeechModel()
            }
            if self.preferencesStore.preferences.refinement.needsModel && self.isEditorDownloaded && !self.editorReady && !self.editorPreparing {
                self.loadActiveEditorModel()
            }
        }
    }

    func loadActiveSpeechModel() {
        prepareSpeech(id: preferencesStore.preferences.speechModel)
    }

    func selectSpeechModel(id: String) {
        guard preferencesStore.preferences.speechModel != id else { return }
        preferencesStore.preferences.speechModel = id
        asrReady = false
        if cachedSpeechModelIDs.contains(id) {
            prepareSpeech(id: id)
        }
    }

    func downloadSpeechModel(id: String) {
        guard !downloadingSpeechModelIDs.contains(id), !hud.recording else { return }
        if id == "apple-speech" {
            checkModelCacheStatus()
            return
        }

        downloadingSpeechModelIDs.insert(id)
        speechDownloadProgress[id] = 0
        speechDownloadMessages[id] = preferencesStore.t("Starting download…")
        activeDownloadingSpeechModelID = id

        let isSelectedModel = (id == preferencesStore.preferences.speechModel)
        if isSelectedModel {
            modelPreparing = true
            modelProgress = 0
            hud.status = preferencesStore.t("Downloading speech model…")
        }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.models.downloadSpeech(id: id) { [weak self] progress, message in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloadingSpeechModelIDs.contains(id) else { return }
                        self.speechDownloadProgress[id] = progress
                        self.speechDownloadMessages[id] = message
                        if self.preferencesStore.preferences.speechModel == id {
                            self.modelProgress = progress
                            self.hud.status = message
                        }
                    }
                }
                await MainActor.run {
                    self.speechDownloadTasks.removeValue(forKey: id)
                    self.downloadingSpeechModelIDs.remove(id)
                    self.speechDownloadProgress.removeValue(forKey: id)
                    self.speechDownloadMessages.removeValue(forKey: id)
                    if self.activeDownloadingSpeechModelID == id {
                        self.activeDownloadingSpeechModelID = self.downloadingSpeechModelIDs.first
                    }
                    self.checkModelCacheStatus()

                    if self.preferencesStore.preferences.speechModel == id || !self.cachedSpeechModelIDs.contains(self.preferencesStore.preferences.speechModel) {
                        self.preferencesStore.preferences.speechModel = id
                        self.prepareSpeech(id: id)
                    }
                }
            } catch {
                await MainActor.run {
                    self.speechDownloadTasks.removeValue(forKey: id)
                    self.downloadingSpeechModelIDs.remove(id)
                    self.speechDownloadProgress.removeValue(forKey: id)
                    self.speechDownloadMessages.removeValue(forKey: id)
                    if self.activeDownloadingSpeechModelID == id {
                        self.activeDownloadingSpeechModelID = self.downloadingSpeechModelIDs.first
                    }
                    if self.preferencesStore.preferences.speechModel == id {
                        self.modelPreparing = false
                        self.hud.status = self.preferencesStore.t("Download failed")
                    }
                }
            }
        }
        speechDownloadTasks[id] = task
    }

    func cancelSpeechDownload(id: String) {
        if let task = speechDownloadTasks.removeValue(forKey: id) {
            task.cancel()
        }
        downloadingSpeechModelIDs.remove(id)
        speechDownloadProgress.removeValue(forKey: id)
        speechDownloadMessages.removeValue(forKey: id)
        if activeDownloadingSpeechModelID == id {
            speechGeneration = UUID()
            speechTask?.cancel()
            speechTask = nil
            activeDownloadingSpeechModelID = downloadingSpeechModelIDs.first
            if downloadingSpeechModelIDs.isEmpty {
                isActivatingSpeechModel = false
                speechPreparing = false
            }
        }
        if preferencesStore.preferences.speechModel == id && !asrReady {
            speechGeneration = UUID()
            speechTask?.cancel()
            speechTask = nil
            isActivatingSpeechModel = false
            speechPreparing = false
            modelPreparing = false
            modelProgress = 0
            hud.status = preferencesStore.t("Ready")
        }
    }

    func prepareSpeech(id: String? = nil, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        guard !isActivatingSpeechModel && !hud.recording else { completion?(false); return }
        isActivatingSpeechModel = true
        speechPreparing = true
        let targetId = id ?? preferencesStore.preferences.speechModel
        let isSelectedModel = (targetId == preferencesStore.preferences.speechModel)
        let loadMsg = preferencesStore.t("Loading speech model into memory…")
        if isSelectedModel {
            modelPreparing = true
            modelProgress = 0
            hud.status = loadMsg
        }
        speechProgress = 0
        speechProgressMessage = loadMsg
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
                        self.isActivatingSpeechModel = false
                        self.speechPreparing = false
                        if isSelectedModel {
                            self.modelPreparing = false
                        }
                        completion?(false)
                    }
                    return
                }
                await MainActor.run {
                    self.cachedSpeechModelIDs.insert(targetId)
                    if isSelectedModel {
                        self.asrReady = true
                    }
                    self.isSpeechDownloaded = self.cachedSpeechModelIDs.contains(self.preferencesStore.preferences.speechModel)
                    self.isActivatingSpeechModel = false
                    self.speechPreparing = false
                    if isSelectedModel {
                        self.modelPreparing = false
                        self.hud.status = self.preferencesStore.t("Speech model ready")
                    }
                    completion?(true)
                }
            } catch {
                DiagnosticLog.shared.record("model.speech.failed id=\(operation) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code)")
                guard speechGeneration == operation else {
                    await MainActor.run {
                        self.isActivatingSpeechModel = false
                        self.speechPreparing = false
                        if isSelectedModel {
                            self.modelPreparing = false
                        }
                        completion?(false)
                    }
                    return
                }
                await MainActor.run {
                    if isSelectedModel {
                        self.hud.status = error.localizedDescription
                    }
                    self.speechProgressMessage = error.localizedDescription
                    self.isActivatingSpeechModel = false
                    self.speechPreparing = false
                    if isSelectedModel {
                        self.modelPreparing = false
                    }
                    completion?(false)
                }
            }
        }
    }

    func testRefinement(mode: Refinement) async {
        guard !testingRefinement, !hud.recording, !isBusy() else { return }
        let source = getOriginal()
        let modelID = preferencesStore.preferences.textModel
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        testingRefinement = true
        refinementTestStatus = preferencesStore.t("Testing…")
        defer { testingRefinement = false }
        let started = Date()
        var loadDuration: TimeInterval = 0
        var refineDuration: TimeInterval = 0
        do {
            let output: String
            if mode == .original {
                output = source
            } else if mode == .light {
                output = TextCleanup.light(source)
            } else {
                let tester = LocalModels()
                defer { Task { await tester.unloadEditor() } }
                guard await tester.isEditorModelCached(id: modelID) else {
                    refinementTestStatus = preferencesStore.t("Download this model in Text Models first.")
                    return
                }
                refinementTestStatus = preferencesStore.t("Loading model and testing…")
                try await tester.prepareEditor(id: modelID) { _, _ in }
                loadDuration = Date().timeIntervalSince(started)
                try Task.checkCancellation()
                let refineStarted = Date()
                output = try await tester.refine(source, mode: mode)
                refineDuration = Date().timeIntervalSince(refineStarted)
                if let reason = TextCleanup.unsafeReason(output, original: source) {
                    throw RefinementFailure(original: source, reason: reason)
                }
            }
            try Task.checkCancellation()
            guard getOriginal() == source else {
                refinementTestStatus = preferencesStore.t("Original text changed. Test again.")
                return
            }
            setResult(output)
            let names: [Refinement: String] = [
                .original: preferencesStore.t("Original"),
                .light: preferencesStore.t("Light"),
                .balanced: preferencesStore.t("Moderate"),
                .moderate: preferencesStore.t("Deep"),
                .rewrite: preferencesStore.t("Professional Rewrite")
            ]
            let model = TextModelSpec.allModels.first { $0.id == modelID }
            let modelName = mode.needsModel
                ? [model?.name, model?.quantization].compactMap { $0 }.joined(separator: " · ")
                : preferencesStore.t("No text model")
            let timing = mode.needsModel
                ? preferencesStore.t("Load") + " \(String(format: "%.1f", loadDuration))s · " + preferencesStore.t("Refine") + " \(String(format: "%.1f", refineDuration))s"
                : preferencesStore.t("Original text")
            refinementTestSummary = "\(names[mode] ?? mode.rawValue) · \(modelName) · \(timing)"
            refinementTestStatus = preferencesStore.t("Test complete")
        } catch is CancellationError {
            refinementTestStatus = preferencesStore.t("Test cancelled")
        } catch {
            refinementTestStatus = preferencesStore.t("Test failed: ") + error.localizedDescription
        }
    }

    func loadActiveEditorModel(force: Bool = false) {
        prepareEditor(id: preferencesStore.preferences.textModel, force: force)
    }

    func unloadEditor() {
        editorGeneration = UUID()
        editorTask?.cancel()
        editorTask = nil
        isActivatingTextModel = false
        editorPreparing = false
        editorReady = false
        let targetId = preferencesStore.preferences.textModel
        Task {
            await models.unloadEditor()
        }
        DiagnosticLog.shared.record("model.text.unloaded id=\(targetId)")
    }

    func handleRefinementChanged(from old: Refinement, to new: Refinement) {
        DiagnosticLog.shared.record("refinement.changed from=\(old.rawValue) to=\(new.rawValue)")
        if !new.needsModel {
            unloadEditor()
        } else if !editorReady && !isActivatingTextModel && cachedTextModelIDs.contains(preferencesStore.preferences.textModel) && !hud.recording {
            loadActiveEditorModel()
        }
    }

    func selectTextModel(id: String) {
        guard preferencesStore.preferences.textModel != id else { return }
        preferencesStore.preferences.textModel = id
        editorReady = false
        if cachedTextModelIDs.contains(id) && preferencesStore.preferences.refinement.needsModel {
            prepareEditor(id: id)
        } else {
            unloadEditor()
        }
    }

    func downloadTextModel(id: String) {
        guard !downloadingTextModelIDs.contains(id), !hud.recording else { return }

        downloadingTextModelIDs.insert(id)
        textDownloadProgress[id] = 0
        textDownloadMessages[id] = preferencesStore.t("Starting download…")
        activeDownloadingTextModelID = id

        let isSelectedModel = (id == preferencesStore.preferences.textModel)
        if isSelectedModel && preferencesStore.preferences.refinement.needsModel {
            modelPreparing = true
            modelProgress = 0
            hud.status = preferencesStore.t("Downloading text model…")
        }

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.models.downloadEditor(id: id) { [weak self] progress, message in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloadingTextModelIDs.contains(id) else { return }
                        self.textDownloadProgress[id] = progress
                        self.textDownloadMessages[id] = message
                        if self.preferencesStore.preferences.textModel == id && self.preferencesStore.preferences.refinement.needsModel {
                            self.modelProgress = progress
                            self.hud.status = message
                        }
                    }
                }
                await MainActor.run {
                    self.textDownloadTasks.removeValue(forKey: id)
                    self.downloadingTextModelIDs.remove(id)
                    self.textDownloadProgress.removeValue(forKey: id)
                    self.textDownloadMessages.removeValue(forKey: id)
                    if self.activeDownloadingTextModelID == id {
                        self.activeDownloadingTextModelID = self.downloadingTextModelIDs.first
                    }
                    self.checkModelCacheStatus()

                    if self.preferencesStore.preferences.refinement.needsModel && (self.preferencesStore.preferences.textModel == id || !self.cachedTextModelIDs.contains(self.preferencesStore.preferences.textModel)) {
                        self.preferencesStore.preferences.textModel = id
                        self.loadActiveEditorModel()
                    }
                }
            } catch {
                await MainActor.run {
                    self.textDownloadTasks.removeValue(forKey: id)
                    self.downloadingTextModelIDs.remove(id)
                    self.textDownloadProgress.removeValue(forKey: id)
                    self.textDownloadMessages.removeValue(forKey: id)
                    if self.activeDownloadingTextModelID == id {
                        self.activeDownloadingTextModelID = self.downloadingTextModelIDs.first
                    }
                    if self.preferencesStore.preferences.textModel == id {
                        self.modelPreparing = false
                        self.hud.status = self.preferencesStore.t("Download failed")
                    }
                }
            }
        }
        textDownloadTasks[id] = task
    }

    func cancelTextDownload(id: String) {
        if let task = textDownloadTasks.removeValue(forKey: id) {
            task.cancel()
        }
        downloadingTextModelIDs.remove(id)
        textDownloadProgress.removeValue(forKey: id)
        textDownloadMessages.removeValue(forKey: id)
        if activeDownloadingTextModelID == id {
            editorGeneration = UUID()
            editorTask?.cancel()
            editorTask = nil
            activeDownloadingTextModelID = downloadingTextModelIDs.first
            if downloadingTextModelIDs.isEmpty {
                isActivatingTextModel = false
                editorPreparing = false
            }
        }
        if preferencesStore.preferences.textModel == id && !editorReady {
            editorGeneration = UUID()
            editorTask?.cancel()
            editorTask = nil
            isActivatingTextModel = false
            editorPreparing = false
            modelPreparing = false
            modelProgress = 0
            hud.status = preferencesStore.t("Ready")
        }
    }

    func prepareEditor(id: String? = nil, force: Bool = false, completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        guard (preferencesStore.preferences.refinement.needsModel || force), !isActivatingTextModel && !hud.recording else {
            completion?(false)
            return
        }
        isActivatingTextModel = true
        editorPreparing = true
        let targetId = id ?? preferencesStore.preferences.textModel
        let isSelectedModel = (targetId == preferencesStore.preferences.textModel)
        let loadMsg = preferencesStore.t("Loading text model into memory…")
        if isSelectedModel {
            modelPreparing = true
            modelProgress = 0
            hud.status = loadMsg
        }
        editorProgress = 0
        editorProgressMessage = loadMsg
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
                        self.isActivatingTextModel = false
                        self.editorPreparing = false
                        if isSelectedModel {
                            self.modelPreparing = false
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
                    self.isEditorDownloaded = self.cachedTextModelIDs.contains(self.preferencesStore.preferences.textModel)
                    self.isActivatingTextModel = false
                    self.editorPreparing = false
                    if isSelectedModel {
                        self.modelPreparing = false
                        self.hud.status = self.preferencesStore.t("Text model ready")
                    }
                    completion?(true)
                }
            } catch {
                DiagnosticLog.shared.record("model.text.failed id=\(operation) error_type=\(String(describing: type(of: error))) code=\((error as NSError).code)")
                guard editorGeneration == operation else {
                    await MainActor.run {
                        self.isActivatingTextModel = false
                        self.editorPreparing = false
                        if isSelectedModel {
                            self.modelPreparing = false
                        }
                        completion?(false)
                    }
                    return
                }
                await MainActor.run {
                    if isSelectedModel {
                        self.hud.status = error.localizedDescription
                    }
                    self.editorProgressMessage = error.localizedDescription
                    self.isActivatingTextModel = false
                    self.editorPreparing = false
                    if isSelectedModel {
                        self.modelPreparing = false
                    }
                    completion?(false)
                }
            }
        }
    }

    func removeSpeechModel(id: String? = nil) {
        guard !isBusy() && !hud.recording else { return }
        let targetId = id ?? preferencesStore.preferences.speechModel
        setBusy(true)
        Task {
            do {
                try await models.removeSpeech(id: targetId)
                await MainActor.run {
                    self.cachedSpeechModelIDs.remove(targetId)
                    if self.preferencesStore.preferences.speechModel == targetId {
                        self.asrReady = false
                        self.isSpeechDownloaded = false
                        if let next = SpeechModelSpec.allModels.first(where: { self.cachedSpeechModelIDs.contains($0.id) }) {
                            self.preferencesStore.preferences.speechModel = next.id
                            self.prepareSpeech(id: next.id)
                        }
                    }
                    self.hud.status = self.preferencesStore.t("Speech model removed")
                }
            } catch {
                await MainActor.run {
                    self.hud.status = error.localizedDescription
                }
            }
            await MainActor.run {
                self.setBusy(false)
                self.checkModelCacheStatus()
            }
        }
    }

    func removeTextModel(id: String? = nil) {
        guard !isBusy() && !hud.recording else { return }
        let targetId = id ?? preferencesStore.preferences.textModel
        setBusy(true)
        Task {
            do {
                try await models.removeEditor(id: targetId)
                await MainActor.run {
                    self.cachedTextModelIDs.remove(targetId)
                    if self.preferencesStore.preferences.textModel == targetId {
                        self.editorReady = false
                        self.isEditorDownloaded = false
                        if let next = TextModelSpec.allModels.first(where: { self.cachedTextModelIDs.contains($0.id) }) {
                            self.preferencesStore.preferences.textModel = next.id
                            self.prepareEditor(id: next.id)
                        }
                    }
                    self.hud.status = self.preferencesStore.t("Text model removed")
                }
            } catch {
                await MainActor.run {
                    self.hud.status = error.localizedDescription
                }
            }
            await MainActor.run {
                self.setBusy(false)
                self.checkModelCacheStatus()
            }
        }
    }
}
