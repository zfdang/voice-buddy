import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Observation

/// Tracks macOS Microphone and Accessibility permissions cleanly outside AppState.
@MainActor
@Observable
final class PermissionsStore {
    var micAuthorized = false
    var axAuthorized = false
    var micStatus: AVAuthorizationStatus = .notDetermined
    @ObservationIgnored var waitingForSystemSettingsReturn = false

    func refreshPermissions() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        micAuthorized = (micStatus == .authorized)
        axAuthorized = AXIsProcessTrusted()
    }

    func requestMicrophoneAccess() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshPermissions()
        }
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
    }

    func openSystemSettings(for permission: String) {
        waitingForSystemSettingsReturn = true
        let urlString = permission == "microphone"
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
