import AppKit
import CaptionCore
import Foundation
import os

// AppState: what the menu shows and the one pipeline behind it:
//
//   SystemAudioTap -> silence gate -> engine (Apple or Parakeet) -> caption bar
//
// Everything here runs on the main actor except the sound itself, which
// goes from the tap's queue straight into the engine.

enum EngineKind: String {
    case apple
    case parakeet
}

@MainActor
final class AppState: ObservableObject {
    enum ParakeetState: Equatable {
        case notDownloaded
        case downloading(Double)
        case preparing
        case ready
    }

    /// Something the user should know about, shown as one menu line.
    enum Problem: Equatable {
        /// Captions are on but only silence has arrived so far. Either
        /// nothing is playing or "System Audio Recording" is not allowed;
        /// macOS does not tell an app which.
        case noSound
        case downloadFailed
        case stopped(String)
    }

    private enum Key {
        static let engine = "app.captionoverlay.engine"
        static let appleLanguage = "app.captionoverlay.appleLanguage"
    }

    @Published private(set) var isOn = false
    /// Between the click and the first sound reaching the engine.
    @Published private(set) var isStarting = false
    @Published private(set) var parakeetState: ParakeetState
    @Published private(set) var appleLocales: [Locale] = []
    /// macOS is downloading the chosen Apple language.
    @Published private(set) var isLoadingLanguage = false
    /// Parakeet is being read into memory (once per app run).
    @Published private(set) var isLoadingParakeet = false
    @Published private(set) var problem: Problem?

    /// Timings, readable with: log show --predicate 'subsystem == "app.captionoverlay.mac"'
    private let log = Logger(subsystem: "app.captionoverlay.mac", category: "timing")

    @Published var engine: EngineKind {
        didSet {
            guard engine != oldValue else { return }
            UserDefaults.standard.set(engine.rawValue, forKey: Key.engine)
            if engine == .parakeet { warmUpParakeet() }
            restartIfOn()
        }
    }

    /// BCP 47 identifier of the Apple engine's language.
    @Published var appleLanguage: String {
        didSet {
            guard appleLanguage != oldValue else { return }
            UserDefaults.standard.set(appleLanguage, forKey: Key.appleLanguage)
            if engine == .apple { restartIfOn() }
        }
    }

    private let panel = CaptionPanel()
    private var tap: SystemAudioTap?
    private var running: CaptionEngine?
    private var download: Task<Void, Never>?
    private var soundCheck: Task<Void, Never>?
    /// Counts starts so a slow start that was overtaken does nothing.
    private var generation = 0

    init() {
        let defaults = UserDefaults.standard
        parakeetState = ParakeetModelStore.isDownloaded ? .ready : .notDownloaded
        let saved = EngineKind(rawValue: defaults.string(forKey: Key.engine) ?? "") ?? .apple
        engine = saved == .parakeet && !ParakeetModelStore.isDownloaded ? .apple : saved
        appleLanguage = defaults.string(forKey: Key.appleLanguage) ?? ""
        Task { await loadLanguages() }
        if engine == .parakeet { warmUpParakeet() }
    }

    /// Reads Parakeet into memory ahead of time, so turning captions on
    /// starts at once. The models stay loaded until the app quits.
    private func warmUpParakeet() {
        guard parakeetState == .ready, !isLoadingParakeet else { return }
        isLoadingParakeet = true
        let started = Date()
        Task {
            defer { isLoadingParakeet = false }
            do {
                try await ParakeetModelCache.shared.warmUp()
                log.notice("parakeet ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
            } catch {
                log.error("parakeet warm-up failed: \(error)")
            }
        }
    }

    private func loadLanguages() async {
        let locales = await AppleEngine.supportedLocales()
        appleLocales = locales
        let identifiers = locales.map { $0.identifier(.bcp47) }
        guard !identifiers.contains(appleLanguage) else { return }
        // First start: the Mac's own language if the engine has it, else
        // any variant of it, else English.
        let current = Locale.current
        let own = current.identifier(.bcp47)
        let sameLanguage = locales.first {
            $0.language.languageCode == current.language.languageCode
        }
        appleLanguage = identifiers.contains(own) ? own
            : sameLanguage?.identifier(.bcp47) ?? "en-US"
    }

    // MARK: Captions on / off

    func toggle() {
        if isOn { stop() } else { start() }
    }

    private func restartIfOn() {
        guard isOn else { return }
        stop()
        start()
    }

    private func start() {
        generation += 1
        let generation = self.generation
        isOn = true
        isStarting = true
        problem = nil
        panel.show()
        let started = Date()
        let kind = engine
        Task {
            do {
                let engine = try await makeEngine()
                guard generation == self.generation, isOn else {
                    await engine.stop()
                    return
                }
                log.notice("captions on (\(kind.rawValue)): engine ready after \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
                var firstText = false
                engine.onUpdate = { [weak self] update in
                    Task { @MainActor in
                        guard let self, generation == self.generation else { return }
                        if !firstText, !(update.newlySettled + update.provisional).isEmpty {
                            firstText = true
                            self.log.notice("captions on (\(kind.rawValue)): first text after \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
                        }
                        self.panel.apply(update)
                    }
                }
                engine.onError = { [weak self] error in
                    Task { @MainActor in
                        guard let self, generation == self.generation else { return }
                        self.stop()
                        self.problem = .stopped("\(error)")
                    }
                }
                let tap = SystemAudioTap()
                var gate = SilenceGate()
                tap.onAudio = { samples in
                    if gate.passes(samples) { engine.feed(samples) }
                }
                try tap.start()
                running = engine
                self.tap = tap
                isStarting = false
                watchForSound(generation)
            } catch {
                guard generation == self.generation else { return }
                stop()
                problem = .stopped("\(error)")
            }
        }
    }

    private func makeEngine() async throws -> CaptionEngine {
        switch engine {
        case .parakeet:
            let engine = ParakeetEngine()
            try await engine.start()
            return engine
        case .apple:
            let locale = Locale(identifier: appleLanguage)
            if !(await AppleEngine.isInstalled(locale)) {
                isLoadingLanguage = true
                defer { isLoadingLanguage = false }
                try await AppleEngine.install(locale) { _ in }
            }
            let engine = AppleEngine(locale: locale)
            try await engine.start()
            return engine
        }
    }

    private func stop() {
        generation += 1
        isOn = false
        isStarting = false
        problem = nil
        soundCheck?.cancel()
        soundCheck = nil
        tap?.stop()
        tap = nil
        panel.hide()
        if let engine = running {
            running = nil
            Task { await engine.stop() }
        }
    }

    /// Says so in the menu when only silence arrives, and takes it back as
    /// soon as there is sound.
    private func watchForSound(_ generation: Int) {
        soundCheck?.cancel()
        soundCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                guard let self, generation == self.generation, let tap = self.tap else { return }
                if tap.heardSound {
                    if self.problem == .noSound { self.problem = nil }
                    return
                }
                self.problem = .noSound
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func openSoundPermissionSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Parakeet download

    func downloadParakeet() {
        guard download == nil else { return }
        parakeetState = .downloading(0)
        if problem == .downloadFailed { problem = nil }
        let started = Date()
        download = Task { [weak self] in
            do {
                try await ParakeetModelStore.download { progress in
                    Task { @MainActor in
                        guard let self, self.download != nil else { return }
                        switch progress {
                        case .downloading(let fraction):
                            // Never backwards, never back from "preparing".
                            if case .downloading(let shown) = self.parakeetState, fraction > shown {
                                self.parakeetState = .downloading(fraction)
                            }
                        case .preparing:
                            self.parakeetState = .preparing
                        }
                    }
                }
                guard let self else { return }
                self.download = nil
                self.parakeetState = ParakeetModelStore.isDownloaded ? .ready : .notDownloaded
                self.log.notice("parakeet downloaded and prepared in \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
                self.warmUpParakeet()
            } catch {
                guard let self else { return }
                let cancelled = Task.isCancelled
                self.download = nil
                self.parakeetState = .notDownloaded
                if !cancelled { self.problem = .downloadFailed }
            }
        }
    }

    func cancelDownload() {
        download?.cancel()
    }
}

/// Lets sound through until the Mac has been silent for a while, so the
/// engines are not run on nothing. Digital silence only: quiet sound passes.
struct SilenceGate {
    /// Silence that still passes, so an engine hears a sentence end.
    private static let trailingSamples = Int(SystemAudioTap.sampleRate * 1.5)
    private var silentSamples = 0

    mutating func passes(_ samples: [Float]) -> Bool {
        if samples.contains(where: { $0 != 0 }) {
            silentSamples = 0
            return true
        }
        silentSamples += samples.count
        return silentSamples <= Self.trailingSamples
    }
}
