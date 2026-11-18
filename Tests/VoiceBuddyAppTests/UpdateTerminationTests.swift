import XCTest
import AppKit
@testable import VoiceBuddyApp

/// Regression coverage for Sparkle "Install & Relaunch" on this menu-bar (LSUIElement) app.
/// The app vetoes ordinary termination requests so that closing the settings window only hides
/// it. That veto must NOT apply when Sparkle asks the host to terminate for a relaunch,
/// otherwise the update silently stalls at "Install & Relaunch".
@MainActor
final class UpdateTerminationTests: XCTestCase {
    func testDefaultTerminationRequestIsVetoed() {
        let delegate = VoiceBuddyAppDelegate()

        let reply = delegate.applicationShouldTerminate(NSApp)

        XCTAssertEqual(reply, .terminateCancel,
                       "Ordinary termination must keep being vetoed so the menu-bar app stays alive")
    }

    func testSparkleRelaunchAllowsTermination() {
        let delegate = VoiceBuddyAppDelegate()

        // Mirrors UpdaterViewModel.updaterWillRelaunchApplication -> prepareForSparkleRelaunch().
        delegate.prepareForSparkleRelaunch()

        let reply = delegate.applicationShouldTerminate(NSApp)

        XCTAssertEqual(reply, .terminateNow,
                       "Sparkle's relaunch request must be allowed or 'Install & Relaunch' stalls")
    }
}
