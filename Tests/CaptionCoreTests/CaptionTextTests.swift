import XCTest
@testable import CaptionCore

final class CaptionTextTests: XCTestCase {
    /// A line holds 10 characters.
    private let fits: (String) -> Bool = { $0.count <= 10 }

    func testWordsFillLinesFromTheLeft() {
        var text = CaptionText()
        text.apply(CaptionUpdate(newlySettled: "eins zwei drei"))
        XCTAssertEqual(text.lines(fits: fits), ["eins zwei", "drei"])
    }

    func testProvisionalTextFollowsSettledText() {
        var text = CaptionText()
        text.apply(CaptionUpdate(newlySettled: "eins", provisional: "zwei drei"))
        XCTAssertEqual(text.lines(fits: fits), ["eins zwei", "drei"])
        // The next guess replaces the previous one.
        text.apply(CaptionUpdate(provisional: "zwo"))
        XCTAssertEqual(text.lines(fits: fits), ["eins zwo"])
    }

    func testTopLineLeavesWhenAThirdLineBegins() {
        var text = CaptionText()
        text.apply(CaptionUpdate(newlySettled: "eins zwei drei vier fuenf"))
        // "eins zwei" / "drei vier" / "fuenf" -> the first line scrolls out.
        XCTAssertEqual(text.lines(fits: fits), ["drei vier", "fuenf"])
    }

    func testLinesOnScreenDoNotRewrapWhenWordsArrive() {
        var text = CaptionText()
        text.apply(CaptionUpdate(newlySettled: "eins zwei drei vier fuenf"))
        _ = text.lines(fits: fits)
        text.apply(CaptionUpdate(newlySettled: "x"))
        XCTAssertEqual(text.lines(fits: fits), ["drei vier", "fuenf x"])
    }

    func testAScrolledOutLineWithProvisionalWordsCanStillChange() {
        var text = CaptionText()
        text.apply(CaptionUpdate(provisional: "eins zwei drei vier fuenf"))
        XCTAssertEqual(text.lines(fits: fits), ["drei vier", "fuenf"])
        // Nothing was settled, so a shorter guess brings the start back.
        text.apply(CaptionUpdate(provisional: "eins zwei"))
        XCTAssertEqual(text.lines(fits: fits), ["eins zwei"])
    }

    func testAWordWiderThanTheBarGetsItsOwnLine() {
        var text = CaptionText()
        text.apply(CaptionUpdate(newlySettled: "a Donaudampfschiff b"))
        XCTAssertEqual(text.lines(fits: fits), ["Donaudampfschiff", "b"])
    }

    func testClear() {
        var text = CaptionText()
        text.apply(CaptionUpdate(newlySettled: "eins", provisional: "zwei"))
        text.clear()
        XCTAssertTrue(text.isEmpty)
        XCTAssertEqual(text.lines(fits: fits), [])
    }
}
