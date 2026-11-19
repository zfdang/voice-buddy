import AppKit
import SwiftUI

private struct RecordingBannerView: View {
    var hud: LiveHUDState
    var preferencesStore: PreferencesStore
    let onCancel: () -> Void

    var body: some View {
        if hud.recording {
            HStack {
                Image(systemName: "mic.fill").foregroundStyle(.red)
                Text(preferencesStore.t("Listening"))
                ProgressView(value: min(Double(hud.level) * 12, 1)).frame(width: 100)
                Button(preferencesStore.t("Cancel"), action: onCancel)
            }
            Divider()
        }
    }
}

struct MainView: View {
    @EnvironmentObject var state: AppState

    private func t(_ key: String) -> String { state.preferencesStore.t(key) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 108)
            Color(nsColor: .separatorColor)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RecordingBannerView(
                        hud: state.hud,
                        preferencesStore: state.preferencesStore,
                        onCancel: { state.cancel() }
                    )
                    switch state.selectedTab {
                    case .general:
                        GeneralSettingsView(
                            preferencesStore: state.preferencesStore,
                            modelCatalog: state.modelCatalog,
                            permissionsStore: state.permissionsStore,
                            hud: state.hud,
                            isBusy: state.busy,
                            onSelectTab: { state.selectedTab = $0 }
                        )
                    case .permissions:
                        PermissionsSettingsView(
                            permissionsStore: state.permissionsStore,
                            preferencesStore: state.preferencesStore
                        )
                    case .speech:
                        SpeechModelsView(
                            preferencesStore: state.preferencesStore,
                            modelCatalog: state.modelCatalog,
                            hud: state.hud,
                            isBusy: state.busy
                        )
                    case .editor:
                        TextModelsView(
                            preferencesStore: state.preferencesStore,
                            modelCatalog: state.modelCatalog,
                            hud: state.hud,
                            isBusy: state.busy
                        )
                    case .recovery:
                        ResultsComparisonView()
                    case .about:
                        AboutDiagnosticsView(
                            preferencesStore: state.preferencesStore,
                            onCheckForUpdates: { state.checkForUpdates() }
                        )
                    }
                    Spacer()
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            state.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
        .onChange(of: state.selectedTab) { _, _ in
            state.checkModelCacheStatus()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                Text("Voice Buddy")
                    .font(.system(size: 13, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(AppTab.sidebarGroups.enumerated()), id: \.offset) { index, tabs in
                        if index > 0 {
                            Divider()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        ForEach(tabs) { tab in
                            sidebarButton(tab)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sidebarButton(_ tab: AppTab) -> some View {
        let isSelected = state.selectedTab == tab
        return Button {
            state.selectedTab = tab
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tabSystemImage(tab))
                    .font(.system(size: 21, weight: .semibold))
                Text(tabTitle(tab))
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func tabSystemImage(_ tab: AppTab) -> String {
        switch tab {
        case .general: return "slider.horizontal.3"
        case .permissions: return "checkmark.shield"
        case .speech: return "waveform"
        case .editor: return "text.bubble"
        case .recovery: return "doc.text"
        case .about: return "info.circle"
        }
    }

    private func tabTitle(_ tab: AppTab) -> String {
        switch tab {
        case .general: return t("General")
        case .permissions: return t("Permissions")
        case .speech: return t("Speech")
        case .editor: return t("Text model")
        case .recovery: return t("Recognition Result")
        case .about: return t("About")
        }
    }

    private var mascot: NSImage {
        if let url = Bundle.main.url(forResource: "mascot", withExtension: "png"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage()
    }
}
