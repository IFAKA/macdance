# MacDance

## Stack
- Swift 6, SwiftUI, macOS 14+
- AVFoundation + AVAudioEngine (audio)
- Apple Vision (VNDetectHumanBodyPoseRequest — body pose)
- Metal (renderer: GhostRenderer, MovePreviewRenderer)
- SceneKit NOT used — Metal only
- Python 3.11 + PyTorch (MPS) for generation — compiled to python_bin

## Build
xcodebuild -scheme MacDance -configuration Debug build

## Test
xcodebuild test -scheme MacDance -destination 'platform=macOS'

## Run
Open MacDance.xcodeproj in Xcode → Run, OR:
xcodebuild -scheme MacDance run

## Architecture rules
- ONE source of truth per concept. If a model exists, use it — don't redefine inline.
- All camera/AVFoundation work: inside PoseDetector.swift only. Never in views.
- All audio: inside AudioPlayer.swift only. Never in views.
- All Metal rendering: inside GhostRenderer.swift / MovePreviewRenderer.swift only.
- Scoring logic: ScoringEngine.swift only. Zero scoring code in views.
- Views are display-only: read from @Observable AppState, emit user actions.
- No force-unwraps (!). No try! outside of tests.
- Swift 6 strict concurrency: all shared state in actors. No DispatchQueue.main.async — use @MainActor.
- Never write TODO comments. Either implement it or file a task.

## File naming
- Views: [Name]View.swift
- Engine components: [Name].swift (e.g. ScoringEngine.swift)
- Models: [Name].swift (e.g. Song.swift, Choreography.swift)

## Do NOT
- Add docstrings or comments to code that wasn't changed
- Refactor code outside the scope of the current task
- Use UIKit (macOS only, AppKit bridging via SwiftUI where needed)
- Create new files without checking if logic belongs in an existing one
- Touch python_bin or Scripts/ from the Swift side — GenerationManager.swift only

## Choreography format
All choreo is 2D normalized [0,1] joint positions — same space as Apple Vision output.
See choreo.json spec in plan file.
