import XCTest
@testable import VoiceBuddyCore

@MainActor private final class FakeMediaBackend: MediaPlaybackBackend {
    var pending: [(MediaPlaybackSnapshot?) -> Void] = []
    var pauseCount = 0
    var playCount = 0
    var pauseSucceeds = true
    func snapshot(completion: @escaping (MediaPlaybackSnapshot?) -> Void) { pending.append(completion) }
    func pause() -> Bool { pauseCount += 1; return pauseSucceeds }
    func play() -> Bool { playCount += 1; return true }
    func complete(_ value: MediaPlaybackSnapshot?) { pending.removeFirst()(value) }
}

final class MediaPlaybackControllerTests: XCTestCase {
    func testAlreadyPausedAndUnknownStateNeverStartPlayback() async {
        await MainActor.run {
            let backend = FakeMediaBackend(), controller = MediaPlaybackController(backend: backend)
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: false))
            controller.resumeIfPaused()
            controller.pauseIfPlaying()
            backend.complete(nil)
            controller.resumeIfPaused()
            XCTAssertEqual(backend.pauseCount, 0)
            XCTAssertEqual(backend.playCount, 0)
        }
    }
    func testOnlyVerifiedPauseOfSamePlayerIsResumed() async {
        await MainActor.run {
            let backend = FakeMediaBackend(), controller = MediaPlaybackController(backend: backend)
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: true))
            XCTAssertEqual(backend.pauseCount, 1)
            backend.complete(.init(processID: 10, isPlaying: false))
            XCTAssertTrue(controller.didPauseMedia)
            controller.resumeIfPaused()
            backend.complete(.init(processID: 10, isPlaying: false))
            XCTAssertEqual(backend.playCount, 1)
            XCTAssertFalse(controller.didPauseMedia)
        }
    }
    func testChangedOrAlreadyPlayingTargetIsNotResumed() async {
        await MainActor.run {
            for current in [MediaPlaybackSnapshot(processID: 20, isPlaying: false), .init(processID: 10, isPlaying: true)] {
                let backend = FakeMediaBackend(), controller = MediaPlaybackController(backend: backend)
                controller.pauseIfPlaying()
                backend.complete(.init(processID: 10, isPlaying: true))
                backend.complete(.init(processID: 10, isPlaying: false))
                controller.resumeIfPaused()
                backend.complete(current)
                XCTAssertEqual(backend.playCount, 0)
            }
        }
    }
    func testStoppingDuringQueriesDoesNotCauseLatePause() async {
        await MainActor.run {
            let backend = FakeMediaBackend(), controller = MediaPlaybackController(backend: backend)
            controller.pauseIfPlaying()
            controller.resumeIfPaused()
            backend.complete(.init(processID: 10, isPlaying: true))
            XCTAssertEqual(backend.pauseCount, 0)
            XCTAssertEqual(backend.playCount, 0)
        }
    }
    func testStoppingWhilePauseIsBeingConfirmedCanRestoreIt() async {
        await MainActor.run {
            let backend = FakeMediaBackend(), controller = MediaPlaybackController(backend: backend)
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: true))
            controller.resumeIfPaused()
            backend.complete(.init(processID: 10, isPlaying: false))
            backend.complete(.init(processID: 10, isPlaying: false))
            XCTAssertEqual(backend.pauseCount, 1)
            XCTAssertEqual(backend.playCount, 1)
        }
    }
    func testFailedPauseOrUnverifiedPauseDoesNotPlay() async {
        await MainActor.run {
            let backend = FakeMediaBackend(), controller = MediaPlaybackController(backend: backend)
            backend.pauseSucceeds = false
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: true))
            controller.resumeIfPaused()
            XCTAssertEqual(backend.playCount, 0)
            backend.pauseSucceeds = true
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: true))
            backend.complete(nil)
            controller.resumeIfPaused()
            XCTAssertEqual(backend.playCount, 0)
        }
    }
    func testNewRecordingDuringPendingResumeDefersPlayback() async {
        await MainActor.run {
            let backend = FakeMediaBackend(), controller = MediaPlaybackController(backend: backend)
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: true))
            backend.complete(.init(processID: 10, isPlaying: false))
            controller.resumeIfPaused()
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: false))
            XCTAssertEqual(backend.playCount, 0)
            controller.resumeIfPaused()
            backend.complete(.init(processID: 10, isPlaying: false))
            XCTAssertEqual(backend.playCount, 1)
        }
    }
    func testNewRecordingDuringPauseConfirmationDefersPlayback() async {
        await MainActor.run {
            let backend = FakeMediaBackend(), controller = MediaPlaybackController(backend: backend)
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: true))
            controller.resumeIfPaused()
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: false))
            XCTAssertEqual(backend.playCount, 0)
            controller.resumeIfPaused()
            backend.complete(.init(processID: 10, isPlaying: false))
            XCTAssertEqual(backend.playCount, 1)
        }
    }
    func testPauseConfirmationRetriesWhilePlayerIsStillPlaying() async {
        await MainActor.run {
            let backend = FakeMediaBackend()
            let controller = MediaPlaybackController(backend: backend, scheduleRetry: { $0() })
            controller.pauseIfPlaying()
            backend.complete(.init(processID: 10, isPlaying: true))
            backend.complete(.init(processID: 10, isPlaying: true))
            backend.complete(.init(processID: 10, isPlaying: false))
            controller.resumeIfPaused()
            backend.complete(.init(processID: 10, isPlaying: false))
            XCTAssertEqual(backend.playCount, 1)
        }
    }
}
