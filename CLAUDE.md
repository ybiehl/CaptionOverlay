# CaptionOverlay — working notes for Claude

A separate Mac app that shows live subtitles for the Mac's system sound in a floating bar over
every app. **Read `FINDINGS.md` first**: why it exists, what macOS permits, the speech engine test (Apple vs
Parakeet vs Whisper, German, 2026-11-09), the language findings and the proposed first version.

Rules carried over from the user's DisplayBridge work:
- Completely separate from DisplayBridge (`~/Documents/ChatGPT/DisplayBridge`): never edit, build or deploy
  anything there from this project. Code from it is copied into `reference/` when needed.
- No login items / autostart.
- ASCII file names only.
- Sign dev builds with the user's Apple Development certificate (TCC permissions depend on a stable identity);
  releases later through Developer ID + notarization (team V5HJQY5VQR).
- No customer names, emails or other personal details in this folder.
- Local git repository since 2026-11-09; meant to become a public GitHub repository (MIT): nothing personal,
  no customer data, no secrets in any commit.
- Build with `Scripts/build-app.sh` (release build with `--disable-index-store`; the index store costs ~1 GB).
  The user runs `Scripts/release.sh` (Developer ID, notarization, DMG) in their own terminal.
