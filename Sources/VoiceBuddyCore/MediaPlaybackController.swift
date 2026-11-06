import Foundation

public final class MediaPlaybackController: @unchecked Sendable {
    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (Int32, AnyObject?) -> Bool

    private static let bundle: CFBundle? = {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        let url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, path as CFString, .cfurlposixPathStyle, true)
        guard let url else { return nil }
        return CFBundleCreate(kCFAllocatorDefault, url)
    }()

    private static let sendCommand: MRMediaRemoteSendCommandFunction? = {
        guard let bundle else { return nil }
        guard let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else { return nil }
        return unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFunction.self)
    }()

    public private(set) var didPauseMedia = false

    public init() {}

    public func pauseIfPlaying() {
        didPauseMedia = true
        // kMRPause = 1
        _ = Self.sendCommand?(1, nil)
    }

    public func resumeIfPaused() {
        guard didPauseMedia else { return }
        didPauseMedia = false
        // kMRPlay = 0
        _ = Self.sendCommand?(0, nil)
    }
}
