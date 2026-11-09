import AppKit
import CaptionCore
import SwiftUI

// CaptionOverlay: live captions for the Mac's system sound in a floating
// bar. A menu bar symbol holds all controls; the app has a Dock icon but
// no main window, and never starts by itself.

@main
struct CaptionOverlayApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: state.isOn ? "captions.bubble.fill" : "captions.bubble")
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("About CaptionOverlay")) { showAbout() }
            }
        }
    }
}

/// The standard About window, with the attributions the Parakeet model's
/// licence (CC BY 4.0) asks for.
@MainActor
func showAbout() {
    let credits = NSAttributedString(
        string: L("Parakeet speech recognition: NVIDIA Parakeet TDT 0.6b v3, licensed under CC BY 4.0, converted to Core ML by FluidInference. FluidAudio library: Apache 2.0. Silero voice detector: MIT."),
        attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        Button(L(state.isOn ? "Turn Captions Off" : "Turn Captions On")) { state.toggle() }

        Divider()

        Picker(L("Engine"), selection: $state.engine) {
            Text(verbatim: "Apple").tag(EngineKind.apple)
            Text(verbatim: "Parakeet").tag(EngineKind.parakeet)
                .selectionDisabled(state.parakeetState != .ready)
        }
        .pickerStyle(.inline)

        switch state.parakeetState {
        case .notDownloaded:
            Button(L("Download Parakeet (490 MB)…")) { state.downloadParakeet() }
        case .downloading(let fraction):
            Text(verbatim: String(format: L("Downloading… %d %%"), Int(fraction * 100)))
            Button(L("Cancel Download")) { state.cancelDownload() }
        case .preparing:
            Text(verbatim: L("Preparing model…"))
        case .ready:
            EmptyView()
        }

        Menu(L("Language")) {
            switch state.engine {
            case .apple:
                Picker(L("Language"), selection: $state.appleLanguage) {
                    ForEach(state.appleLocales, id: \.identifier) { locale in
                        Text(verbatim: AppleEngine.name(of: locale))
                            .tag(locale.identifier(.bcp47))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            case .parakeet:
                // Parakeet picks the language itself; it cannot be set.
                Toggle(L("Automatic"), isOn: .constant(true)).disabled(true)
            }
        }

        if state.isLoadingLanguage {
            Text(verbatim: L("Loading language…"))
        }
        if state.isLoadingParakeet {
            Text(verbatim: L("Loading Parakeet…"))
        }
        if let problem = state.problem {
            Divider()
            switch problem {
            case .noSound:
                Button(L("No sound received. Allow System Audio Recording…")) {
                    state.openSoundPermissionSettings()
                }
            case .downloadFailed:
                Text(verbatim: L("Download failed. Try again."))
            case .stopped(let reason):
                Text(verbatim: String(format: L("Captions stopped: %@"), reason))
            }
        }

        Divider()

        Button(L("About CaptionOverlay")) { showAbout() }
        Button(L("Quit")) { NSApp.terminate(nil) }
    }
}
