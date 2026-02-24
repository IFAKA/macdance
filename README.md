# MacDance

A macOS dance game that uses your camera to track body poses and score your moves against choreographed routines.

## Install

1. Download `MacDance.dmg` from [Releases](https://github.com/IFAKA/macdance/releases)
2. Open the DMG and drag MacDance to Applications
3. Launch MacDance — grant camera and microphone access when prompted

### Uninstall

```bash
./Scripts/uninstall.sh
```

Removes the app, all data, caches, preferences, and privacy permissions — no trace left.

---

## Development

Requirements: macOS 14.0+, Xcode 15+, Python 3.11+ (for choreography generation)

### Build & Run

```bash
xcodegen generate    # after adding/removing files
xcodebuild -scheme MacDance -configuration Debug build
xcodebuild test -scheme MacDance -destination 'platform=macOS'
```

Or open `MacDance.xcodeproj` in Xcode and hit Run.

### Choreography Generation

Generates dance choreography from audio using librosa beat tracking (with an EDGE model path for future AI-generated moves).

```bash
cd Scripts && python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

./Scripts/build_binary.sh          # full (includes torch/EDGE)
./Scripts/build_binary.sh --light  # template-only, smaller binary
```

### Clean Up

```bash
rm -rf ~/Library/DerivedData/MacDance-*   # Xcode build cache
rm -rf build/                              # installer artifacts
```

This removes all dev-side artifacts. Nothing else is created on your machine during development.

### Build Installer

```bash
./Scripts/build_installer.sh                  # archive → notarize → DMG
./Scripts/build_installer.sh --skip-notarize  # local testing without Apple ID
```

**One-time setup:**

1. Install a Developer ID certificate (Xcode → Settings → Accounts → Manage Certificates)
2. Store notarization credentials:
   ```bash
   xcrun notarytool store-credentials "MacDance" \
     --apple-id you@email.com --team-id XXXXXXXXXX
   ```
3. Optionally: `brew install create-dmg` for a polished DMG window

### Architecture

| Layer | Files | Responsibility |
|-------|-------|---------------|
| Views | `*View.swift` | Display-only, read from `AppState` |
| State | `AppState.swift` | `@Observable @MainActor` single source of truth |
| Engine | `ScoringEngine.swift` | Beat-interval scoring, combo tracking |
| Pose | `PoseDetector.swift` | Camera + Apple Vision body pose detection |
| Audio | `AudioPlayer.swift` | AVAudioEngine playback, tempo control, practice mode |
| Render | `GhostRenderer.swift`, `MovePreviewRenderer.swift` | Metal rendering |
| Generation | `GenerationManager.swift` | Launches Python pipeline, streams progress |

## License

Copyright © 2024 MacDance. All rights reserved.
