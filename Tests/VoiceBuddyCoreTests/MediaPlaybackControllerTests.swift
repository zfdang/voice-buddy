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
    func testFallbackUsedOnlyWhenSystemCannotIdentifyAPlayer() async {
        await MainActor.run {
            let primary = FakeMediaBackend(), fallback = FakeMediaBackend()
            let backend = FallbackMediaPlaybackBackend(primary: primary, fallback: fallback)
            var result: MediaPlaybackSnapshot?
            backend.snapshot { result = $0 }
            primary.complete(.init(processID: 0, isPlaying: false))
            fallback.complete(.init(processID: 10, isPlaying: true))
            XCTAssertEqual(result, .init(processID: 10, isPlaying: true))
            XCTAssertTrue(backend.pause())
            XCTAssertEqual(fallback.pauseCount, 1)
            backend.snapshot { result = $0 }
            primary.complete(.init(processID: 20, isPlaying: false))
            XCTAssertEqual(result, .init(processID: 20, isPlaying: false))
            XCTAssertTrue(fallback.pending.isEmpty)
        }
    }
    func testStaleFallbackQueryCannotChangeCommandTarget() async {
        await MainActor.run {
            let primary = FakeMediaBackend(), fallback = FakeMediaBackend()
            let backend = FallbackMediaPlaybackBackend(primary: primary, fallback: fallback)
            backend.snapshot { _ in }
            primary.complete(nil)
            backend.snapshot { _ in }
            primary.complete(.init(processID: 20, isPlaying: true))
            fallback.complete(.init(processID: 10, isPlaying: true))
            XCTAssertTrue(backend.pause())
            XCTAssertEqual(primary.pauseCount, 1)
            XCTAssertEqual(fallback.pauseCount, 0)
        }
    }
    func testFallbackPlayerIsPausedAndResumedOnlyWhenOriginallyPlaying() async {
        await MainActor.run {
            let primary = FakeMediaBackend(), fallback = FakeMediaBackend()
            let backend = FallbackMediaPlaybackBackend(primary: primary, fallback: fallback)
            let controller = MediaPlaybackController(backend: backend)
            controller.pauseIfPlaying()
            primary.complete(nil)
            fallback.complete(.init(processID: 10, isPlaying: true))
            XCTAssertEqual(fallback.pauseCount, 1)
            primary.complete(nil)
            fallback.complete(.init(processID: 10, isPlaying: false))
            controller.resumeIfPaused()
            primary.complete(nil)
            fallback.complete(.init(processID: 10, isPlaying: false))
            XCTAssertEqual(fallback.playCount, 1)
        }
    }
    func testFallbackPlayerAlreadyPausedIsNeverStarted() async {
        await MainActor.run {
            let primary = FakeMediaBackend(), fallback = FakeMediaBackend()
            let controller = MediaPlaybackController(backend: FallbackMediaPlaybackBackend(primary: primary, fallback: fallback))
            controller.pauseIfPlaying()
            primary.complete(nil)
            fallback.complete(.init(processID: 10, isPlaying: false))
            controller.resumeIfPaused()
            XCTAssertEqual(fallback.pauseCount, 0)
            XCTAssertEqual(fallback.playCount, 0)
        }
    }
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
