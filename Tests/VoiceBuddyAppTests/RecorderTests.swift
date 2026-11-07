import XCTest
@testable import VoiceBuddyApp

final class RecorderTests: XCTestCase {
    func testUnavailableDeviceFailsWithoutStarting() {
        XCTAssertThrowsError(try Recorder().start(deviceUID: "voice-buddy-nonexistent-test-device"))
    }

    func testSelectedMicrophoneCaptureWhenRequested() throws {
        guard let name = ProcessInfo.processInfo.environment["VOICE_BUDDY_TEST_MICROPHONE"] else {
            throw XCTSkip("Set VOICE_BUDDY_TEST_MICROPHONE to test a connected input device")
        }
        let uid = try XCTUnwrap(AudioDevices.devices().first { $0.1 == name }?.0)
        let recorder = Recorder()
        try recorder.start(deviceUID: uid)
        let duration = Double(ProcessInfo.processInfo.environment["VOICE_BUDDY_TEST_DURATION"] ?? "5") ?? 5
        Thread.sleep(forTimeInterval: duration)
        let result = recorder.stop()
        XCTAssertGreaterThan(result.diagnostics.callbacks, 0)
        XCTAssertGreaterThan(Double(result.samples.count), duration * 16000 * 0.8, "Capture must remain active for most of the recording")
        XCTAssertEqual(result.diagnostics.conversionFailures, 0)
    }
}
