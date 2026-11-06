import XCTest
@testable import VoiceBuddyApp

final class CaptureDiagnosticsTests: XCTestCase {
    func testDistinguishesMissingCallbacksAndConversionOutcomes() {
        var stats = CaptureDiagnostics()
        XCTAssertEqual(stats.callbacks, 0)
        stats.record(inputFrames: 100, outputFrames: 0, allocated: false, conversionFailed: false, errorCode: nil)
        stats.record(inputFrames: 100, outputFrames: 0, allocated: true, conversionFailed: true, errorCode: -50)
        stats.record(inputFrames: 100, outputFrames: 0, allocated: true, conversionFailed: false, errorCode: nil)
        stats.record(inputFrames: 100, outputFrames: 80, allocated: true, conversionFailed: false, errorCode: nil)
        XCTAssertEqual(stats.callbacks, 4)
        XCTAssertEqual(stats.inputFrames, 400)
        XCTAssertEqual(stats.outputFrames, 80)
        XCTAssertEqual(stats.allocationFailures, 1)
        XCTAssertEqual(stats.conversionFailures, 1)
        XCTAssertEqual(stats.emptyOutputBuffers, 1)
        XCTAssertEqual(stats.lastConversionErrorCode, -50)
    }

    func testStoppingWithoutStartingReturnsEmptyCapture() {
        let capture = Recorder().stop()
        XCTAssertTrue(capture.samples.isEmpty)
        XCTAssertEqual(capture.diagnostics.callbacks, 0)
    }
}
