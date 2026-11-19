import SwiftUI

struct TextModelsView: View {
    var preferencesStore: PreferencesStore
    var modelCatalog: ModelCatalogStore
    var hud: LiveHUDState
    let isBusy: Bool

    @State private var confirmTextDelete = false
    @State private var textModelToDelete: String? = nil

    private func t(_ key: String) -> String { preferencesStore.t(key) }
    private func label(_ en: String, _ zh: String) -> String { preferencesStore.label(en, zh) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: t("Local Models & Storage")) {
                VStack(spacing: 14) {
                    ForEach(Array(TextModelSpec.allModels.enumerated()), id: \.element.id) { index, spec in
                        if index > 0 {
                            Divider()
                        }

                        let isCached = modelCatalog.cachedTextModelIDs.contains(spec.id)
                        let isDownloadingThis = modelCatalog.downloadingTextModelIDs.contains(spec.id)
                        let progressVal = modelCatalog.textDownloadProgress[spec.id] ?? 0
                        let progressMsg = modelCatalog.textDownloadMessages[spec.id] ?? ""

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 10) {
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
                                    }
                                    Text(label(spec.descriptionEn, spec.description))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 16)

                                HStack(spacing: 10) {
                                    if isDownloadingThis {
                                        HStack(spacing: 4) {
                                            ProgressView().controlSize(.small)
                                            Text("\(Int(progressVal * 100))%")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 80, alignment: .trailing)

                                        Button(t("Cancel")) {
                                            modelCatalog.cancelTextDownload(id: spec.id)
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
                                            textModelToDelete = spec.id
                                            confirmTextDelete = true
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
                                            modelCatalog.downloadTextModel(id: spec.id)
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

            SettingsCard(title: t("Text Refinement Model")) {
                let downloadedSpecs = TextModelSpec.allModels.filter { modelCatalog.cachedTextModelIDs.contains($0.id) }

                if downloadedSpecs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("No Models Downloaded Locally"))
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
                        title: t("Active Refinement Model"),
                        subtitle: t("Local LLM used for Moderate, Deep and Professional Rewrite")
                    ) {
                        Picker("", selection: Binding(
                            get: { preferencesStore.preferences.textModel },
                            set: { modelCatalog.selectTextModel(id: $0) }
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

                    HStack(spacing: 8) {
                        if modelCatalog.editorReady {
                            if preferencesStore.preferences.refinement.needsModel {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(t("Model is loaded in unified memory · Ready for instant zero-latency refinement."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(t("Unload")) {
                                    modelCatalog.unloadEditor()
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                .accessibilityLabel(t("Unload text model"))
                            } else {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text(t("Model is preloaded, but current mode (Original/Light) does not need it."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(t("Unload to Free Memory")) {
                                    modelCatalog.unloadEditor()
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                                .accessibilityLabel(t("Unload text model to free memory"))
                            }
                        } else if modelCatalog.isActivatingTextModel {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("Loading model into unified memory…"))
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                Text(t("Mapping unified memory weights, please wait…"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        } else if !preferencesStore.preferences.refinement.needsModel {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text(t("Original and Light modes do not require a text model; no memory used."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(t("Preload Anyway")) {
                                modelCatalog.loadActiveEditorModel(force: true)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .accessibilityLabel(t("Preload Anyway"))
                        } else {
                            Image(systemName: "pause.circle")
                                .foregroundStyle(.orange)
                            Text(t("Model not loaded into unified memory."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(t("Load into Memory")) {
                                modelCatalog.loadActiveEditorModel()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel(t("Load into Memory"))
                        }
                    }
                }
            }

            SettingsCard(title: t("How Refinement Works")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Original mode")).font(.subheadline.bold())
                            Text(t("Outputs raw speech recognition results directly without loading LLM, providing lightning-fast zero-overhead dictation."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Light uses local rules to normalize whitespace and remove standalone hesitations; it preserves self-corrections and does not load a text model."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(t("Moderate, Deep & Professional Rewrite")).font(.subheadline.bold())
                            Text(t("Run 100% locally via Apple Silicon unified memory to polish speech, fix homophone errors, remove oral fillers, or reconstruct formal lists. If the text model is ever unavailable, the system automatically degrades gracefully to inputting the original transcript."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 680)
        .confirmationDialog(t("Delete this text model from disk?"), isPresented: $confirmTextDelete) {
            Button(t("Delete"), role: .destructive) {
                if let targetId = textModelToDelete {
                    modelCatalog.removeTextModel(id: targetId)
                    textModelToDelete = nil
                } else {
                    modelCatalog.removeTextModel()
                }
            }
        } message: {
            Text(t("Model files will be removed from your disk. You can re-download anytime."))
        }
    }
}
