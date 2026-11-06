import XCTest
@testable import VoiceBuddyApp

final class AccessibleMediaPlaybackTests: XCTestCase {
    func testOnlyExplicitPlaybackControlLabelsAreAccepted() {
        XCTAssertEqual(AccessibleMediaPlaybackBackend.playbackState(forLabel: "暂停 (Space)"), true)
        XCTAssertEqual(AccessibleMediaPlaybackBackend.playbackState(forLabel: "播放 (Space)"), false)
        XCTAssertEqual(AccessibleMediaPlaybackBackend.playbackState(forLabel: "Pause playback"), true)
        XCTAssertEqual(AccessibleMediaPlaybackBackend.playbackState(forLabel: "Resume playback"), false)
        XCTAssertNil(AccessibleMediaPlaybackBackend.playbackState(forLabel: "暂停"))
        XCTAssertNil(AccessibleMediaPlaybackBackend.playbackState(forLabel: "Pause"))
        XCTAssertNil(AccessibleMediaPlaybackBackend.playbackState(forLabel: nil))
    }

    func testRequiresPlaybackProgressAndUniqueAudioApp() {
        XCTAssertTrue(AccessibleMediaPlaybackBackend.isPlaybackProgress("播放进度"))
        XCTAssertTrue(AccessibleMediaPlaybackBackend.isPlaybackProgress("Playback position"))
        XCTAssertFalse(AccessibleMediaPlaybackBackend.isPlaybackProgress("Volume"))
        XCTAssertNil(AudioOutputProcesses.uniqueCandidate([]))
        XCTAssertEqual(AudioOutputProcesses.uniqueCandidate([123]), 123)
        XCTAssertNil(AudioOutputProcesses.uniqueCandidate([123, 456]))
    }
}
