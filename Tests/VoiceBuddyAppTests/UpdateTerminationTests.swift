import XCTest
import AppKit
import Sparkle
@testable import VoiceBuddyApp

/// Regression coverage for Sparkle "Install & Relaunch" on this menu-bar (LSUIElement) app.
/// The app vetoes ordinary termination requests so that closing the settings window only hides
/// it. That veto must NOT apply when Sparkle asks the host to terminate for a relaunch,
/// otherwise the update silently stalls at "Install & Relaunch".
@MainActor
final class UpdateTerminationTests: XCTestCase {
    private var delegate: VoiceBuddyAppDelegate!

    override func setUp() async throws {
        // Skip model preloading: it initializes MLX/Metal on a background task, which aborts
        // the process on CI runners without a Metal shader cache. Termination logic is independent.
        delegate = VoiceBuddyAppDelegate(skipModelPreload: true)
    }

    override func tearDown() async throws {
        VoiceBuddyAppDelegate.shared = nil
        delegate = nil
    }

    func testDefaultTerminationRequestIsVetoed() {
        let reply = delegate.applicationShouldTerminate(NSApp)

        XCTAssertEqual(reply, .terminateCancel,
                       "Ordinary termination must keep being vetoed so the menu-bar app stays alive")
    }

    func testUpdaterDelegateRelaunchHookAllowsTermination() throws {
        let updater = try XCTUnwrap(delegate.appState.updater.updaterInstance)

        delegate.appState.updater.updaterWillRelaunchApplication(updater)

        let reply = delegate.applicationShouldTerminate(NSApp)
        XCTAssertEqual(reply, .terminateNow,
                       "SPUUpdaterDelegate.updaterWillRelaunchApplication must allow termination")
    }

    func testSparkleWillRestartNotificationAllowsTermination() {
        NotificationCenter.default.post(
            name: NSNotification.Name.SUUpdaterWillRestart,
            object: nil
        )

        let reply = delegate.applicationShouldTerminate(NSApp)
        XCTAssertEqual(reply, .terminateNow,
                       "SUUpdaterWillRestartNotification must allow termination as fallback")
    }

    func testSparkleAbortResetsPendingRelaunchAndRestoresVeto() throws {
        let updater = try XCTUnwrap(delegate.appState.updater.updaterInstance)

        delegate.appState.updater.updaterWillRelaunchApplication(updater)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateNow)

        delegate.appState.updater.updater(
            updater,
            didAbortWithError: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationCanceledError.rawValue))
        )

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateCancel,
                       "Aborting or cancelling an update must restore the default termination veto")
    }

    func testUpdaterFeedURLDefaultsToOfficialMyVoiceBuddyFeed() throws {
        let updater = try XCTUnwrap(delegate.appState.updater.updaterInstance)
        XCTAssertEqual(UpdaterViewModel.feedURLString, "https://myvoicebuddy.com/appcast.xml")
        XCTAssertEqual(
            delegate.appState.updater.feedURLString(for: updater),
            "https://myvoicebuddy.com/appcast.xml",
            "Sparkle feed URL must stay unified on myvoicebuddy.com instead of diverging from Info.plist"
        )
    }
}
