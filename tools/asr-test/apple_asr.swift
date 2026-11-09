import Speech
import AVFoundation
import Foundation

// usage: apple_asr <in.wav> <out.txt>
let args = CommandLine.arguments
let inURL = URL(fileURLWithPath: args[1]), outPath = args[2]
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let t0 = Date()
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "de_DE"), preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: inURL)
        let collector = Task { () throws -> String in
            var parts: [String] = []
            for try await r in transcriber.results where r.isFinal { parts.append(String(r.text.characters)) }
            return parts.joined(separator: " ")
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else { await analyzer.cancelAndFinishNow() }
        let text = try await collector.value
        try text.write(toFile: outPath, atomically: true, encoding: .utf8)
        print(String(format: "apple %@ %.1f s", inURL.lastPathComponent, Date().timeIntervalSince(t0)))
    } catch { print("ERROR", error) }
    sem.signal()
}
sem.wait()
