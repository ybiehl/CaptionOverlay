# CaptionOverlay — findings and scope (2026-11-09)

Working name. A small, separate Mac app that shows live subtitles for whatever the Mac is playing, in a
floating bar over every other app. Started from a DisplayBridge support case; **DisplayBridge itself stays
unchanged** (user decision 2026-11-09). This folder has nothing to do with the DisplayBridge repo except the
reference code copied into `reference/`.

## 1. Why this app exists

A deaf customer emailed DisplayBridge support on 2026-11-09:
- Setup: sending Mac = Mac mini M4 (2024), macOS 27.2; receiving Mac = iMac Pro, macOS 15.8.2; Thunderbolt cable.
- macOS **Live Captions** (Accessibility, source "Computer audio", German) shows almost nothing while
  DisplayBridge is connected: the window stays grey, only an occasional word. This also happens with the sound
  set to stay on the Mac mini and the video playing on a separate HDMI monitor.
- Disconnecting DisplayBridge brings Live Captions back immediately.
- They need captions to follow videos.

Why Live Captions fails is **not known**:
- DisplayBridge keeps a ScreenCaptureKit stream running with an audio output attached, even when the sound
  stays on the sending Mac (DisplayBridge `GBSession.swift`, `capturesAudio` + `addStreamOutput(.audio)`).
- Known: Apple keeps the Live Captions window out of screen sharing and screenshots (it turns black in the
  share). But this customer sees the window, grey. So Live Captions is either holding back on purpose while the
  screen is captured, or the capture disturbs its sound input. Neither is confirmed.
- Easy check on any Mac: start a QuickTime screen recording or a screen share and see whether Live Captions
  goes grey too. If it does, it is Apple's behaviour, not something DisplayBridge does.

Either way, our own app does not depend on Live Captions, so it avoids the problem.

## 2. What macOS allows (permissions)

| Part | How | Permission |
|---|---|---|
| Caption bar over every app, including full-screen video | `NSPanel` with `.nonactivatingPanel`, app runs as `.accessory` (no Dock icon, menu bar only), level `.floating` or higher, `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `ignoresMouseEvents = true` (clicks go through) | **none** |
| The Mac's system sound | Core Audio process tap (`CATapDescription` + `AudioHardwareCreateProcessTap` + a private aggregate device), macOS 14.2+ | **"System Audio Recording"** (needs `NSAudioCaptureUsageDescription` in Info.plist). Not Screen Recording. |
| Speech to text | Apple `SpeechTranscriber` (macOS 26+), or Parakeet / Whisper bundled | Apple: maybe "Speech Recognition" (tutorials say yes; a command-line test on 2026-11-09 did NOT ask; still to be checked inside an app). Parakeet/Whisper: none. |

Sources: Apple forum thread on overlay panels over full-screen Spaces, tested on macOS 26
(https://developer.apple.com/forums/thread/826308); TechNet Experts on the window flags
(https://www.technetexperts.com/macos-python-fullscreen-overlay-fix/).

Notes:
- **Leave the tap UNMUTED.** The DisplayBridge experiment muted it (`muteBehavior = .muted`) because it moved the
  sound to the other Mac. Here the sound must keep playing normally.
- The caption bar is an ordinary window, so if the user drags it onto a DisplayBridge screen, DisplayBridge
  sends it along. Do not set `sharingType = .none` unless we decide we want it hidden from screen captures.
- A tap of all processes worked during a running DisplayBridge session on 2026-10-27 (MacBook, macOS 26).
  **Not yet tested:** a Mac mini on macOS 27 with DisplayBridge connected. That is the first thing to prove.
- In that experiment the permission prompt flow was never checked either.

## 3. Speech engine test (2026-11-09)

Audio: 49.2 minutes / 6,784 words of the user's own German voice-over takes (4 takes, phone mic, one speaker,
no music). Reference = the existing Whisper large-v3 transcripts (the user accepted that as ground truth).
Before scoring, spelling style was normalised (€ ↔ Euro, numbers ↔ number words, "Display Bridge" ↔
"DisplayBridge", "Mac OS" ↔ "macOS", Hz/ms/W/GB, "d. h.").
Machine: MacBook Pro M1 Pro, macOS 26.7.1.

| Engine | Wrong words (WER) | Characters wrong | Speed | Errors only this engine makes |
|---|---|---|---|---|
| Apple `SpeechTranscriber` (de_DE, preset `.transcription`) | **5.5 %** (≈ 1 in 18) | 2.0 % | 130× real time | 189 |
| NVIDIA Parakeet TDT 0.6b v3 (`parakeet-mlx`) | **3.4 %** (≈ 1 in 29) | 1.15 % | 33× real time | 73 |
| Whisper large-v3-turbo (`mlx-whisper`) | **2.65 %** (≈ 1 in 38) | 0.9 % | 21× real time | 50 |

Before normalising: Apple 8.1 %, Parakeet 5.1 %, turbo 3.7 %.

How to read it:
- Whisper turbo is from the same family as the reference, so it is flattered. The real gap to Parakeet is
  probably smaller.
- In 77 spots all three engines disagree with the reference (e.g. all hear "Endung .dmg" where the reference
  says "Änderung .dmg"). Those are reference mistakes, so all rates are slight overestimates.
- Character of the mistakes:
  - **Apple:** technical words: "Ethernet" → "Internet" (8×), "Thunderbolt" → "Thunderbowl" (7×),
    "DisplayBridge" → "Bridge". Also small words that change the meaning ("ein Kabel" → "so Kabel",
    "man" → "wir").
  - **Parakeet:** mostly grammar endings ("ein" → "einen", "dem" → "den"), a few odd words ("welches" → "melchiz").
    The meaning almost always survives.
  - **Whisper turbo:** word joins ("Hardware Umbau" → "Hardwareumbau"), a few dropped filler words.
- Apple supports `de_AT`, `de_CH`, `de_DE`; German was already installed on the test Mac (no download).
- Model sizes: Whisper turbo 1.5 GB on disk. Parakeet ≈ 1.2 GB is an estimate (0.6 B parameters), not measured.
  Apple's engine ships with macOS.
- Licences: Parakeet v3 CC-BY-4.0 (commercial use OK with attribution); Whisper MIT; Apple = system API.

Per-error lists: `tools/asr-test/errors2-*.json`; totals: `tools/asr-test/results-summary.json`.

## 4. Languages (tested 2026-11-09)

- **Apple: one fixed language per transcriber, no automatic detection.** German set + English video gives
  garbled pseudo-German, not an error:
  > "Over the Last week I received the Lot of E-Mails and YouTube Commons from You Guys wo are interesteit …
  > whitch Max supported … macirteen Venta"

  With `en_US` set, the same clip is almost perfect. As far as we know, macOS Live Captions also uses one
  language picked in its settings.
- **Parakeet detects the language by itself** (25 European languages): the English clip came out clean with no
  setting. But in a clip that switches from German to English halfway, the German part picked up English words
  ("dann is this video genau richtig für dich. This can klappt genauso …").
- ~~With Parakeet a fixed language choice fixes mixed-language videos.~~ **Wrong (checked 2026-11-09):**
  Parakeet v3 has no language input at all. FluidAudio's "language hint" only restricts the alphabet
  (Latin / Cyrillic / Greek); its own docs say it cannot stop English words inside German speech. So the app
  offers a language choice for Apple only; Parakeet is "Automatic". For a video where Parakeet mixes
  languages, the way out is the Apple engine with a fixed language.

## 5. Recommendation so far

**Parakeet** is the best balance: far fewer real mistakes than Apple, close to Whisper, faster than Whisper
(more headroom next to DisplayBridge's GPU work), detects the language itself.
Apple's engine stays the fallback: no download, very fast, but it misses technical words.

Still open before deciding:
1. **Real soundtracks:** films and YouTube with music, effects, several speakers. Whisper is known to invent
   text in German during music or silence (e.g. "Untertitel im Auftrag des ZDF"); not tested here.
2. **Live mode:** delay from sound to text on screen. Apple is built for live (volatile + final results);
   Parakeet and Whisper were only run on whole files. `parakeet-mlx` has a streaming API (`transcribe_stream`),
   untested.
3. **How to ship Parakeet in a Swift app:** `parakeet-mlx` is Python. Options to check: a Swift/Core ML port
   (e.g. the FluidAudio package; not verified), MLX Swift, or a bundled helper process.
4. **The first real test:** captions on a Mac mini (macOS 27) while DisplayBridge is connected.

## 6. Proposed first version (scope)

In:
- Menu bar app, no Dock icon, no login item / autostart (user rule).
- Start / stop captions; language: Auto / Deutsch / English (more later).
- Caption bar: 2–3 lines, large readable text on a dark translucent background, movable, resizable, choice of
  screen, clicks pass through; on top of full-screen videos.
- System sound through a Core Audio tap (all processes, unmuted).
- One speech engine (Parakeet unless the open tests say otherwise), on-device only, no network.
- Plain-language permission guide on first start ("System Audio Recording", and Speech Recognition if Apple's
  engine needs it).

Out (for now): saving transcripts, translation, speaker labels, microphone input, iOS.

Platform floor: macOS 14.2 for the tap; macOS 26 if Apple's engine is used.

## 6a. First version: what was built and measured (2026-11-09)

Plan: `~/.claude/plans/pasted-content-id-d3c1-okay-i-elegant-umbrella.md` (approved 2026-11-09). Changes to
section 6: both engines selectable (Apple with language list, Parakeet automatic); Parakeet is downloaded in
the app, not shipped; the bar is dragged to move (not click-through); the app has a Dock icon.

Parakeet runs through the Swift package **FluidAudio 0.18.3** (Core ML). Live method = the one VoiceInk uses,
written as our own code (VoiceInk is GPL v3, nothing copied): once a second the not-yet-settled stretch of
sound is transcribed again; words that came out the same in 2 passes in a row are settled (the newest 2 words
never); settled sound is dropped except 3 s kept as context for the next pass.

Measured on the MacBook Pro M1 Pro, one German take (10.5 min, 1,471 words, `board-comparison-voiceover-de`),
with `captionprobe` (simulated real-time clock):

| | Result |
|---|---|
| Download | 484 MB on disk (encoder 6-bit, decoder, joint, vocabulary + 1 MB voice detector), 39 s on this line |
| Whole file, encoder on GPU | 118x real time (first run after download 63x), 5.8 % wrong words |
| Whole file, encoder on Neural Engine | 220x real time, 5.7 % wrong words; first load 37 s |
| Live, GPU, final settings | **3.9 % wrong words**; a word is on screen a median 0.8 s after it was spoken (90 %: 1.7 s); one pass takes 0.15 s |
| Live without the 3 s context | 14.8 % wrong words (measured with the number bug below still in) |

- The live text is better than the whole-file run here; the whole-file run switched to English once
  ("photographs that really the exact") and lost words at its internal 15 s seams.
- parakeet-mlx (Python) reached 3.4 % on this take in section 3, so the Core ML version is in the same range.
- Bug found by this test: before a number Parakeet sends the space as a token of its own; ignoring it glued
  the number to the word before ("alten5k") and cost about 6 points. Fixed, with a unit test.
- GPU vs Neural Engine was not compared in live mode: the Mac's disk was full (see below) and the Neural
  Engine could not write its compiled model. The app uses the GPU.
- **Not measured yet:** film / YouTube sound with music and several speakers; Apple engine live from the tap;
  the permission prompts; the bar over a full-screen video with the Dock icon on; Mac mini + DisplayBridge.
- The test Mac had 0.8 GB free disk during these runs. One Neural Engine run failed with "No space left on
  device". `.build` is about 1.3 GB; build with `--disable-index-store` (build-app.sh does) to save 1 GB.

## 7. Files here

- `reference/GBSystemAudioTap.swift` + `GBSystemAudioTap-commit-message.txt`: the working Core Audio tap from
  DisplayBridge branch `experiment/system-audio-tap` (commit 4ef0e72). Reuse it; flip `muteBehavior` to
  unmuted and drop the DisplayBridge names.
- `Sources/`, `Tests/`, `Scripts/`, `Resources/`: the app (see `Package.swift`). `Scripts/build-app.sh` builds
  and signs `build/CaptionOverlay.app`. `captionprobe` (`swift build -c release --disable-index-store`, then
  `.build/release/captionprobe download | batch | live | apple`) does the measurements of section 6a.
- `tools/asr-test/`: the test from section 3/4: `apple_asr.swift` (Apple engine on a wav, German),
  `apple_asr2.swift` (locale as 3rd argument), `run_models.py` (parakeet / turbo), `score.py`, `score2.py`
  (normalised), `unique.py` (errors only one engine makes). They point at the scratch folder used on
  2026-11-09 (`audio/*.wav` = 16 kHz mono copies of the DisplayBridge library takes
  `media/library/raw/*-voiceover-*-de.m4a`); adjust the paths before re-running.
  Python environments used: `parakeet-mlx` + `jiwer` in a throwaway venv; Whisper via
  `~/Documents/VideoVoiceOver/.venv`.

## 8. Before any release

- Name, trademark and domain check (as done for DisplayBridge, see its docs/website.md). "Live Captions" is
  Apple's feature name: do not use it as the product name.
- Parakeet CC-BY-4.0 attribution in an Acknowledgments file + About window.
- Developer ID signing and notarization (team V5HJQY5VQR, same as DisplayBridge).
- Native German check of all UI text; ASCII file names only.
