# CaptionOverlay

Live captions for whatever your Mac is playing, in a floating bar over every app.

CaptionOverlay listens to the Mac's own sound output (not the microphone) and shows what is said as two
lines of text that float above every window, including full-screen video. Everything runs on the Mac;
no sound or text leaves it.

It was built for a deaf user whose macOS Live Captions stopped working while a screen-capture app was
running. CaptionOverlay does not depend on Live Captions, so it keeps working in that situation. It also
gives you a second, more accurate speech engine (NVIDIA Parakeet) and a bar you can place where you want.

**Status: beta.** It works well on speech; film sound with music and several speakers is not tested much
yet. Feedback welcome in the issues.

## Requirements

- A Mac with Apple Silicon (M1 or newer)
- macOS 26 (Tahoe) or newer

## Install

1. Download `CaptionOverlay-<version>.dmg` from the [latest release](../../releases/latest).
2. Open it and drag CaptionOverlay into Applications.
3. Start CaptionOverlay. It appears in the menu bar as a caption symbol and in the Dock.
4. Click the caption symbol and choose **Turn Captions On**. macOS asks once for permission to record
   **system audio**; allow it. (Nothing is recorded; the permission is what lets the app hear the sound.)
5. Play a video. The caption bar appears at the bottom of the screen.

Drag the bar anywhere, also onto another screen; drag its left or right edge to change its width. It
remembers its place. Turn captions off from the menu when you are done.

The app never starts by itself and has no settings beyond the menu.

## The two speech engines

| | Apple | Parakeet (NVIDIA) |
|---|---|---|
| Comes with | macOS | a 490 MB download inside the app, once |
| Language | one fixed language, chosen in the menu (macOS downloads it if needed) | automatic, 25 European languages |
| Accuracy on German speech (our test, 49 min) | about 1 wrong word in 18 | about 1 wrong word in 29 |
| Typical mistakes | technical words ("Thunderbolt" becomes "Thunderbowl") | word endings; the meaning survives |
| Memory while on | small | about 1.2 GB |

Choose the engine under **Engine** in the menu. Parakeet appears greyed out until it is downloaded with
**Download Parakeet**; the model is stored in `~/Library/Application Support/CaptionOverlay`. On first use
macOS compiles it for your Mac (about 10 s, once; it keeps a 1.1 GB cache in `~/Library/Caches`). After
that the model is loaded within a second when the app starts and stays in memory while the app runs.

Parakeet detects the language itself and cannot be told which language to expect. If a video mixes
languages and Parakeet mixes them up, switch to the Apple engine and set the language.

With Parakeet a word appears on screen about one second after it is spoken and may still change for a
second or two while the following words come in. The Apple engine behaves the same way.

## Privacy

The sound is processed on your Mac and nothing is stored or sent anywhere. The only network access is the
one-time Parakeet download from Hugging Face. There is no analytics, no update check, no account.

## Building from source

```bash
Scripts/build-app.sh
```

builds and signs `build/CaptionOverlay.app` with the Apple Development certificate in your keychain (ad hoc
when there is none). `swift test` runs the unit tests. `Scripts/release.sh <version> <build>` makes the
notarized DMG (needs a Developer ID certificate and notary credentials).

`captionprobe` measures the engines on an audio file:

```bash
swift build -c release --disable-index-store
.build/release/captionprobe download
.build/release/captionprobe live recording.wav gpu vad
```

[FINDINGS.md](FINDINGS.md) holds the notes behind the design: what macOS permits, the engine comparison
and the measurements.

## How it works, in short

- The system sound comes from a Core Audio process tap (macOS 14.2+), unmuted, so the sound keeps playing.
- Apple engine: `SpeechAnalyzer` with `SpeechTranscriber`, fast provisional results.
- Parakeet engine: NVIDIA Parakeet TDT 0.6b v3 as Core ML through [FluidAudio](https://github.com/FluidInference/FluidAudio),
  encoder on the GPU. Parakeet reads finished audio, so once a second the not-yet-settled stretch of sound
  is transcribed again; words that come out the same twice in a row are settled and their sound is dropped.
  A small voice detector keeps it off silence and music.
- The bar is a borderless panel that joins every Space and floats above full-screen windows.

## Deutsch

CaptionOverlay zeigt Live-Untertitel für den Ton, den dein Mac abspielt, in einem schwebenden Balken über
allen Fenstern, auch über Videos im Vollbild. Alles läuft auf dem Mac, nichts verlässt ihn.

- Voraussetzungen: Mac mit Apple Silicon, macOS 26 oder neuer.
- Installation: DMG aus den [Releases](../../releases/latest) laden, CaptionOverlay in „Programme“ ziehen,
  starten, im Menüleisten-Symbol **Untertitel einschalten** wählen und die Frage nach der
  **Systemaudioaufnahme** erlauben.
- Den Balken ziehst du mit der Maus an eine beliebige Stelle, auch auf einen anderen Bildschirm; an der
  linken oder rechten Kante änderst du die Breite.
- Zwei Spracherkennungen: **Apple** (in macOS enthalten, Sprache im Menü wählen) und **Parakeet** (einmal
  490 MB in der App laden, erkennt die Sprache selbst, deutlich weniger Fehler bei deutscher Sprache).

## License

MIT, see [LICENSE](LICENSE). Third-party parts are listed in [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md).
