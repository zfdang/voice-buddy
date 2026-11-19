import SwiftUI

struct SpeechModelsView: View {
    @Bindable var preferencesStore: PreferencesStore
    var modelCatalog: ModelCatalogStore
    var hud: LiveHUDState
    let isBusy: Bool

    @State private var confirmSpeechDelete = false
    @State private var speechModelToDelete: String? = nil
    @State private var showDeveloperContextPreview = false
    @State private var copiedDeveloperContextTip = false

    private func t(_ key: String) -> String { preferencesStore.t(key) }
    private func label(_ en: String, _ zh: String) -> String { preferencesStore.label(en, zh) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: t("Local Speech Models & Storage")) {
                VStack(spacing: 14) {
                    ForEach(Array(SpeechModelSpec.allModels.enumerated()), id: \.element.id) { index, spec in
                        if index > 0 {
                            Divider()
                        }

                        let isCached = modelCatalog.cachedSpeechModelIDs.contains(spec.id)
                        let isDownloadingThis = modelCatalog.downloadingSpeechModelIDs.contains(spec.id)
                        let progressVal = modelCatalog.speechDownloadProgress[spec.id] ?? 0
                        let progressMsg = modelCatalog.speechDownloadMessages[spec.id] ?? ""

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(spec.name)
                                            .font(.headline)
                                        Text(spec.quantization)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(Capsule())
                                        Text(spec.size)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 2) {
                                            Image(systemName: "bolt.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.yellow)
                                            Text(spec.latency)
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow.opacity(0.1))
                                        .clipShape(Capsule())
                                    }
                                    Text(label(spec.descriptionEn, spec.description))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 16)

                                HStack(spacing: 10) {
                                    if spec.id == "apple-speech" {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundStyle(.green)
                                            Text(t("Built-in"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Text(t("Free"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 90)
                                    } else if isDownloadingThis {
                                        HStack(spacing: 4) {
                                            ProgressView().controlSize(.small)
                                            Text("\(Int(progressVal * 100))%")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Button(t("Cancel")) {
                                            modelCatalog.cancelSpeechDownload(id: spec.id)
                                        }
                                        .controlSize(.small)
                                        .frame(minWidth: 90)
                                        .accessibilityLabel(t("Cancel"))
                                    } else if isCached {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.green).frame(width: 8, height: 8)
                                            Text(t("Downloaded"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Button(role: .destructive) {
                                            speechModelToDelete = spec.id
                                            confirmSpeechDelete = true
                                        } label: {
                                            Text(t("Delete Cache…"))
                                        }
                                        .controlSize(.small)
                                        .disabled(isBusy || hud.recording)
                                        .frame(minWidth: 90)
                                        .accessibilityLabel(t("Delete Cache…"))
                                    } else {
                                        HStack(spacing: 4) {
                                            Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
                                            Text(t("Not Downloaded"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Button {
                                            modelCatalog.downloadSpeechModel(id: spec.id)
                                        } label: {
                                            Text(t("Download"))
                                        }
                                        .controlSize(.small)
                                        .buttonStyle(.borderedProminent)
                                        .disabled(isBusy || hud.recording)
                                        .frame(minWidth: 90)
                                        .accessibilityLabel(t("Download"))
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }

                            if isDownloadingThis {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: progressVal)
                                    if !progressMsg.isEmpty {
                                        Text(progressMsg)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                }
            }

            SettingsCard(title: t("Speech Recognition Model")) {
                let downloadedSpecs = SpeechModelSpec.allModels.filter { modelCatalog.cachedSpeechModelIDs.contains($0.id) }

                if downloadedSpecs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("No Speech Models Downloaded Locally"))
                                .font(.headline)
                            Text(t("Please click 'Download' on a model in the list above. Once downloaded, you can select it here for instant use."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else {
                    SettingRow(
                        title: t("Active Recognition Model"),
                        subtitle: t("On-device acoustic model for speech-to-text")
                    ) {
                        Picker("", selection: Binding(
                            get: { preferencesStore.preferences.speechModel },
                            set: { modelCatalog.selectSpeechModel(id: $0) }
                        )) {
                            ForEach(downloadedSpecs) { spec in
                                Text("\(spec.name) (\(spec.quantization) · \(spec.size))").tag(spec.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(isBusy || hud.recording)
                    }

                    Divider()

                    if let activeSpec = SpeechModelSpec.allModels.first(where: { $0.id == preferencesStore.preferences.speechModel }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(t("Model Profile & Evaluation"))
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(0..<5) { star in
                                        Image(systemName: star < activeSpec.speedRating ? "bolt.fill" : "bolt")
                                            .font(.caption2)
                                            .foregroundStyle(star < activeSpec.speedRating ? .yellow : .secondary)
                                    }
                                    Text(activeSpec.latency)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                                GridRow {
                                    Text(t("Languages:"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(label(activeSpec.languagesEn, activeSpec.languagesZh))
                                        .font(.caption2.bold())
                                }
                                GridRow {
                                    Text(t("Evaluation:"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(label(activeSpec.accuracyScoreEn, activeSpec.accuracyScore))
                                        .font(.caption2.bold())
                                        .foregroundStyle(.blue)
                                }
                                GridRow {
                                    Text(t("Footprint:"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(activeSpec.memoryUsage) · \(activeSpec.size) (\(activeSpec.quantization))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                GridRow {
                                    Text(t("Best For:"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(label(activeSpec.bestForEn, activeSpec.bestForZh))
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                }
                            }
                            if activeSpec.id.contains("whisper") {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text(t("First load compiles to Apple Neural Engine (~1–2 mins, once only). Instant thereafter."))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }

                    Divider()

                    HStack(spacing: 8) {
                        if modelCatalog.asrReady {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(t("Model & VAD are loaded in unified memory · Ready for instant dictation."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if modelCatalog.isActivatingSpeechModel {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Loading model into unified memory…"))
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                if preferencesStore.preferences.speechModel.contains("whisper") {
                                    Text(t("First-time load requires Neural Engine compilation (~1–2 minutes, one-time only). Subsequent launches will be instant."))
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(t("Allocating memory and initializing neural weights…"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Image(systemName: "pause.circle")
                                .foregroundStyle(.orange)
                            Text(t("Model not loaded into unified memory."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(t("Load into Memory")) {
                                modelCatalog.loadActiveSpeechModel()
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .accessibilityLabel(t("Load into Memory"))
                        }
                        Spacer()
                    }

                    Divider()

                    SettingRow(
                        title: t("Developer Vocabulary Context (Qwen3-ASR)"),
                        subtitle: preferencesStore.preferences.speechModel.contains("qwen-asr")
                            ? preferencesStore.formatted("Pass %d programming & engineering terms to Qwen3-ASR context", DeveloperASRContext.terms.count)
                            : preferencesStore.formatted("Pass %d programming & engineering terms when using Qwen3-ASR (inactive on current model)", DeveloperASRContext.terms.count)
                    ) {
                        Toggle("", isOn: $preferencesStore.preferences.developerContextEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    CollapsibleContextPreview(
                        title: preferencesStore.formatted("View Developer Context (%d terms)", DeveloperASRContext.terms.count),
                        headerCaption: t("Qwen3-ASR System Context (Read-Only Preview)"),
                        copyButtonTitle: t("Copy Vocabulary"),
                        copiedTitle: t("Copied"),
                        content: DeveloperASRContext.contextString,
                        isExpanded: $showDeveloperContextPreview,
                        copiedTip: $copiedDeveloperContextTip
                    )

                    Divider()

                    SettingRow(
                        title: t("Spoken Language"),
                        subtitle: t("Select primary spoken language or auto-detect")
                    ) {
                        Picker("", selection: $preferencesStore.preferences.speechLanguage) {
                            Text(t("Automatic / Mixed")).tag("auto")
                            Text("中文 (普通话)").tag("Chinese")
                            Text("粵語 (Cantonese)").tag("Cantonese")
                            Text("English").tag("English")
                            Text("日本語 (Japanese)").tag("Japanese")
                            Text("한국어 (Korean)").tag("Korean")
                            Text("Français").tag("French")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            SettingsCard(title: t("How Speech Recognition Works")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Multi-Engine On-Device Transcription")).font(.subheadline.bold())
                            Text(t("Voice Buddy supports 4 distinct model architectures tailored to your hardware and workflows: Qwen3-ASR (MLX flagship for Chinese & Chinglish), Whisper Large-v3 Turbo (CoreML 90+ languages), SenseVoice Small (FunASR sub-100ms instant response), and Apple Speech (0 MB built-in instant ready)."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Silero VAD Voice Activity Detection")).font(.subheadline.bold())
                            Text(t("Ultra-low latency speech boundary detection. Seamlessly isolates speech from background noise and silence with zero external server transmission."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 680)
        .confirmationDialog(t("Delete this speech model from disk?"), isPresented: $confirmSpeechDelete) {
            Button(t("Delete"), role: .destructive) {
                if let targetId = speechModelToDelete {
                    modelCatalog.removeSpeechModel(id: targetId)
                    speechModelToDelete = nil
                } else {
                    modelCatalog.removeSpeechModel()
                }
            }
        } message: {
            Text(t("Model files will be removed from your disk. You can re-download anytime."))
        }
    }
}
