import SwiftUI

struct PermissionsSettingsView: View {
    var permissionsStore: PermissionsStore
    var preferencesStore: PreferencesStore

    private func t(_ key: String) -> String { preferencesStore.t(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(t("Voice Buddy works completely offline. Permissions are only used for local audio capture and text insertion."))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: (permissionsStore.micAuthorized && permissionsStore.axAuthorized) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle((permissionsStore.micAuthorized && permissionsStore.axAuthorized) ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text((permissionsStore.micAuthorized && permissionsStore.axAuthorized) ? t("All required permissions granted") : t("Permissions needed"))
                        .font(.headline)
                    Text((permissionsStore.micAuthorized && permissionsStore.axAuthorized) ? t("Voice Buddy is fully ready for offline dictation and insertion.") : t("Please grant the missing permissions below to enable seamless voice input."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("Re-check")) {
                    permissionsStore.refreshPermissions()
                }
                .accessibilityLabel(t("Re-check"))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(t("Microphone Access"), systemImage: "mic.fill")
                        .font(.headline)
                    Spacer()
                    if permissionsStore.micAuthorized {
                        AuthorizedStatusBadge(title: t("Authorized"))
                    } else if permissionsStore.micStatus == .denied {
                        Label(t("Denied"), systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    } else {
                        Label(t("Not Determined"), systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
                Text(t("Allows Voice Buddy to capture your voice from the microphone for local speech recognition. Audio is never recorded to disk or sent online."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if !permissionsStore.micAuthorized && permissionsStore.micStatus == .notDetermined {
                        Button(t("Request Microphone Permission")) {
                            permissionsStore.requestMicrophoneAccess()
                        }
                        .accessibilityLabel(t("Request Microphone Permission"))
                    }
                    Button(t("Open System Settings")) {
                        permissionsStore.openSystemSettings(for: "microphone")
                    }
                    .accessibilityLabel(t("Open System Settings"))
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(t("Accessibility Access"), systemImage: "command")
                        .font(.headline)
                    Spacer()
                    if permissionsStore.axAuthorized {
                        AuthorizedStatusBadge(title: t("Authorized"))
                    } else {
                        Label(t("Not Authorized"), systemImage: "xmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
                Text(t("Allows Voice Buddy to detect the active text box in other applications and safely insert the recognized text at your cursor without losing undo history."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if !permissionsStore.axAuthorized {
                        Button(t("Request Accessibility Permission")) {
                            permissionsStore.requestAccessibilityAccess()
                        }
                        .accessibilityLabel(t("Request Accessibility Permission"))
                    }
                    Button(t("Open System Settings")) {
                        permissionsStore.openSystemSettings(for: "accessibility")
                    }
                    .accessibilityLabel(t("Open System Settings"))
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text(t("Privacy & Security Commitments")).font(.subheadline.bold())
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield").foregroundStyle(.green)
                    Text(t("100% Offline: Models run directly on Apple Silicon via Metal / Core ML with zero network dependencies during dictation."))
                        .font(.caption)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield").foregroundStyle(.green)
                    Text(t("Clipboard Hygiene: Transient pasteboard markers prevent third-party history managers (Raycast, Paste, Maccy) from indexing your dictations."))
                        .font(.caption)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield").foregroundStyle(.green)
                    Text(t("Secure Field Guard: Automatically disables auto-insertion if a secure password field is active."))
                        .font(.caption)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
        }
        .frame(maxWidth: 620)
    }
}
