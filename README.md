# VoicePilot

A native macOS overlay for push-to-talk dictation. Speak, then send the text into whatever app is focused — Cursor, Terminal, Notes, anywhere you can type.

Speech stays on the Mac. VoicePilot uses Apple’s on-device SpeechAnalyzer. No cloud model, no Electron.

## Requirements

- Apple Silicon Mac
- macOS 26 or later
- Xcode / Swift 6.2

## Build and install

```bash
make install
open /Applications/VoicePilot.app
```

Or `make run` for a debug build.

## Use

1. Click the text field you want (Cursor, Terminal, etc.).
2. Tap the **mic** on the overlay, or hold **Right Option**.
3. Talk, then stop.
4. Tap **Enter** to paste into that field and press Return.

Drag the overlay from the middle of the bar. The menu-bar **VP** item can show the bar again, quit, or open privacy settings.

## Permissions

macOS will not let one app type into another without these. Grant them for `/Applications/VoicePilot.app`:

| Setting | Why |
|---|---|
| Microphone | Capture speech |
| Speech Recognition | On-device transcription |
| Accessibility | Focus the target field |
| Input Monitoring | Inject keystrokes |
| Automation → System Events | Paste / Return into the front app |

After you rebuild and replace the app, macOS may treat it as a new binary. Remove the old VoicePilot entries and add the new `/Applications/VoicePilot.app` again.

## License

[MIT](LICENSE)
