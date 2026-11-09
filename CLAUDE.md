# CaptionOverlay — working notes for Claude

A separate Mac app (working name) that shows live subtitles for the Mac's system sound in a floating bar over
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
- Not a git repository yet; ask before creating one.
