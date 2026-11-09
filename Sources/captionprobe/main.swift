import AVFoundation
import CaptionCore
import CoreML
import FluidAudio
import Foundation

// captionprobe: measurements for the Parakeet engine, without the app.
//
//   captionprobe download
//       Fetch the model (with progress) and print its size on disk.
//   captionprobe batch <audio> <gpu|ane> [out.txt]
//       Whole file in one go: the accuracy and speed the model can reach.
//   captionprobe live <audio> <gpu|ane> <vad|novad> [out.txt] [passes] [held]
//       The live method on a file, on a simulated clock: sound "arrives" in
//       real time, a pass starts every second (or when the previous one is
//       done, whichever is later). Prints how late words appear and how
//       often shown words change afterwards.
//   captionprobe apple <audio> <locale> [out.txt]
//       Apple's engine fed at real-time speed (takes as long as the audio).

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

/// Any audio file as 16 kHz mono floats.
func loadAudio(_ path: String) throws -> [Float] {
    try AudioConverter().resampleAudioFile(URL(fileURLWithPath: path))
}

func computeUnits(_ name: String) -> MLComputeUnits {
    switch name {
    case "gpu": return .cpuAndGPU
    case "ane": return .cpuAndNeuralEngine
    default: fail("compute units must be gpu or ane")
    }
}

func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
}

func directorySize(_ url: URL) -> Int {
    guard let files = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total = 0
    for case let file as URL in files {
        total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    return total
}

func download() async throws {
    let started = Date()
    final class Last: @unchecked Sendable { var shown = -1 }
    let last = Last()
    try await ParakeetModelStore.download { progress in
        switch progress {
        case .downloading(let fraction):
            let percent = Int(fraction * 100)
            if percent >= last.shown + 5 {
                last.shown = percent
                print(String(format: "downloading %3d %%  (%.0f s)", percent,
                             Date().timeIntervalSince(started)))
            }
        case .preparing:
            if last.shown != 1000 {
                last.shown = 1000
                print(String(format: "preparing        (%.0f s)", Date().timeIntervalSince(started)))
            }
        }
    }
    let models = ParakeetModelStore.baseDirectory.appendingPathComponent("Models")
    print(String(format: "done in %.0f s, downloaded: %@, %.0f MB on disk at %@",
                 Date().timeIntervalSince(started), String(ParakeetModelStore.isDownloaded),
                 Double(directorySize(models)) / 1e6, models.path))
}

func batch(_ arguments: [String]) async throws {
    guard arguments.count >= 2 else { fail("batch <audio> <gpu|ane> [out.txt]") }
    let samples = try loadAudio(arguments[0])
    let loadStart = Date()
    let models = try await AsrModels.load(
        from: ParakeetModelStore.baseDirectory.appendingPathComponent("Models/parakeet-tdt-0.6b-v3"),
        version: .v3, encoderComputeUnits: computeUnits(arguments[1]))
    let manager = AsrManager(config: .default)
    try await manager.loadModels(models)
    let loadSeconds = Date().timeIntervalSince(loadStart)
    var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
    let started = Date()
    let result = try await manager.transcribe(samples, decoderState: &state)
    let seconds = Date().timeIntervalSince(started)
    let audioSeconds = Double(samples.count) / 16000
    print(String(format: "batch %@: load %.1f s, %.1f s audio in %.2f s = %.0fx real time",
                 arguments[1], loadSeconds, audioSeconds, seconds, audioSeconds / seconds))
    if arguments.count > 2 {
        try result.text.write(toFile: arguments[2], atomically: true, encoding: .utf8)
    }
}

func live(_ arguments: [String]) async throws {
    guard arguments.count >= 3 else {
        fail("live <audio> <gpu|ane> <vad|novad> [out.txt] [passes] [held] [context s]")
    }
    let samples = try loadAudio(arguments[0])
    var config = WordAgreement.Config()
    if arguments.count > 4, let passes = Int(arguments[4]) { config.passesNeeded = passes }
    if arguments.count > 5, let held = Int(arguments[5]) { config.heldBackWords = held }
    var context = 3.0
    if arguments.count > 6, let seconds = Double(arguments[6]) { context = seconds }
    let streamer = try await ParakeetStreamer(
        encoderComputeUnits: computeUnits(arguments[1]),
        useVoiceDetector: arguments[2] == "vad", contextSeconds: context, agreement: config)

    let rate = 16000.0
    let interval = 1.0
    var clock = interval          // simulated seconds since the sound began
    var fed = 0
    var settledWords: [TimedWord] = []
    var firstShown: [String: Double] = [:]   // "start|text" -> clock when first on screen
    var appearDelays: [Double] = []           // word end -> first on screen
    var settleDelays: [Double] = []           // word end -> settled
    var passSeconds: [Double] = []
    var stretches: [Double] = []
    var shownBefore: [TimedWord] = []
    var changedWords = 0
    var shownWords = 0
    let wallStart = Date()

    func key(_ word: TimedWord) -> String { "\(Int(word.start * 10))|\(word.text.lowercased())" }

    while fed < samples.count {
        let available = min(samples.count, Int(clock * rate))
        if available > fed {
            await streamer.append(Array(samples[fed..<available]))
            fed = available
        }
        guard let report = try await streamer.pass() else {
            clock += interval
            continue
        }
        let shownAt = clock + report.passSeconds
        passSeconds.append(report.passSeconds)
        stretches.append(report.stretchSeconds)
        for word in report.newlySettled + report.provisional where firstShown[key(word)] == nil {
            firstShown[key(word)] = shownAt
            appearDelays.append(shownAt - word.end)
        }
        for word in report.newlySettled {
            settleDelays.append(shownAt - word.end)
        }
        // Flicker: provisional words shown last time that are different
        // now (compared by position).
        let now = report.newlySettled + report.provisional
        for (index, old) in shownBefore.enumerated() {
            shownWords += 1
            if index >= now.count || now[index].text.lowercased() != old.text.lowercased() {
                changedWords += 1
            }
        }
        shownBefore = report.provisional
        settledWords += report.newlySettled
        clock = max(clock + interval, shownAt)
    }
    let rest = await streamer.settleAll()
    _ = rest
    let text = (settledWords.map(\.text) + shownBefore.map(\.text)).joined(separator: " ")
    if arguments.count > 3 {
        try text.write(toFile: arguments[3], atomically: true, encoding: .utf8)
    }

    appearDelays.sort()
    settleDelays.sort()
    let sortedPass = passSeconds.sorted()
    let sortedStretch = stretches.sorted()
    print(String(format: "live %@ %@ passes=%d held=%d context=%.0f: %.0f s audio, %d passes, wall %.0f s",
                 arguments[1], arguments[2], config.passesNeeded, config.heldBackWords, context,
                 Double(samples.count) / rate, passSeconds.count,
                 Date().timeIntervalSince(wallStart)))
    print(String(format: "  word on screen after it was spoken: median %.2f s, 90 %% %.2f s, worst %.2f s",
                 percentile(appearDelays, 0.5), percentile(appearDelays, 0.9), appearDelays.last ?? .nan))
    print(String(format: "  word settled after it was spoken:   median %.2f s, 90 %% %.2f s, worst %.2f s",
                 percentile(settleDelays, 0.5), percentile(settleDelays, 0.9), settleDelays.last ?? .nan))
    print(String(format: "  one pass takes: median %.3f s, 90 %% %.3f s, worst %.3f s",
                 percentile(sortedPass, 0.5), percentile(sortedPass, 0.9), sortedPass.last ?? .nan))
    print(String(format: "  stretch per pass: median %.1f s, worst %.1f s",
                 percentile(sortedStretch, 0.5), sortedStretch.last ?? .nan))
    print(String(format: "  provisional words that changed in the next pass: %d of %d = %.1f %%",
                 changedWords, shownWords, shownWords > 0 ? Double(changedWords) / Double(shownWords) * 100 : 0))
}

func apple(_ arguments: [String]) async throws {
    guard arguments.count >= 2 else { fail("apple <audio> <locale> [out.txt] [legacy]") }
    let samples = try loadAudio(arguments[0])
    let engine = AppleEngine(locale: Locale(identifier: arguments[1]))
    engine.legacySetup = arguments.count > 3 && arguments[3] == "legacy"
    final class Box: @unchecked Sendable {
        var all = ""
        var provisional = ""
        var updates = 0
        var firstText: Date?
    }
    let box = Box()
    let lock = NSLock()
    engine.onUpdate = { update in
        lock.withLock {
            box.updates += 1
            if box.firstText == nil, !(update.newlySettled + update.provisional).isEmpty {
                box.firstText = Date()
            }
            if !update.newlySettled.isEmpty { box.all += " " + update.newlySettled }
            box.provisional = update.provisional
        }
    }
    engine.onError = { error in print("apple engine error:", error) }
    // Lag: how far the sound fed so far is ahead of the newest result.
    final class Fed: @unchecked Sendable { var seconds = 0.0 }
    let fed = Fed()
    final class Lags: @unchecked Sendable { var volatile: [Double] = []; var final: [Double] = [] }
    let lags = Lags()
    engine.onResultRange = { range, isFinal in
        let end = range.end.seconds
        guard end.isFinite else { return }
        lock.withLock {
            let lag = fed.seconds - end
            if isFinal { lags.final.append(lag) } else { lags.volatile.append(lag) }
        }
    }
    let setupStart = Date()
    try await engine.start()
    print(String(format: "apple setup took %.1f s", Date().timeIntervalSince(setupStart)))
    let started = Date()
    let chunk = 1600  // 0.1 s
    var position = 0
    while position < samples.count {
        let end = min(samples.count, position + chunk)
        engine.feed(Array(samples[position..<end]))
        position = end
        let due = Double(position) / 16000
        lock.withLock { fed.seconds = due }
        let ahead = due - Date().timeIntervalSince(started)
        if ahead > 0 { try await Task.sleep(for: .seconds(ahead)) }
    }
    try await Task.sleep(for: .seconds(3))
    await engine.stop()
    let text = lock.withLock {
        (box.all + " " + box.provisional).trimmingCharacters(in: .whitespaces)
    }
    print(String(format: "apple %@%@: %.0f s audio, %d updates, first text after %.1f s, %d words",
                 arguments[1], engine.legacySetup ? " (legacy setup)" : "",
                 Double(samples.count) / 16000, box.updates,
                 box.firstText?.timeIntervalSince(started) ?? .nan,
                 text.split(separator: " ").count))
    let (volatile, final) = lock.withLock { (lags.volatile.sorted(), lags.final.sorted()) }
    print(String(format: "  provisional text behind the sound: median %.2f s, 90 %% %.2f s (%d results)",
                 percentile(volatile, 0.5), percentile(volatile, 0.9), volatile.count))
    print(String(format: "  final text behind the sound:       median %.2f s, 90 %% %.2f s (%d results)",
                 percentile(final, 0.5), percentile(final, 0.9), final.count))
    if arguments.count > 2 {
        try text.write(toFile: arguments[2], atomically: true, encoding: .utf8)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("captionprobe download | batch | live | apple") }
do {
    switch command {
    case "download": try await download()
    case "batch": try await batch(Array(arguments.dropFirst()))
    case "live": try await live(Array(arguments.dropFirst()))
    case "apple": try await apple(Array(arguments.dropFirst()))
    default: fail("unknown command \(command)")
    }
} catch {
    fail("error: \(error)")
}
