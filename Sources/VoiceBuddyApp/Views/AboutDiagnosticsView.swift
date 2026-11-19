import AppKit
import SwiftUI

struct AboutDiagnosticsView: View {
    var preferencesStore: PreferencesStore
    let onCheckForUpdates: () -> Void

    @State private var diagnosticsError = false

    private func t(_ key: String) -> String { preferencesStore.t(key) }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Version Information")).font(.headline)
                VStack(spacing: 8) {
                    HStack {
                        Text(t("Current version")).foregroundStyle(.secondary)
                        Spacer()
                        Text("v\(appVersion) (\(t("Build")) \(appBuild))")
                            .font(.system(.body, design: .monospaced))
                    }
                    Divider()
                    HStack {
                        Text(t("Architecture")).foregroundStyle(.secondary)
                        Spacer()
                        #if arch(arm64)
                        Text("Apple Silicon (arm64)")
                        #else
                        Text("Intel (x86_64)")
                        #endif
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(t("Software Update")).font(.headline)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("Keep Voice Buddy up to date"))
                            .font(.subheadline.bold())
                        Text(t("Check for new versions, enhancements, and fixes."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("Check for Updates…")) {
                        onCheckForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(t("Diagnostics")).font(.headline)
                Text(t("Stored only on this Mac. Logs include app identifiers, microphone names, and diagnostic status, but not audio, dictated text, or clipboard contents. Seven files of up to about 1 MB each are retained."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(t("Show Logs in Finder")) {
                    do {
                        let url = try DiagnosticLog.shared.readyFile()
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } catch {
                        diagnosticsError = true
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text(t("Introduction & Links")).font(.headline)
                VStack(alignment: .leading, spacing: 12) {
                    Text(t("Voice Buddy runs entirely offline on your Mac. Using local speech recognition and lightweight language models, it turns spoken words into clean, punctuated text in milliseconds without sending any audio or text data to the cloud. Dictation is activated exclusively via your global keyboard shortcut."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    VStack(spacing: 8) {
                        HStack {
                            Label(t("Official Website"), systemImage: "globe")
                            Spacer()
                            Link("myvoicebuddy.com", destination: URL(string: "https://myvoicebuddy.com")!)
                        }
                        Divider()
                        HStack {
                            Label(t("Releases & Downloads"), systemImage: "shippingbox")
                            Spacer()
                            Link(t("Visit Website"), destination: URL(string: "https://myvoicebuddy.com")!)
                        }
                        Divider()
                        HStack {
                            Label("GitHub Repository", systemImage: "link")
                            Spacer()
                            Link("github.com/zfdang/voice-buddy", destination: URL(string: "https://github.com/zfdang/voice-buddy")!)
                        }
                        Divider()
                        HStack {
                            Label(t("Issues & Feedback"), systemImage: "bubble.left.and.exclamationmark.bubble.right")
                            Spacer()
                            Link(t("Submit Issue"), destination: URL(string: "https://github.com/zfdang/voice-buddy/issues")!)
                        }
                    }

                    Divider()

                    Text(t("Built with Sparkle, KeyboardShortcuts, LaunchAtLogin, Whisper.cpp, and MLX."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: 560)
        .alert(t("Could not read diagnostic logs"), isPresented: $diagnosticsError) {
            Button(t("OK"), role: .cancel) { }
        } message: {
            Text(t("Check that Voice Buddy can write to its local Logs folder."))
        }
    }
}
