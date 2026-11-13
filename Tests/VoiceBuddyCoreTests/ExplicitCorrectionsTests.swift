import XCTest
@testable import VoiceBuddyCore

final class ExplicitCorrectionsTests: XCTestCase {
    let input = "今天下午三点钟，啊不对，是两点钟，在三帆中学的明远校区，呃开家长会。希望啊，那个各位家长能够准时到。"
    func testCorrectedHourPreservesContextAndPlace() {
        XCTAssertEqual(ExplicitCorrections.resolve(input), "今天下午两点钟，在三帆中学的明远校区，呃开家长会。希望啊，那个各位家长能够准时到。")
        XCTAssertEqual(ExplicitCorrections.resolve("今天下午三点，不对，明天上午两点开会"), "明天上午两点开会")
    }
    func testChainedCorrectionsAndWeekdays() {
        XCTAssertEqual(ExplicitCorrections.resolve("周三不对周四下午三点不对两点不对一点开会"), "周四下午一点开会")
    }
    func testAlternativesAndOrdinaryNegationStayUntouched() {
        for text in ["周三或周四开会", "不是三点，是两点", "那三点不对的地方要改", "三点半，不对，两点半开会"] {
            XCTAssertEqual(ExplicitCorrections.resolve(text), text)
        }
    }
    func testRejectsLostOrReintroducedCorrectedValues() {
        XCTAssertNil(ExplicitCorrections.unsafeReason("今天下午两点在三帆中学明远校区开家长会。", original: input))
        XCTAssertNil(ExplicitCorrections.unsafeReason("今天14:00在三帆中学明远校区开家长会。", original: input))
        XCTAssertNotNil(ExplicitCorrections.unsafeReason("今天下午三点开家长会。", original: input))
        XCTAssertNotNil(ExplicitCorrections.unsafeReason("三点即两点开家长会。", original: input))
        XCTAssertNotNil(ExplicitCorrections.unsafeReason("下午两点开家长会。", original: input))
        XCTAssertNotNil(ExplicitCorrections.unsafeReason("周三开会", original: "周三不对周四开会"))
    }
}

final class RefinementContentGuardTests: XCTestCase {
    func testMeetingOmissionIsDetectedWithoutDependingOnTheExampleTime() {
        let source = "明天上午九点，在学校开家长会，请家长准时到。"
        XCTAssertTrue(RefinementContentGuard.missingNouns(in: "明天上午九点，在学校，请家长准时到。", original: source).contains("家长会"))
        XCTAssertTrue(RefinementContentGuard.missingNouns(in: "明天上午九点在学校召开家长会，请家长准时到。", original: source).isEmpty)
    }
}
