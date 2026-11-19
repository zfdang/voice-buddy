import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI
import VoiceBuddyCore

struct GeneralSettingsView: View {
    @Bindable var preferencesStore: PreferencesStore
    var modelCatalog: ModelCatalogStore
    var permissionsStore: PermissionsStore
    var hud: LiveHUDState
    let isBusy: Bool
    let onSelectTab: (AppTab) -> Void

    @State private var showPromptPreview = false
    @State private var copiedPromptTip = false

    private func t(_ key: String) -> String { preferencesStore.t(key) }

    var body: some View {
        let permReady = permissionsStore.micAuthorized && permissionsStore.axAuthorized
        let speechReady = modelCatalog.asrReady || modelCatalog.isSpeechDownloaded
        let textReady = !preferencesStore.preferences.refinement.needsModel || modelCatalog.editorReady || modelCatalog.isEditorDownloaded
        let allReady = permReady && speechReady && textReady

        let isCurrentSpeechDownloading = modelCatalog.downloadingSpeechModelIDs.contains(preferencesStore.preferences.speechModel)
        let isCurrentTextDownloading = modelCatalog.downloadingTextModelIDs.contains(preferencesStore.preferences.textModel)

        let speechSubtitle: String = {
            if modelCatalog.isActivatingSpeechModel {
                return preferencesStore.preferences.speechModel.contains("whisper")
                    ? t("Loading (1-2 mins on first run)…")
                    : t("Loading into memory…")
            }
            if isCurrentSpeechDownloading { return t("Downloading…") }
            if modelCatalog.asrReady { return t("Ready") }
            if modelCatalog.isSpeechDownloaded { return t("Downloaded") }
            return t("Not downloaded")
        }()

        let textSubtitle: String = {
            if !preferencesStore.preferences.refinement.needsModel {
                if modelCatalog.editorReady {
                    return t("Preloaded · Not needed for Light/Original")
                }
                return t("Original / Light (No LLM needed)")
            }
            if modelCatalog.isActivatingTextModel { return t("Loading into memory…") }
            if isCurrentTextDownloading { return t("Downloading…") }
            if modelCatalog.editorReady { return t("Ready") }
            if modelCatalog.isEditorDownloaded { return t("Downloaded") }
            return t("Not downloaded")
        }()

        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: t("System Readiness Check")) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        StatusModuleButton(
                            number: 1,
                            title: t("Permissions"),
                            subtitle: permReady ? t("Authorized") : t("Needs grant"),
                            isReady: permReady,
                            isPreparing: false
                        ) { onSelectTab(.permissions) }

                        StatusModuleButton(
                            number: 2,
                            title: t("Speech Model"),
                            subtitle: speechSubtitle,
                            isReady: speechReady,
                            isPreparing: modelCatalog.isActivatingSpeechModel || isCurrentSpeechDownloading
                        ) { onSelectTab(.speech) }

                        StatusModuleButton(
                            number: 3,
                            title: t("Text Model"),
                            subtitle: textSubtitle,
                            isReady: textReady,
                            isPreparing: preferencesStore.preferences.refinement.needsModel && (modelCatalog.isActivatingTextModel || isCurrentTextDownloading)
                        ) { onSelectTab(.editor) }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        if allReady {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text(t("All 3 components ready · System is fully operational for dictation."))
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(t("System not fully ready · Please ensure all 3 modules show green checkmarks."))
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }

                    let hasBackgroundDownloads = (!isCurrentSpeechDownloading && !modelCatalog.downloadingSpeechModelIDs.isEmpty)
                        || (!isCurrentTextDownloading && !modelCatalog.downloadingTextModelIDs.isEmpty)
                    if hasBackgroundDownloads {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(t("Background models are downloading. This does not affect active dictation."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            }

            SettingsCard(title: t("Shortcut & Recording")) {
                SettingRow(
                    title: t("Trigger key"),
                    subtitle: t("Fn may also trigger the macOS Globe key action.")
                ) {
                    Picker("", selection: $preferencesStore.preferences.useFnKey) {
                        Text(t("Custom shortcut")).tag(false)
                        Text("Fn / 🌐").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(hud.recording || isBusy)
                }
                Divider()
                if !preferencesStore.preferences.useFnKey {
                    SettingRow(
                        title: t("Dictation Shortcut"),
                        subtitle: t("Press anywhere to trigger dictation")
                    ) {
                        KeyboardShortcuts.Recorder(for: .toggleDictation)
                    }
                    Divider()
                }
                SettingRow(
                    title: t("Recording Mode"),
                    subtitle: t("Hold to talk or press once to toggle recording")
                ) {
                    Picker("", selection: Binding(
                        get: { preferencesStore.preferences.holdToTalk ?? true },
                        set: { preferencesStore.preferences.holdToTalk = $0 }
                    )) {
                        Text(t("Hold to talk")).tag(true)
                        Text(t("Press to start / stop")).tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(hud.recording || isBusy)
                }
            }

            SettingsCard(title: t("Audio & Feedback")) {
                SettingRow(
                    title: t("Microphone"),
                    subtitle: t("Select audio capture device")
                ) {
                    Picker("", selection: $preferencesStore.preferences.microphoneUID) {
                        Text(t("System default")).tag("")
                        ForEach(AudioDevices.devices(), id: \.0) { device in
                            Text(device.1).tag(device.0)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                SettingRow(
                    title: t("Pause Media During Dictation"),
                    subtitle: t("Pause and resume when the player state can be verified")
                ) {
                    Toggle("", isOn: $preferencesStore.preferences.pauseMediaDuringRecording)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Divider()
                SettingRow(
                    title: t("Sound Feedback"),
                    subtitle: t("Play subtle sounds when dictation begins and finishes")
                ) {
                    Toggle("", isOn: $preferencesStore.preferences.sounds)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsCard(title: t("Text & Insertion")) {
                SettingRow(
                    title: t("Text Refinement"),
                    subtitle: t("Degree of punctuation and stylistic cleanup")
                ) {
                    Picker("", selection: $preferencesStore.preferences.refinement) {
                        Text(t("Original")).tag(Refinement.original)
                        Text(t("Light")).tag(Refinement.light)
                        Text(t("Moderate")).tag(Refinement.balanced)
                        Text(t("Deep")).tag(Refinement.moderate)
                        Text(t("Professional Rewrite")).tag(Refinement.rewrite)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if preferencesStore.preferences.refinement != .original,
                   let prompt = RefinementPrompts.prompt(for: preferencesStore.preferences.refinement) {
                    CollapsibleContextPreview(
                        title: t("View System Prompt"),
                        headerCaption: t("System Prompt for active level (Read-Only Preview)"),
                        copyButtonTitle: t("Copy Prompt"),
                        copiedTitle: t("Copied"),
                        content: prompt,
                        isExpanded: $showPromptPreview,
                        copiedTip: $copiedPromptTip
                    )
                }
                Divider()
                SettingRow(
                    title: t("Auto-Insert Text"),
                    subtitle: t("Automatically inject transcription at active cursor position")
                ) {
                    Toggle("", isOn: $preferencesStore.preferences.autoInsert)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsCard(title: t("System & Launch")) {
                SettingRow(
                    title: t("Interface Language"),
                    subtitle: t("Select display language for Voice Buddy")
                ) {
                    Picker("", selection: $preferencesStore.preferences.interfaceLanguage) {
                        Text(t("System")).tag("system")
                        Text("English").tag("en")
                        Text("简体中文").tag("zh")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                SettingRow(
                    title: t("Launch at Login"),
                    subtitle: t("Start Voice Buddy in the menu bar when Mac starts")
                ) {
                    LaunchAtLogin.Toggle {
                        Text("")
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
        }
        .frame(maxWidth: 580)
    }
}
