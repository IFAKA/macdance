# MacDance

A macOS dance game that uses your camera to track body poses and score your moves against choreographed routines. Built with Swift 6, SwiftUI, Metal, and Apple Vision.

## Requirements

- macOS 14.0+
- Xcode 15+
- Camera (for pose tracking)
- Python 3.11+ (for choreography generation only)

## Build & Run

```bash
# Generate Xcode project (after adding/removing files)
xcodegen generate

# Build
xcodebuild -scheme MacDance -configuration Debug build

# Test
xcodebuild test -scheme MacDance -destination 'platform=macOS'
```

Or open `MacDance.xcodeproj` in Xcode and hit Run.

## Choreography Generation

MacDance generates dance choreography from audio using a Python pipeline (librosa beat tracking, with an EDGE model path for future AI-generated moves).

```bash
# Set up Python environment
cd Scripts && python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Build the bundled binary for the app
./Scripts/build_binary.sh          # full (includes torch/EDGE)
./Scripts/build_binary.sh --light  # template-only, smaller binary
```

## Distribution

### Build Installer

```bash
./Scripts/build_installer.sh                # archive → notarize → DMG
./Scripts/build_installer.sh --skip-notarize  # local testing
```

**One-time setup:**

1. Install a Developer ID certificate (Xcode → Settings → Accounts → Manage Certificates)
2. Store notarization credentials:
   ```bash
   xcrun notarytool store-credentials "MacDance" \
     --apple-id you@email.com --team-id XXXXXXXXXX
   ```
3. Optionally install `create-dmg` for a polished DMG window: `brew install create-dmg`

### Uninstall

```bash
./Scripts/uninstall.sh
```

Removes the app, sandboxed data, caches, preferences, and privacy permissions — no trace left.

## Architecture

| Layer | Files | Responsibility |
|-------|-------|---------------|
| Views | `*View.swift` | Display-only, read from `AppState` |
| State | `AppState.swift` | `@Observable @MainActor` single source of truth |
| Engine | `ScoringEngine.swift` | Beat-interval scoring, combo tracking |
| Pose | `PoseDetector.swift` | Camera + Apple Vision body pose detection |
| Audio | `AudioPlayer.swift` | AVAudioEngine playback, tempo control, practice mode |
| Render | `GhostRenderer.swift`, `MovePreviewRenderer.swift` | Metal-based ghost/preview rendering |
| Generation | `GenerationManager.swift` | Launches Python pipeline, streams progress |

## License

Copyright © 2024 MacDance. All rights reserved.
