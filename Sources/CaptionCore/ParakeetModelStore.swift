import CoreML
import FluidAudio
import Foundation

// ParakeetModelStore: where the Parakeet model lives on disk, whether it is
// there, and the download.
//
// The model is not part of the app. It is fetched from Hugging Face
// (FluidInference/parakeet-tdt-0.6b-v3-coreml, plus the small Silero voice
// detector) into ~/Library/Application Support/CaptionOverlay/Models.
// This is the app's only network use.

public enum ParakeetModelStore {
    /// How far a download is, for the menu.
    public enum Progress: Sendable, Equatable {
        /// 0...1 of the bytes.
        case downloading(Double)
        /// Files are there; Core ML is compiling them for this Mac.
        case preparing
    }

    /// Which processor the big part of the model (the encoder) runs on.
    public static let encoderComputeUnits: MLComputeUnits = .cpuAndGPU

    /// ~/Library/Application Support/CaptionOverlay
    public static var baseDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("CaptionOverlay", isDirectory: true)
    }

    /// FluidAudio puts each model into its own folder next to this one; the
    /// last path component only selects the model.
    static var parakeetDirectory: URL {
        baseDirectory.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v3", isDirectory: true)
    }

    /// Both models complete on disk (a half-finished download does not count).
    public static var isDownloaded: Bool {
        AsrModels.modelsExist(at: parakeetDirectory, version: .v3) && voiceDetectorExists
    }

    private static var voiceDetectorExists: Bool {
        let models = baseDirectory.appendingPathComponent("Models", isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: models, includingPropertiesForKeys: nil) else { return false }
        return folders.contains { folder in
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(ModelNames.VAD.sileroVadFile)
                    .appendingPathComponent("coremldata.bin").path)
        }
    }

    /// Downloads what is missing. Cancelling the task stops it; the next
    /// call continues with the files that are not complete yet.
    public static func download(progress: @escaping @Sendable (Progress) -> Void) async throws {
        try FileManager.default.createDirectory(
            at: baseDirectory, withIntermediateDirectories: true)
        try await AsrModels.download(
            to: parakeetDirectory, version: .v3,
            encoderComputeUnits: encoderComputeUnits
        ) { report in
            switch report.phase {
            case .listing:
                progress(.downloading(0))
            case .downloading:
                // FluidAudio counts the network part as the first half and
                // compiling as the second.
                progress(.downloading(min(1, report.fractionCompleted * 2)))
            case .compiling:
                progress(.preparing)
            }
        }
        try Task.checkCancellation()
        progress(.preparing)
        // Creating the detector downloads it when it is missing.
        _ = try await VadManager(modelDirectory: baseDirectory)
    }

    /// The loaded speech model, encoder on the GPU.
    static func loadSpeechModels(
        encoderComputeUnits: MLComputeUnits = encoderComputeUnits
    ) async throws -> AsrModels {
        try await AsrModels.load(
            from: parakeetDirectory, version: .v3, encoderComputeUnits: encoderComputeUnits)
    }

    static func loadVoiceDetector() async throws -> VadManager {
        try await VadManager(modelDirectory: baseDirectory)
    }
}
