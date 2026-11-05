import Foundation
import MediaRemoteAdapter
import AppKit

@MainActor
final class MediaPlaybackController {
    private let adapter = MediaController()
    private var didPauseMedia = false

    func pauseIfPlaying() {
        didPauseMedia = true
        adapter.pause()
    }

    func resumeIfPaused() {
        guard didPauseMedia else { return }
        didPauseMedia = false
        adapter.play()
    }
}
