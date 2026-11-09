# CaptionOverlay

Live captions for whatever your Mac is playing, in a floating bar over every app.

CaptionOverlay listens to the sound your Mac plays (not the microphone) and shows what is said as two
lines of text that float above every window, including full-screen video. Everything runs on the Mac;
no sound and no text leaves it.

It was built for a deaf user whose macOS Live Captions stopped working while another app was capturing
the screen. CaptionOverlay does not depend on Live Captions, so it keeps working in that situation. It
also offers a second, more accurate speech engine (NVIDIA Parakeet) and a caption bar you can place
wherever you want.

**Status: beta.** It works well on speech. Film sound with music and several speakers has not been tested
much yet. Please report what you find in the issues.

[Deutsche Anleitung weiter unten.](#deutsch)

## What you need

- A Mac with Apple Silicon (M1 or newer; every Mac from late 2020 on except Intel models)
- macOS 26 (Tahoe) or newer
- Internet only for the download of the app and, if you want it, the Parakeet speech model (490 MB)

## Step 1: Install

1. Open the [latest release](../../releases/latest) and download `CaptionOverlay-<version>.dmg`.
2. Open the downloaded file. A window with the CaptionOverlay icon and an "Applications" folder appears.
3. Drag the CaptionOverlay icon onto the Applications folder.
4. Open your Applications folder and double-click CaptionOverlay.

CaptionOverlay shows up in two places: as a **caption symbol in the menu bar** (top right of the screen)
and in the Dock. All controls are in the menu bar symbol. The Dock icon has no window of its own.

CaptionOverlay never starts by itself. Start it when you need captions, quit it when you are done.

## Step 2: Turn captions on and allow the permission

1. Click the caption symbol in the menu bar.
2. Choose **Turn Captions On**.
3. The first time, macOS asks whether CaptionOverlay may record **system audio**. Click **Allow**.
   Nothing is recorded or stored; this permission is what lets the app hear the sound.
4. A dark bar appears near the bottom of the screen. Play a video: the words appear in the bar about a
   second after they are spoken. The newest words may still change for a moment while the sentence
   continues.

If no text appears, the menu shows "No sound received. Allow System Audio Recording…". Click it to open
System Settings at the right place, switch CaptionOverlay on under **Privacy & Security > Screen & System
Audio Recording**, then turn captions off and on again.

## Step 3: Set the language

CaptionOverlay has two speech engines. Pick one under **Engine** in the menu. **Which engine you use
decides how the language is set:**

### Apple engine (the default)

The Apple engine understands **one language at a time**, and you choose it:

1. In the menu, open **Language**.
2. Tick the language of the videos you watch, for example **Deutsch (Deutschland)** or
   **English (United States)**.
3. If that language is not on your Mac yet, macOS downloads it the first time; the menu shows
   "Loading language…" meanwhile.

Set the language before you watch. With the wrong language set, the Apple engine does not say so; it
produces garbled words. Switch the language when you switch to videos in another language.

### Parakeet engine (more accurate, needs a one-time download)

Parakeet recognises the language **by itself**, among 25 European languages, so there is nothing to set:
the **Language** menu shows "Automatic". To use it:

1. In the menu, choose **Download Parakeet (490 MB)…**. The menu shows the progress
   ("Downloading… 42 %"), then "Preparing model…" and "Loading Parakeet…". The whole step takes about
   a minute on a fast connection. You can cancel and continue later.
2. Under **Engine**, choose **Parakeet**.
3. Turn captions on as in step 2.

Parakeet cannot be told which language to expect. If a video switches between languages and the captions
mix them up, use the Apple engine with the language set.

### Which engine should I use?

| | Apple | Parakeet |
|---|---|---|
| Comes with | macOS | a 490 MB download inside the app, once |
| Language | one fixed language, chosen in the menu | automatic |
| Wrong words on German speech (our test, 49 minutes) | about 1 in 18 | about 1 in 29 |
| Typical mistakes | technical words ("Thunderbolt" becomes "Thunderbowl") | word endings; the meaning survives |
| Memory while the app runs | small | about 1.2 GB |

Our recommendation: Parakeet for accuracy, Apple when you do not want the download or the memory use.

Parakeet details: the model is stored in `~/Library/Application Support/CaptionOverlay`. On first use macOS
compiles it for your Mac (about 10 seconds, once) and keeps a 1.1 GB cache in `~/Library/Caches`. After
that it loads within a second when the app starts and stays in memory while the app runs, so turning
captions on is instant.

## Step 4: Place the caption bar

- **Move:** drag the bar with the mouse to any place, also onto another screen.
- **Width:** drag the left or right edge of the bar.
- The bar remembers its place. It is only visible while captions are on.
- It floats above full-screen video and every other window and never takes the keyboard.
- When nothing has been said for a few seconds, the bar empties so old text does not sit on the picture.

## Everyday use

- Start CaptionOverlay, turn captions on, watch, turn them off or quit the app.
- Switching the engine or the language while captions are on restarts them; the bar empties for a moment.

## Privacy

The sound is processed on your Mac. Nothing is stored and nothing is sent anywhere. The only network
access is the one-time Parakeet download from Hugging Face. There is no analytics, no update check and
no account.

## Known limits

- Film sound with music and several speakers is not tested much yet (beta).
- Parakeet's language cannot be set by hand.
- Text size, colour and number of lines are fixed in this version.
- No automatic updates: look at the [releases](../../releases) now and then.

## Deutsch

CaptionOverlay zeigt Live-Untertitel für den Ton, den dein Mac abspielt, in einem schwebenden Balken über
allen Fenstern, auch über Videos im Vollbild. Alles läuft auf deinem Mac; kein Ton und kein Text verlässt
ihn.

**Voraussetzungen:** Mac mit Apple Silicon (M1 oder neuer), macOS 26 oder neuer.

**Schritt 1: Installieren**

1. Öffne das [neueste Release](../../releases/latest) und lade `CaptionOverlay-<Version>.dmg`.
2. Öffne die Datei und ziehe das CaptionOverlay-Symbol auf den Ordner „Programme“.
3. Starte CaptionOverlay aus dem Programme-Ordner. Es erscheint als **Untertitel-Symbol in der Menüleiste**
   (oben rechts) und im Dock. Alle Einstellungen sind im Menüleisten-Symbol.

**Schritt 2: Untertitel einschalten und Erlaubnis geben**

1. Klicke das Untertitel-Symbol in der Menüleiste und wähle **Untertitel einschalten**.
2. Beim ersten Mal fragt macOS, ob CaptionOverlay **Systemaudio aufnehmen** darf. Klicke **Erlauben**.
   Es wird nichts aufgenommen oder gespeichert; die Erlaubnis lässt die App nur den Ton hören.
3. Ein dunkler Balken erscheint unten auf dem Bildschirm. Spiel ein Video ab: die Wörter erscheinen etwa
   eine Sekunde nachdem sie gesprochen wurden.

Erscheint kein Text, zeigt das Menü „Kein Ton empfangen. Systemaudioaufnahme erlauben …“. Ein Klick
darauf öffnet die Systemeinstellungen an der richtigen Stelle (**Datenschutz & Sicherheit > Bildschirm-
& Systemaudioaufnahme**). Schalte CaptionOverlay dort ein, dann die Untertitel aus und wieder an.

**Schritt 3: Sprache einstellen**

Es gibt zwei Spracherkennungen, Auswahl im Menü unter **Spracherkennung**:

- **Apple** (Standard): versteht **eine Sprache**, die du wählst. Öffne im Menü **Sprache** und setze den
  Haken bei der Sprache der Videos, zum Beispiel **Deutsch (Deutschland)**. Fehlt die Sprache noch auf dem
  Mac, lädt macOS sie beim ersten Mal („Sprache wird geladen …“). Bei falsch eingestellter Sprache
  kommen sinnlose Wörter heraus, keine Fehlermeldung. Stelle die Sprache um, wenn du Videos in einer
  anderen Sprache schaust.
- **Parakeet** (genauer, einmal 490 MB laden): erkennt die Sprache **selbst** (25 europäische Sprachen),
  es gibt nichts einzustellen. Wähle im Menü **Parakeet laden (490 MB) …**, warte, bis „Lädt …“,
  „Modell wird vorbereitet …“ und „Parakeet wird geladen …“ durch sind (etwa eine Minute), und wähle dann
  unter **Spracherkennung** den Eintrag **Parakeet**. Parakeet kann nicht auf eine Sprache festgelegt
  werden; mischt ein Video Sprachen und die Untertitel geraten durcheinander, nimm Apple mit fester Sprache.

Unsere Empfehlung: Parakeet, wenn es auf Genauigkeit ankommt (in unserem Test mit deutscher Sprache
etwa 1 falsches Wort von 29 statt 1 von 18 bei Apple). Parakeet braucht etwa 1,2 GB Arbeitsspeicher,
solange die App läuft.

**Schritt 4: Balken platzieren**

Ziehe den Balken mit der Maus an eine beliebige Stelle, auch auf einen anderen Bildschirm; an der linken
oder rechten Kante änderst du die Breite. Die Position bleibt gespeichert. Der Balken liegt auch über
Videos im Vollbild.

**Datenschutz:** Der Ton wird auf deinem Mac verarbeitet, nichts wird gespeichert oder verschickt. Die
einzige Netzverbindung ist der einmalige Parakeet-Download.

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
- The caption bar is a borderless panel that joins every Space and floats above full-screen windows.

## License

MIT, see [LICENSE](LICENSE). Third-party parts are listed in [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md).
