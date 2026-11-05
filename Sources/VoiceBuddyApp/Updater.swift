import Foundation
import Sparkle

@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var updaterController: SPUStandardUpdaterController?

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
