import Foundation
import Sparkle

@MainActor
final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var canCheckForUpdates = false
    private var updaterController: SPUStandardUpdaterController?

    public nonisolated static let feedURLString = "https://raw.githubusercontent.com/zfdang/voice-buddy/main/appcast.xml"

    override init() {
        super.init()
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UpdaterViewModel.feedURLString
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
