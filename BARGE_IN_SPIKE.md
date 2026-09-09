# Barge-in VAD spike

This is a separate Flutter entrypoint. It is not wired into the production app.

```bash
flutter run -d <android-device-id> -t lib/barge_in_spike_main.dart
```

Use an inexpensive physical Android phone in a normal room with the built-in speaker and microphone. Do not use an emulator or headphones.

The spike records 16 kHz mono PCM, calibrates a one-second room-noise floor, and applies a simple RMS energy threshold. Recorder echo cancellation and noise suppression are deliberately disabled for this first measurement. When energy crosses the threshold during TTS, it stops playback, waits for 900 ms of silence, writes a WAV clip, and sends it to Sarvam STT.

Use **Mark now: I started speaking** immediately as you begin speaking. The event log reports:

- automatic speech detection and its RMS value;
- whether TTS completed without a trigger, which indicates a missed/clean run;
- detector-to-player-stop latency;
- manual speech-start to playback-stop latency;
- the final Sarvam transcript.

Repeat several runs with speech, silence, background noise, and different speaker volume. Any automatic detection before the manual marker is an echo/background false trigger. This spike does not establish production suitability until those real-device logs are reviewed.