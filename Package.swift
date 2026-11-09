// swift-tools-version: 6.2
import PackageDescription

// CaptionOverlay: live subtitles for the Mac's system sound.
// CaptionCore holds everything that is not UI, so the probe tool and the
// tests can use it without the app.
let package = Package(
    name: "CaptionOverlay",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Pinned: the Parakeet engine leans on API details of this version.
        // No traits = ASR and VAD only.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3", traits: []),
    ],
    targets: [
        .target(
            name: "CaptionCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .executableTarget(
            name: "CaptionOverlay",
            dependencies: ["CaptionCore"]
        ),
        .executableTarget(
            name: "captionprobe",
            dependencies: ["CaptionCore"]
        ),
        .testTarget(
            name: "CaptionCoreTests",
            dependencies: ["CaptionCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
