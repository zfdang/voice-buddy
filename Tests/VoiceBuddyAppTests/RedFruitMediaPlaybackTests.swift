import XCTest
@testable import VoiceBuddyApp

final class RedFruitMediaPlaybackTests: XCTestCase {
    func testOnlyRecognizedPlaybackLabelsAreAccepted() {
        XCTAssertEqual(RedFruitMediaPlaybackBackend.playbackState(forHelp: "暂停 (Space)"), true)
        XCTAssertEqual(RedFruitMediaPlaybackBackend.playbackState(forHelp: "播放 (Space)"), false)
        XCTAssertNil(RedFruitMediaPlaybackBackend.playbackState(forHelp: "暂停"))
        XCTAssertNil(RedFruitMediaPlaybackBackend.playbackState(forHelp: nil))
    }
}
