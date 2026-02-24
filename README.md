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

**Requirements:** macOS 14.0+, Xcode 15+, Python 3.11+

### Setup

```bash
# Generate the Xcode project
xcodegen generate

# Set up the Python env for choreography generation
cd Scripts && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt && cd ..

# Open in Xcode and hit Run
open MacDance.xcodeproj
```

To build the bundled Python binary that ships with the app:

```bash
./Scripts/build_binary.sh          # full (includes torch/EDGE)
./Scripts/build_binary.sh --light  # template-only, smaller binary
```

### Tests

```bash
xcodebuild test -scheme MacDance -destination 'platform=macOS'
```

### Ship a Release

```bash
./Scripts/build_installer.sh                  # archive → notarize → DMG
./Scripts/build_installer.sh --skip-notarize  # local testing
```

<details>
<summary>First-time notarization setup</summary>

1. Install a Developer ID certificate (Xcode → Settings → Accounts → Manage Certificates)
2. Store credentials:
   ```bash
   xcrun notarytool store-credentials "MacDance" \
     --apple-id you@email.com --team-id XXXXXXXXXX
   ```
3. Optional: `brew install create-dmg` for a polished DMG window
</details>

### Clean Up

```bash
rm -rf ~/Library/DerivedData/MacDance-*   # Xcode build cache
rm -rf build/                              # installer artifacts
```

### Architecture

| Layer | Key File(s) | Role |
|-------|-------------|------|
| State | `AppState.swift` | Single source of truth (`@Observable @MainActor`) |
| Views | `*View.swift` | Display-only — read state, emit actions |
| Engine | `ScoringEngine.swift` | Beat-interval scoring, combos |
| Pose | `PoseDetector.swift` | Camera + Vision body pose |
| Audio | `AudioPlayer.swift` | Playback, tempo, practice mode |
| Render | `GhostRenderer.swift` | Metal rendering |
| Generation | `GenerationManager.swift` | Python pipeline bridge |

## License

Copyright © 2024 MacDance. All rights reserved.
