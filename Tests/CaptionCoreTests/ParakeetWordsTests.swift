import FluidAudio
import XCTest
@testable import CaptionCore

final class ParakeetWordsTests: XCTestCase {
    private func token(_ text: String, _ start: Double) -> TokenTiming {
        TokenTiming(token: text, tokenId: 0, startTime: start, endTime: start + 0.1, confidence: 1)
    }

    func testPiecesJoinIntoWords() {
        let words = ParakeetStreamer.words(
            from: [token(" Unter", 0), token("titel", 0.1), token(" an", 0.3), token(".", 0.4)],
            offset: 10)
        XCTAssertEqual(words.map(\.text), ["Untertitel", "an."])
        XCTAssertEqual(words[0].start, 10, accuracy: 0.001)
        XCTAssertEqual(words[0].end, 10.2, accuracy: 0.001)
    }

    func testASpacePieceOnItsOwnBeginsTheNextWord() {
        // Numbers come as: "alten", " ", "5", "k".
        let words = ParakeetStreamer.words(
            from: [token(" alten", 0), token(" ", 0.2), token("5", 0.3), token("k", 0.4),
                   token(" iMac", 0.6)],
            offset: 0)
        XCTAssertEqual(words.map(\.text), ["alten", "5k", "iMac"])
    }
}
