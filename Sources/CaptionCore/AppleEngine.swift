import AVFoundation
import Foundation
import Speech

// Apple's on-device transcriber (SpeechAnalyzer + SpeechTranscriber,
// macOS 26). Built for live sound: it reports provisional ("volatile")
// text while a phrase is spoken and replaces it with a final result.
//
// One fixed language per run; it does not detect the language. With the
// wrong language set it produces garbled text, not an error.

public final class AppleEngine: CaptionEngine, @unchecked Sendable {
    public var onUpdate: (@Sendable (CaptionUpdate) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    public enum EngineError: Error, CustomStringConvertible {
        case languageNotSupported(String)
        case noAudioFormat
        public var description: String {
            switch self {
            case .languageNotSupported(let id): return "language \(id) is not supported"
            case .noAudioFormat: return "the transcriber offers no audio format"
            }
        }
    }

    private let locale: Locale
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private let tapFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: SystemAudioTap.sampleRate,
        channels: 1, interleaved: false)!
    private let lock = NSLock()

    public init(locale: Locale) {
        self.locale = locale
    }

    /// Languages the transcriber can do, sorted by their name in the
    /// current interface language.
    public static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted {
            name(of: $0).localizedCaseInsensitiveCompare(name(of: $1)) == .orderedAscending
        }
    }

    public static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// True when the language's model is on this Mac already.
    public static func isInstalled(_ locale: Locale) async -> Bool {
        let wanted = locale.identifier(.bcp47)
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == wanted }
    }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// Lets macOS download the language if it is missing. `progress` gets
    /// 0...1. Returns at once when it is installed.
    public static func install(
        _ locale: Locale, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [makeTranscriber(locale)]) else { return }
        let observation = request.progress.observe(\.fractionCompleted) { value, _ in
            progress(value.fractionCompleted)
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
    }

    public func start() async throws {
        let wanted = locale.identifier(.bcp47)
        guard await SpeechTranscriber.supportedLocales.contains(where: {
            $0.identifier(.bcp47) == wanted
        }) else { throw EngineError.languageNotSupported(locale.identifier) }

        let transcriber = Self.makeTranscriber(locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]) else { throw EngineError.noAudioFormat }
        let (sequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        lock.withLock {
            analyzerFormat = format
            converter = AVAudioConverter(from: tapFormat, to: format)
            input = continuation
            self.analyzer = analyzer
        }

        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.onUpdate?(result.isFinal
                        ? CaptionUpdate(newlySettled: text)
                        : CaptionUpdate(provisional: text))
                }
            } catch {
                if !Task.isCancelled { self?.onError?(error) }
            }
        }
        try await analyzer.start(inputSequence: sequence)
    }

    public func feed(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard let input, let converter, let analyzerFormat, !samples.isEmpty,
              let source = AVAudioPCMBuffer(
                pcmFormat: tapFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            source.floatChannelData![0].update(from: pointer.baseAddress!, count: samples.count)
        }
        let ratio = analyzerFormat.sampleRate / tapFormat.sampleRate
        guard let output = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: AVAudioFrameCount(Double(samples.count) * ratio) + 32)
        else { return }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return }
        input.yield(AnalyzerInput(buffer: output))
    }

    public func stop() async {
        let (input, analyzer) = lock.withLock {
            let current = (self.input, self.analyzer)
            self.input = nil
            self.analyzer = nil
            converter = nil
            return current
        }
        input?.finish()
        await analyzer?.cancelAndFinishNow()
        results?.cancel()
        await results?.value
        results = nil
    }
}
