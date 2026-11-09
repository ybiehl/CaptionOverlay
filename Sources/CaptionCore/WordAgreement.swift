import Foundation

// WordAgreement: decides which words of a repeatedly re-transcribed stretch
// of sound are settled.
//
// Parakeet is a whole-file model. To caption live sound, the same unsettled
// stretch is transcribed again every second as it grows. The newest words
// change between passes (the model has not heard the end of the word or the
// sentence yet); the older ones stop changing. A word is settled once it
// came out the same in `passesNeeded` passes in a row. Settled words are
// never transcribed again: the caller drops the sound before `cutTime`.
//
// The method (re-transcribe, compare the leading words of consecutive
// passes) is the one VoiceInk uses for dictation; this is our own code for
// it, with rules for captions: settle early and often, because a caption
// reader gains nothing from a word that is held back, and a long unsettled
// stretch makes every pass slower.

/// A word with its place on the timeline of the running sound, in seconds.
public struct TimedWord: Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }

    /// What two passes are compared by: letters and digits only, lowercased,
    /// so "Kabel," and "kabel" agree.
    var key: String {
        String(String.UnicodeScalarView(
            text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
}

public struct WordAgreement {
    public struct Config: Sendable {
        /// Passes in a row a word must survive unchanged.
        public var passesNeeded = 2
        /// The newest words of a pass are never settled: the model revises
        /// them most once it hears what follows.
        public var heldBackWords = 2
        /// Unsettled sound beyond this is settled by force, oldest words
        /// first, so a pass (this plus the context the caller keeps before
        /// the cut) never outgrows the model's 15 s window.
        public var maxUnsettledSeconds = 10.0

        public init() {}
    }

    public struct Result: Sendable, Equatable {
        /// Words that became settled in this pass, in order.
        public var newlySettled: [TimedWord]
        /// The words after them, as heard in this pass.
        public var provisional: [TimedWord]
        /// Sound before this time is finished with.
        public var cutTime: Double
    }

    public let config: Config
    /// Sound before this time is finished with.
    public private(set) var cutTime: Double = 0
    /// The unsettled words of the previous pass, and for each how many
    /// passes in a row it has been there unchanged.
    private var previous: [(word: TimedWord, streak: Int)] = []

    public init(config: Config = Config()) {
        self.config = config
    }

    /// One pass. `words` are everything heard from `cutTime` to `soundEnd`,
    /// with times on the timeline of the running sound.
    public mutating func add(pass words: [TimedWord], soundEnd: Double) -> Result {
        // Streaks: a word keeps counting only while every word before it
        // also matched, because a changed word shifts what follows.
        var current: [(word: TimedWord, streak: Int)] = []
        var matching = true
        for (index, word) in words.enumerated() {
            if matching, index < previous.count, previous[index].word.key == word.key {
                current.append((word, previous[index].streak + 1))
            } else {
                matching = false
                current.append((word, 1))
            }
        }

        // Settle the leading words that survived long enough, except the
        // newest few.
        let eligible = max(0, current.count - config.heldBackWords)
        var settleCount = 0
        while settleCount < eligible, current[settleCount].streak >= config.passesNeeded {
            settleCount += 1
        }
        // Force: whatever starts more than `maxUnsettledSeconds` before the
        // end of the sound goes, agreed or not.
        let forceBefore = soundEnd - config.maxUnsettledSeconds
        while settleCount < current.count, current[settleCount].word.end <= forceBefore {
            settleCount += 1
        }

        let settled = current.prefix(settleCount).map(\.word)
        let rest = Array(current.dropFirst(settleCount))
        if let last = settled.last {
            // Cut between the last settled word and the first unsettled one,
            // so neither loses its edge.
            let next = rest.first?.word.start ?? last.end
            cutTime = max(cutTime, (last.end + max(last.end, next)) / 2)
        }
        if rest.isEmpty, soundEnd - cutTime > config.maxUnsettledSeconds {
            // Nothing heard for a long stretch (music, noise): let it go.
            cutTime = soundEnd - config.maxUnsettledSeconds
        }
        previous = rest
        return Result(newlySettled: settled, provisional: rest.map(\.word), cutTime: cutTime)
    }

    /// The caller knows the sound before `time` holds no speech. Only moves
    /// forward, and only while no unsettled words would be cut off.
    public mutating func advanceCut(to time: Double) -> Double {
        if previous.isEmpty { cutTime = max(cutTime, time) }
        return cutTime
    }

    /// Start over with sound that begins at `time`.
    public mutating func reset(at time: Double = 0) {
        cutTime = time
        previous = []
    }
}
