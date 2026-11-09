import CoreML
import FluidAudio
import Foundation

// Parakeet on live sound.
//
// Parakeet reads a finished stretch of sound; it has no live mode. So once
// a second the stretch that is not settled yet is transcribed again:
//
//   sound in  ->  [ unsettled stretch, grows ]  ->  voice detector cuts out
//   the quiet parts  ->  Parakeet on each spoken part  ->  words with times
//   ->  WordAgreement: which words are settled  ->  settled sound is dropped
//
// What is shown is settled text plus the newest pass's unsettled words, so
// a word appears about one pass after it was spoken and may still change
// until it settles.
//
// `ParakeetStreamer` is the pass itself, without a clock, so the probe tool
// can drive it faster than real time. `ParakeetEngine` adds the clock.

public actor ParakeetStreamer {
    public struct PassReport: Sendable {
        public var update: CaptionUpdate
        public var newlySettled: [TimedWord]
        public var provisional: [TimedWord]
        /// Length of the stretch this pass transcribed, seconds.
        public var stretchSeconds: Double
        /// Time the pass took, seconds.
        public var passSeconds: Double
    }

    private static let sampleRate = Int(SystemAudioTap.sampleRate)
    /// Appended after each spoken part: the decoder only lets go of the last
    /// word once it hears what follows.
    private static let tailPadding = [Float](repeating: 0, count: sampleRate)
    private let manager: AsrManager
    private let voiceDetector: VadManager?
    private let decoderLayers: Int
    private let contextSeconds: Double
    private var agreement: WordAgreement

    /// The unsettled stretch. `samples[0]` is sample `firstSample` of the run.
    private var samples: [Float] = []
    private var firstSample = 0
    private var transcribedUpTo = 0
    private var provisional: [TimedWord] = []

    public init(
        encoderComputeUnits: MLComputeUnits = ParakeetModelStore.encoderComputeUnits,
        useVoiceDetector: Bool = true,
        contextSeconds: Double = 3,
        agreement: WordAgreement.Config = .init()
    ) async throws {
        let models = try await ParakeetModelCache.shared.speechModels(
            encoderComputeUnits: encoderComputeUnits)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        decoderLayers = await manager.decoderLayerCount
        voiceDetector = useVoiceDetector ? try await ParakeetModelCache.shared.voiceDetectorModel() : nil
        self.contextSeconds = contextSeconds
        self.agreement = WordAgreement(config: agreement)
    }

    public func append(_ chunk: [Float]) {
        samples.append(contentsOf: chunk)
    }

    /// End of the sound received so far, seconds since the run began.
    public var soundEnd: Double {
        Double(firstSample + samples.count) / Double(Self.sampleRate)
    }

    /// Transcribes the unsettled stretch once. Returns nil when there is
    /// nothing new to do.
    public func pass() async throws -> PassReport? {
        let endSample = firstSample + samples.count
        guard endSample > transcribedUpTo,
              samples.count >= ASRConstants.minimumRequiredSamples(forSampleRate: Self.sampleRate)
        else { return nil }
        let started = Date()
        let stretch = samples
        let stretchStart = firstSample
        let soundEnd = Double(endSample) / Double(Self.sampleRate)

        var words: [TimedWord] = []
        var spoken = true
        var parts: [Range<Int>] = [0..<stretch.count]
        if let voiceDetector {
            let segments = try await voiceDetector.segmentSpeech(stretch)
            parts = segments.compactMap { segment in
                let start = max(0, segment.startSample(sampleRate: Self.sampleRate))
                let end = min(stretch.count, segment.endSample(sampleRate: Self.sampleRate))
                return end > start ? start..<end : nil
            }
            spoken = !parts.isEmpty
        }
        for part in parts
        where part.count >= ASRConstants.minimumRequiredSamples(forSampleRate: Self.sampleRate) {
            var state = TdtDecoderState.make(decoderLayers: decoderLayers)
            let result = try await manager.transcribe(
                Array(stretch[part]) + Self.tailPadding, decoderState: &state)
            let offset = Double(stretchStart + part.lowerBound) / Double(Self.sampleRate)
            words += Self.words(from: result.tokenTimings ?? [], offset: offset)
        }
        transcribedUpTo = endSample
        // The stretch begins `contextSeconds` before the cut, so the model
        // hears how the sentence began. Words from that part are settled
        // already and are not counted again.
        let cut = agreement.cutTime
        words.removeAll { ($0.start + $0.end) / 2 < cut }

        var result = agreement.add(pass: words, soundEnd: soundEnd)
        if !spoken {
            // No voice in the whole stretch: keep one second in case a word
            // is just beginning, let the rest go.
            result.cutTime = agreement.advanceCut(to: soundEnd - 1)
        }
        provisional = result.provisional
        dropSound(before: result.cutTime - contextSeconds)

        return PassReport(
            update: CaptionUpdate(newlySettled: Self.text(result.newlySettled),
                                  provisional: Self.text(result.provisional)),
            newlySettled: result.newlySettled,
            provisional: result.provisional,
            stretchSeconds: Double(stretch.count) / Double(Self.sampleRate),
            passSeconds: Date().timeIntervalSince(started))
    }

    /// The sound has stopped: what is still provisional will not change any
    /// more, so it counts as settled and the stretch is cleared.
    public func settleAll() -> CaptionUpdate {
        let update = CaptionUpdate(newlySettled: Self.text(provisional))
        provisional = []
        firstSample += samples.count
        samples.removeAll(keepingCapacity: true)
        transcribedUpTo = firstSample
        agreement.reset(at: Double(firstSample) / Double(Self.sampleRate))
        return update
    }

    public func cleanup() async {
        await manager.cleanup()
    }

    private static func text(_ words: [TimedWord]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    private func dropSound(before time: Double) {
        let cutSample = Int(time * Double(Self.sampleRate))
        let drop = min(samples.count, cutSample - firstSample)
        guard drop > 0 else { return }
        samples.removeFirst(drop)
        firstSample += drop
    }

    /// Parakeet's tokens are word pieces; a piece that begins with a space
    /// begins a word. Before a number the space comes as a piece of its own.
    static func words(from tokens: [TokenTiming], offset: Double) -> [TimedWord] {
        var words: [TimedWord] = []
        var spaceBefore = true
        for token in tokens {
            let piece = token.token
            let beginsWord = spaceBefore || piece.hasPrefix(" ") || piece.hasPrefix("▁")
            let text = piece.trimmingCharacters(in: CharacterSet(charactersIn: " ▁"))
            guard !text.isEmpty else {
                spaceBefore = true
                continue
            }
            spaceBefore = false
            if beginsWord {
                words.append(TimedWord(text: text, start: token.startTime + offset,
                                       end: token.endTime + offset))
            } else {
                words[words.count - 1].text += text
                words[words.count - 1].end = token.endTime + offset
            }
        }
        return words
    }
}

public final class ParakeetEngine: CaptionEngine, @unchecked Sendable {
    public var onUpdate: (@Sendable (CaptionUpdate) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    /// Seconds between the starts of two passes.
    private static let passInterval = 1.0
    /// Sound pause after which the last words count as settled.
    private static let settleAfterQuiet = 2.0

    private var streamer: ParakeetStreamer?
    private var loop: Task<Void, Never>?
    private let lock = NSLock()
    private var pending: [Float] = []

    public init() {}

    public func start() async throws {
        let streamer = try await ParakeetStreamer()
        self.streamer = streamer
        loop = Task { [weak self] in
            var lastSound = Date()
            var quietSettled = true
            while !Task.isCancelled {
                let started = Date()
                guard let self else { return }
                let chunk = self.takePending()
                do {
                    if !chunk.isEmpty {
                        await streamer.append(chunk)
                        lastSound = started
                        quietSettled = false
                    }
                    if let report = try await streamer.pass() {
                        self.onUpdate?(report.update)
                    } else if !quietSettled,
                              started.timeIntervalSince(lastSound) > Self.settleAfterQuiet {
                        quietSettled = true
                        self.onUpdate?(await streamer.settleAll())
                    }
                } catch {
                    if !Task.isCancelled { self.onError?(error) }
                    return
                }
                let wait = Self.passInterval - Date().timeIntervalSince(started)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            }
        }
    }

    public func feed(_ samples: [Float]) {
        lock.lock()
        pending.append(contentsOf: samples)
        lock.unlock()
    }

    public func stop() async {
        loop?.cancel()
        await loop?.value
        loop = nil
        await streamer?.cleanup()
        streamer = nil
        _ = takePending()
    }

    private func takePending() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let chunk = pending
        pending.removeAll(keepingCapacity: true)
        return chunk
    }
}
