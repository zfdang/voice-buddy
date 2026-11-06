import Foundation

public struct MediaPlaybackSnapshot: Equatable {
    public let processID: Int32
    public let isPlaying: Bool
    public init(processID: Int32, isPlaying: Bool) {
        self.processID = processID
        self.isPlaying = isPlaying
    }
}

public enum MediaPlaybackEvent: String {
    case checkStarted, notPlayingOrUnavailable, pauseSent, pauseFailed, pauseUnverified, pauseConfirmed
    case resumeSkipped, resumeSent, resumeFailed
}

@MainActor public protocol MediaPlaybackBackend {
    func snapshot(completion: @escaping (MediaPlaybackSnapshot?) -> Void)
    func pause() -> Bool
    func play() -> Bool
}

/// All decisions run on the main actor. Unknown or stale playback state never starts playback.
@MainActor public final class MediaPlaybackController {
    private enum Phase { case idle, checking, verifyingPause(Int32), paused(Int32), checkingResume(Int32) }
    private let backend: any MediaPlaybackBackend
    private let onEvent: (MediaPlaybackEvent) -> Void
    private let scheduleRetry: @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void
    private var token: UUID?
    private var phase: Phase = .idle
    private var ended = false
    public private(set) var didPauseMedia = false

    public init(onEvent: @escaping (MediaPlaybackEvent) -> Void = { _ in }) {
        backend = SystemMediaPlaybackBackend(); self.onEvent = onEvent
        scheduleRetry = { action in DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action) }
    }
    public init(backend: any MediaPlaybackBackend, onEvent: @escaping (MediaPlaybackEvent) -> Void = { _ in }, scheduleRetry: @escaping @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void = { action in DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action) }) {
        self.backend = backend; self.onEvent = onEvent; self.scheduleRetry = scheduleRetry
    }

    public func pauseIfPlaying() {
        // A new recording may begin while the preceding pause or resume query
        // is still in flight. Carry its ownership forward rather than playing
        // audio during the new recording or losing the eventual resume.
        if ended, token != nil {
            switch phase {
            case .verifyingPause:
                ended = false
                return
            case .checkingResume(let pid):
                ended = false
                phase = .paused(pid)
                return
            case .idle, .checking, .paused:
                break
            }
        }
        let id = UUID()
        token = id; phase = .checking; ended = false; didPauseMedia = false
        onEvent(.checkStarted)
        backend.snapshot { [weak self] snapshot in
            guard let self, self.token == id, !self.ended, case .checking = self.phase else { return }
            guard let snapshot, snapshot.processID > 0, snapshot.isPlaying else {
                self.onEvent(.notPlayingOrUnavailable)
                self.token = nil; self.phase = .idle
                return
            }
            guard self.backend.pause() else {
                self.onEvent(.pauseFailed); self.token = nil; self.phase = .idle
                return
            }
            self.onEvent(.pauseSent)
            let pid = snapshot.processID
            self.phase = .verifyingPause(pid)
            self.verifyPause(id: id, pid: pid, attemptsRemaining: 3)
        }
    }

    private func verifyPause(id: UUID, pid: Int32, attemptsRemaining: Int) {
        backend.snapshot { [weak self] current in
            guard let self, self.token == id, case .verifyingPause(let expected) = self.phase, expected == pid else { return }
            if let current, current.processID == pid, current.isPlaying, attemptsRemaining > 1 {
                self.scheduleRetry { [weak self] in
                    guard let self, self.token == id, case .verifyingPause = self.phase else { return }
                    self.verifyPause(id: id, pid: pid, attemptsRemaining: attemptsRemaining - 1)
                }
                return
            }
            guard let current, current.processID == pid, !current.isPlaying else {
                self.onEvent(.pauseUnverified); self.token = nil; self.phase = .idle
                return
            }
            self.onEvent(.pauseConfirmed)
            self.phase = .paused(pid); self.didPauseMedia = true
            if self.ended { self.resumeVerified(id: id, pid: pid) }
        }
    }

    public func resumeIfPaused() {
        guard let id = token, !ended else { return }
        ended = true
        switch phase {
        case .checking:
            token = nil; phase = .idle
        case .paused(let pid):
            resumeVerified(id: id, pid: pid)
        case .idle, .verifyingPause, .checkingResume:
            break
        }
    }

    private func resumeVerified(id: UUID, pid: Int32) {
        phase = .checkingResume(pid)
        backend.snapshot { [weak self] current in
            guard let self, self.token == id, case .checkingResume(let expected) = self.phase, expected == pid else { return }
            if let current, current.processID == pid, !current.isPlaying {
                self.onEvent(self.backend.play() ? .resumeSent : .resumeFailed)
            } else { self.onEvent(.resumeSkipped) }
            self.didPauseMedia = false; self.token = nil; self.phase = .idle
        }
    }
}

/// MediaRemote is not a public API. If its query is unavailable or times out, no command is sent.
@MainActor private final class SystemMediaPlaybackBackend: MediaPlaybackBackend {
    private typealias Command = @convention(c) (Int32, AnyObject?) -> Bool
    private typealias PlayingQuery = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias PIDQuery = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private let bundle: CFBundle?
    init() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL)
    }
    private func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let bundle, let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
    func snapshot(completion: @escaping (MediaPlaybackSnapshot?) -> Void) {
        guard let playing = function("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: PlayingQuery.self),
              let pid = function("MRMediaRemoteGetNowPlayingApplicationPID", as: PIDQuery.self) else { completion(nil); return }
        var completed = false
        pid(.main) { firstPID in
            guard !completed else { return }
            playing(.main) { isPlaying in
                guard !completed else { return }
                pid(.main) { secondPID in
                    guard !completed else { return }
                    completed = true
                    guard firstPID == secondPID else { completion(nil); return }
                    completion(MediaPlaybackSnapshot(processID: firstPID, isPlaying: isPlaying))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard !completed else { return }
            completed = true; completion(nil)
        }
    }
    func pause() -> Bool { function("MRMediaRemoteSendCommand", as: Command.self)?(1, nil) ?? false }
    func play() -> Bool { function("MRMediaRemoteSendCommand", as: Command.self)?(0, nil) ?? false }
}
