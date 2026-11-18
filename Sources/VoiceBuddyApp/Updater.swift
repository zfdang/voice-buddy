import AppKit
import Sparkle

@MainActor
final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published var canCheckForUpdates = false
    private var updaterController: SPUStandardUpdaterController?
    private var updateScreenFrame: NSRect?
    private var showingModalAlert = false

    public nonisolated static let feedURLString = "https://raw.githubusercontent.com/zfdang/voice-buddy/main/appcast.xml"

    override init() {
        super.init()
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.updaterController = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        NotificationCenter.default.addObserver(self, selector: #selector(positionUpdateWindow(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UpdaterViewModel.feedURLString
    }

    /// Sparkle calls this immediately before terminating the host app to relaunch after an
    /// update. The app is a menu-bar (LSUIElement) agent that vetoes ordinary termination
    /// requests by default, so explicitly allow this one or "Install & Relaunch" stalls.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        VoiceBuddyAppDelegate.shared?.prepareForSparkleRelaunch()
    }

    func checkForUpdates() {
        let screen = NSApp.keyWindow?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        updateScreenFrame = screen?.visibleFrame
        updaterController?.checkForUpdates(nil)
    }

    @objc private func positionUpdateWindow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let screen = updateScreenFrame else { return }
        let identifier = window.identifier?.rawValue
        guard identifier == "SUStatus" || identifier == "SUUpdateAlert" || (showingModalAlert && NSApp.modalWindow === window) else { return }
        let frame = window.frame
        window.setFrameOrigin(NSPoint(x: screen.midX - frame.width / 2, y: screen.midY - frame.height / 2))
    }

    func standardUserDriverWillShowModalAlert() { showingModalAlert = true }
    func standardUserDriverDidShowModalAlert() { showingModalAlert = false }
    func standardUserDriverWillFinishUpdateSession() {
        updateScreenFrame = nil
        showingModalAlert = false
    }
}
