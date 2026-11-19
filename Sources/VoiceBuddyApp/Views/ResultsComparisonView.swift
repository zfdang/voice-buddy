import AppKit
import SwiftUI
import VoiceBuddyCore

struct ResultsComparisonView: View {
    @EnvironmentObject var state: AppState
    @State private var resultTestMode: Refinement?
    @State private var resultActionStatus = ""

    private func t(_ key: String) -> String { state.preferencesStore.t(key) }

    private func refinementName(_ mode: Refinement) -> String {
        switch mode {
        case .original: return t("Original")
        case .light: return t("Light")
        case .balanced: return t("Moderate")
        case .moderate: return t("Deep")
        case .rewrite: return t("Professional Rewrite")
        }
    }

    var body: some View {
        let prefs = state.preferencesStore.preferences
        let catalog = state.modelCatalog!

        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: t("Direct Speech Recognition (Original)")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Raw transcript directly produced by the speech recognition model without post-processing."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(state.original.isEmpty ? t("No speech input recorded yet.") : state.original)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(state.original.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .frame(minHeight: 80, maxHeight: 140)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    HStack {
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(state.original, forType: .string)
                            state.hud.status = t("Original text copied")
                        } label: {
                            Label(t("Copy Original"), systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                        .disabled(state.original.isEmpty)
                        .accessibilityLabel(t("Copy Original"))
                    }
                }
            }

            SettingsCard(title: t("Refined & Optimized Output")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Use the current text model to compare refinement levels on the same original transcript."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let model = TextModelSpec.allModels.first(where: { $0.id == prefs.textModel }) {
                        Text(t("Current model: ") + model.name + " · " + model.quantization)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Picker(t("Refinement Level"), selection: Binding(
                            get: { resultTestMode ?? prefs.refinement },
                            set: { resultTestMode = $0 }
                        )) {
                            ForEach(Refinement.allCases) { mode in
                                Text(refinementName(mode) + (mode == prefs.refinement ? t(" (Default)") : ""))
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(catalog.testingRefinement)

                        Button(t("Test")) {
                            let mode = resultTestMode ?? prefs.refinement
                            resultActionStatus = ""
                            Task { await catalog.testRefinement(mode: mode) }
                        }
                        .disabled(state.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || catalog.testingRefinement || state.busy || state.hud.recording)
                    }
                    HStack {
                        if catalog.testingRefinement { ProgressView().controlSize(.small) }
                        Text(catalog.refinementTestStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !catalog.refinementTestSummary.isEmpty {
                        Text(catalog.refinementTestSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextEditor(text: $state.result)
                        .disabled(catalog.testingRefinement)
                        .font(.system(.body, design: .default))
                        .frame(minHeight: 110, maxHeight: 180)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    HStack(spacing: 12) {
                        Button {
                            state.copyResult()
                            resultActionStatus = state.hud.status
                        } label: {
                            Label(t("Copy Result"), systemImage: "doc.on.clipboard")
                        }
                        .controlSize(.small)
                        .disabled(state.result.isEmpty || catalog.testingRefinement)
                        .accessibilityLabel(t("Copy Result"))

                        Button {
                            if state.insertIfSafe(state.result) {
                                resultActionStatus = t("Insertion queued")
                            } else {
                                state.hud.status = state.insertFailure
                                resultActionStatus = state.insertFailure
                            }
                        } label: {
                            Label(t("Insert into Active App"), systemImage: "arrow.down.doc")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(state.result.isEmpty || catalog.testingRefinement)
                        .accessibilityLabel(t("Insert into Active App"))

                        Spacer()
                        if !resultActionStatus.isEmpty {
                            Text(resultActionStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
