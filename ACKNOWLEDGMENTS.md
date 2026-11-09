# Acknowledgments

CaptionOverlay builds on the work of others:

- **NVIDIA Parakeet TDT 0.6b v3**, the multilingual speech recognition model behind the Parakeet engine.
  Licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- **FluidInference**: the Core ML conversion of Parakeet
  (https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) and the **FluidAudio** Swift
  library that runs it (Apache License 2.0). https://github.com/FluidInference/FluidAudio
- **Silero VAD**, the voice activity detector that keeps Parakeet off silence and music (MIT).
  https://github.com/snakers4/silero-vad
- **Apple Speech framework** (`SpeechAnalyzer` / `SpeechTranscriber`) for the Apple engine.

The way Parakeet is made to work on live sound (transcribe the unsettled stretch again every second,
settle the words that stay the same) is the method [VoiceInk](https://github.com/Beingpax/VoiceInk) uses
for dictation. CaptionOverlay's implementation is its own code; nothing from VoiceInk (GPL v3) is included.
