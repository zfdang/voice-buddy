import AppKit
import Sparkle

@MainActor
final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published var canCheckForUpdates = false
    private var updaterController: SPUStandardUpdaterController?
    private var updateScreenFrame: NSRect?
    private var showingModalAlert = false

    public nonisolated static let feedURLString = "https://myvoicebuddy.com/appcast.xml"

    var updaterInstance: SPUUpdater? { updaterController?.updater }

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSparkleWillRestart(_:)),
            name: NSNotification.Name.SUUpdaterWillRestart,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        if let infoFeedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String {
            let trimmed = infoFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return UpdaterViewModel.feedURLString
    }

    /// Sparkle calls this immediately before terminating the host app to relaunch after an
    /// update. The app is a menu-bar (LSUIElement) agent that vetoes ordinary termination
    /// requests by default, so explicitly allow this one or "Install & Relaunch" stalls.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        VoiceBuddyAppDelegate.shared?.prepareForSparkleRelaunch()
    }

    /// Reset the pending relaunch allowance if Stage 2 aborts (for instance, the user cancels
    /// authorization) so the menu-bar app does not remain permanently terminable.
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        VoiceBuddyAppDelegate.shared?.cancelSparkleRelaunch()
    }

    @objc private func handleSparkleWillRestart(_ notification: Notification) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                VoiceBuddyAppDelegate.shared?.prepareForSparkleRelaunch()
            }
        } else {
            Task { @MainActor in
                VoiceBuddyAppDelegate.shared?.prepareForSparkleRelaunch()
            }
        }
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
