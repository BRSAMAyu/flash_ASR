∆# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FlashASR is a macOS menu bar application that provides real-time speech-to-text transcription using Aliyun's Dashscope ASR service. The app runs as a background agent (LSUIElement=true) with only a menu bar icon, using global hotkeys to trigger transcription.

## Build Commands

```bash
# Build the app bundle
./scripts/build_app.sh

# Install to Applications folder
./scripts/install_app.sh

# Uninstall
./scripts/uninstall_app.sh

# Package release (creates both ZIP and DMG)
./scripts/package_release.sh

# Run the built app
open build/FlashASR.app
```

### Build Script Details

The `build_app.sh` script:
- Compiles all Swift files from `Sources/*.swift` using swiftc
- Links required frameworks: AVFoundation, Carbon, AppKit, ApplicationServices, SwiftUI, Security, ServiceManagement
- Creates a macOS .app bundle with Info.plist
- Codesigns with ad-hoc signature by default (set `SIGN_IDENTITY` for real signing)
- Builds with optimization `-O`

## Architecture

### App Structure

The app uses SwiftUI's `MenuBarExtra` for the menu bar interface. Key components:

- **FlashASRApp.swift**: Main entry point (`@main`), declares MenuBarExtra and Settings scenes
- **AppDelegate.swift**: `FlashASRDelegate` handles app lifecycle, creates AppController, shows onboarding
- **AppController.swift**: Core business logic controller managing state, audio capture, ASR clients
- **SettingsManager.swift**: Singleton using `@AppStorage` for all user preferences
- **AppStatePublisher.swift**: ObservableObject that publishes state changes to UI

### State Machine

The app uses a three-state machine (defined in AppController):

- **idle**: Not recording
- **listening**: Recording and transcribing
- **stopping**: Finalizing transcription

State transitions are thread-safe via `stateQueue` DispatchQueue.

### Two Capture Modes

1. **Realtime Mode** (`CaptureMode.realtime`):
   - Uses WebSocket streaming to Dashscope API
   - Sends audio frames continuously, receives partial/final results
   - Auto-stops after silence (configurable delay)
   - Default hotkey: Option+Space

2. **File Mode** (`CaptureMode.fileFlash`):
   - Records up to 5 minutes of audio to memory
   - On stop, encodes to WAV and uploads via HTTP
   - Receives streaming text response
   - Default hotkey: Option+LeftArrow

### Audio Pipeline

1. **AudioCapture** (`AVAudioEngine`):
   - Captures microphone input
   - Converts to 16kHz, 16-bit PCM mono (required by Dashscope)
   - 20ms frames (640 bytes at 16kHz)
   - Optional silence frame dropping for realtime mode

2. **Realtime Path**:
   - `ASRWebSocketClient` → Dashscope WebSocket API
   - Sends binary audio frames
   - Receives JSON events: opened, partial, final, speech_started, speech_stopped, session_finished, closed, error

3. **File Path**:
   - `WavEncoder.makeWav()` converts PCM to WAV
   - `FileASRStreamClient` uploads via HTTP POST
   - Receives streaming SSE response

### Output Handling

- **TranscriptBuffer**: Merges partial and final text results, throttles rendering
- **ClipboardWriter**: Copies final text to clipboard
- **RealtimeTyper**: Uses `CGEvent` to simulate keyboard input, typing text into focused application
- **RecordingIndicatorController**: Shows visual recording indicator window

### Global Hotkeys

- **GlobalKeyTap**: Uses Carbon `CGEvent.tapCreate` for global key event monitoring
- Requires Accessibility and Input Monitoring permissions
- Debounced (250ms) to prevent double-triggering
- Hotkeys stored in SettingsManager as keycode + modifier flags

### Key Constants

Defined in `AudioCapture.swift`:
- `kSampleRate = 16_000` Hz
- `kChannels = 1` (mono)
- `kFrameMS = 20` ms
- `kFrameBytes = 640` (20ms at 16kHz, 16-bit)
- `kSilenceThreshold = 220`

Timeouts:
- Realtime finalize: 2 seconds
- File ASR timeout: 90 seconds
- Max file recording: 300 seconds (5 minutes)
- Auto-stop delay: 2.2 seconds (configurable)

## File Organization

```
Sources/
├── FlashASRApp.swift          # @main entry point
├── AppDelegate.swift           # NSApplicationDelegate
├── AppController.swift         # Core business logic (state machine, audio, ASR)
├── AppStatePublisher.swift     # UI state publisher
├── SettingsManager.swift       # User settings (@AppStorage)
├── AudioCapture.swift          # Microphone capture
├── ASRWebSocketClient.swift    # Realtime WebSocket client
├── FileASRStreamClient.swift   # File ASR HTTP client
├── TranscriptBuffer.swift      # Text merging buffer
├── WavEncoder.swift            # PCM to WAV converter
├── GlobalKeyTap.swift          # Global hotkey listener
├── RealtimeTyper.swift         # Keyboard text simulation
├── ClipboardWriter.swift       # Clipboard operations
├── Console.swift               # Logging utility
├── RecordingIndicator.swift    # Recording indicator UI
├── MenuBarView.swift           # Menu bar UI
├── SettingsView.swift          # Settings container
├── GeneralSettingsView.swift   # General settings panel
├── HotkeySettingsView.swift    # Hotkey configuration
├── APIKeySettingsView.swift    # API key configuration
├── OnboardingView.swift        # First-run onboarding
├── AboutView.swift             # About dialog
└── HotkeyRecorder.swift        # Hotkey recording UI component
```

## Development Notes

### No Package.swift

This project does not use Swift Package Manager. It compiles all Swift sources directly using swiftc in the build script.

### SwiftUI + AppKit Hybrid

The app uses SwiftUI for views but AppKit for:
- Global hotkeys (Carbon API)
- Keyboard event simulation (CGEvent)
- Menu bar integration (MenuBarExtra)
- Window management

### Thread Safety

- `AppController.stateQueue`: All state mutations and audio callbacks
- `AudioCapture.queue`: Audio processing
- `Console.queue`: Thread-safe console output
- UI updates always dispatched to `.main`

### Dashscope API Configuration

- **Realtime WebSocket**: `wss://dashscope.aliyuncs.com/api-ws/v1/realtime`
- **File API**: `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
- **Models**: `qwen3-asr-flash-realtime` (realtime), `qwen3-asr-flash` (file)
- **Default API Key**: Provided in SettingsManager (consider rotating for production)

### Permissions Required

The app requires macOS permissions:
1. **Microphone**: Audio capture
2. **Accessibility**: Global hotkeys and text typing
3. **Input Monitoring**: Global hotkey event tap

These are requested via `Info.plist` descriptions and handled in `AppController.beginListening()`.
