import Foundation

// CaptionText: turns the engines' stream of settled and provisional text
// into the lines the caption bar shows.
//
// Roll-up captions: words fill a line from the left; when the bottom line
// is full the top line leaves, the bottom line moves up and new words
// start a fresh bottom line. Lines are always broken the same way, counted
// from the first word of the top line, so text that is on screen never
// re-wraps while new words arrive.

public struct CaptionText {
    /// Lines the bar has room for.
    public let lineCount: Int
    /// Settled words from the first word of the top line on.
    private var settled: [String] = []
    private var provisional: [String] = []

    public init(lineCount: Int = 2) {
        self.lineCount = lineCount
    }

    public var isEmpty: Bool { settled.isEmpty && provisional.isEmpty }

    public mutating func apply(_ update: CaptionUpdate) {
        settled += update.newlySettled.split(whereSeparator: \.isWhitespace).map(String.init)
        provisional = update.provisional.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public mutating func clear() {
        settled = []
        provisional = []
    }

    /// The lines to show, oldest first, at most `lineCount`. `fits` says
    /// whether a string fits into one line of the bar.
    public mutating func lines(fits: (String) -> Bool) -> [String] {
        var lines: [[String]] = []
        // For each line, how many of its words are settled.
        var settledInLine: [Int] = []
        for (index, word) in (settled + provisional).enumerated() {
            let isSettled = index < settled.count
            if var last = lines.last, fits((last + [word]).joined(separator: " ")) {
                last.append(word)
                lines[lines.count - 1] = last
                if isSettled { settledInLine[settledInLine.count - 1] += 1 }
            } else {
                // A word wider than the bar gets a line of its own.
                lines.append([word])
                settledInLine.append(isSettled ? 1 : 0)
            }
        }
        // Lines that scrolled out are forgotten for good once all their
        // words are settled; until then they could still change.
        var scrolledOut = max(0, lines.count - lineCount)
        var forget = 0
        for index in 0..<scrolledOut {
            guard settledInLine[index] == lines[index].count else { break }
            forget += lines[index].count
        }
        settled.removeFirst(forget)
        scrolledOut = max(0, lines.count - lineCount)
        return lines.dropFirst(scrolledOut).map { $0.joined(separator: " ") }
    }
}
