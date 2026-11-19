import Foundation
import Observation

/// High-frequency streaming HUD state isolated via `@Observable` so meter ticks and partial
/// transcripts only re-render views that read these properties (avoiding global settings redraws).
@MainActor
@Observable
final class LiveHUDState {
    @ObservationIgnored var onRecordingChanged: ((Bool) -> Void)?

    var recording = false {
        didSet {
            if oldValue != recording {
                onRecordingChanged?(recording)
            }
        }
    }
    var level: Float = 0
    var liveTranscript = ""
    var liveTranscriptState = LiveTranscriptState()
    var status = "Ready"
}
