import XCTest
@testable import CaptionCore

final class WordAgreementTests: XCTestCase {
    /// Words one second apart: word n spans n...n+0.5.
    private func words(_ texts: [String], from start: Double = 0) -> [TimedWord] {
        texts.enumerated().map { index, text in
            TimedWord(text: text, start: start + Double(index), end: start + Double(index) + 0.5)
        }
    }

    func testNothingSettlesOnTheFirstPass() {
        var agreement = WordAgreement()
        let result = agreement.add(pass: words(["das", "ist", "ein", "test"]), soundEnd: 4)
        XCTAssertEqual(result.newlySettled, [])
        XCTAssertEqual(result.provisional.map(\.text), ["das", "ist", "ein", "test"])
        XCTAssertEqual(result.cutTime, 0)
    }

    func testWordsSettleAfterTwoEqualPassesExceptTheNewestTwo() {
        var agreement = WordAgreement()
        _ = agreement.add(pass: words(["das", "ist", "ein", "test"]), soundEnd: 4)
        let result = agreement.add(pass: words(["das", "ist", "ein", "test", "hier"]), soundEnd: 5)
        // 5 words, newest 2 held back, of the other 3 all were seen twice.
        XCTAssertEqual(result.newlySettled.map(\.text), ["das", "ist", "ein"])
        XCTAssertEqual(result.provisional.map(\.text), ["test", "hier"])
        // Cut halfway between "ein" (ends 2.5) and "test" (starts 3).
        XCTAssertEqual(result.cutTime, 2.75, accuracy: 0.001)
    }

    func testCaseAndPunctuationDoNotBreakAgreement() {
        var agreement = WordAgreement()
        _ = agreement.add(pass: words(["Das", "Kabel,", "ist", "da"]), soundEnd: 4)
        let result = agreement.add(pass: words(["das", "Kabel", "ist", "da"]), soundEnd: 4.5)
        XCTAssertEqual(result.newlySettled.map(\.text), ["das", "Kabel"])
    }

    func testAChangedWordHoldsBackEverythingAfterIt() {
        var agreement = WordAgreement()
        _ = agreement.add(pass: words(["ein", "so", "Kabel", "ist", "da"]), soundEnd: 5)
        let result = agreement.add(
            pass: words(["ein", "langes", "Kabel", "ist", "da", "und"]), soundEnd: 6)
        XCTAssertEqual(result.newlySettled.map(\.text), ["ein"])
        XCTAssertEqual(result.provisional.map(\.text), ["langes", "Kabel", "ist", "da", "und"])
    }

    func testAfterACutTheNextPassStartsAtTheUnsettledWords() {
        var agreement = WordAgreement()
        _ = agreement.add(pass: words(["a", "b", "c", "d"]), soundEnd: 4)
        _ = agreement.add(pass: words(["a", "b", "c", "d"]), soundEnd: 4.5)   // settles a, b
        // The caller dropped the sound of a and b; the pass begins with c.
        let result = agreement.add(pass: words(["c", "d", "e", "f"], from: 2), soundEnd: 6)
        // c and d were seen in both earlier passes and again now.
        XCTAssertEqual(result.newlySettled.map(\.text), ["c", "d"])
        XCTAssertEqual(result.provisional.map(\.text), ["e", "f"])
    }

    func testOldUnsettledSoundIsSettledByForce() {
        var config = WordAgreement.Config()
        config.maxUnsettledSeconds = 3
        var agreement = WordAgreement(config: config)
        // First pass, nothing agreed yet, but "a" and "b" end more than 3 s
        // before the end of the sound.
        let result = agreement.add(pass: words(["a", "b", "c", "d", "e"]), soundEnd: 5)
        XCTAssertEqual(result.newlySettled.map(\.text), ["a", "b"])
    }

    func testLongStretchWithoutWordsIsLetGo() {
        var agreement = WordAgreement()
        let result = agreement.add(pass: [], soundEnd: 20)
        XCTAssertEqual(result.cutTime, 10, accuracy: 0.001)   // 20 - 10
    }

    func testAdvanceCutOnlyWhenNothingIsUnsettled() {
        var agreement = WordAgreement()
        XCTAssertEqual(agreement.advanceCut(to: 5), 5)
        _ = agreement.add(pass: words(["a", "b", "c"], from: 6), soundEnd: 9)
        XCTAssertEqual(agreement.advanceCut(to: 8), 5)
    }
}
