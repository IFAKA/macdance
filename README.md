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

Requires macOS 14.0+, Xcode 15+, Python 3.11+

```bash
xcodegen generate && open MacDance.xcodeproj     # run
rm -rf ~/Library/DerivedData/MacDance-* build/   # clean up
```

## License

Copyright © 2024 MacDance. All rights reserved.
