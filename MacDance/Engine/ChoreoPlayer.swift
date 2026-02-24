import Foundation
import CoreGraphics

struct ChoreoPlayerState {
    var currentFrame: PoseFrame
    var upcomingFrames: [PoseFrame]
    var isInCountIn: Bool
    var countInBeat: Int
}

@Observable
@MainActor
final class ChoreoPlayer {
    private(set) var state: ChoreoPlayerState?
    private var choreography: Choreography?
    private var bpm: Double = 120
    private(set) var isPlaying: Bool = false
    private var startAudioTime: TimeInterval = 0
    private var displayLink: Timer?

    var onBeat: ((Int) -> Void)?

    func load(_ choreo: Choreography) {
        choreography = choreo
        bpm = choreo.bpm
    }

    func start(audioTime: TimeInterval) {
        startAudioTime = audioTime
        isPlaying = true
        startDisplayLink()
    }

    func stop() {
        isPlaying = false
        displayLink?.invalidate()
        displayLink = nil
        state = nil
    }

    func update(audioTime: TimeInterval) {
        guard let choreo = choreography, isPlaying else { return }
        let frame = choreo.frame(at: audioTime)
        let upcoming = choreo.upcomingKeyframes(after: audioTime, count: 4)
        state = ChoreoPlayerState(
            currentFrame: frame,
            upcomingFrames: upcoming,
            isInCountIn: false,
            countInBeat: 0
        )
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let _ = self.choreography else { return }
            }
        }
    }

    func beatInterval() -> TimeInterval {
        60.0 / bpm
    }

    func countInFrames(bpm: Double) -> [PoseFrame] {
        guard let choreo = choreography else { return [] }
        return Array(choreo.frames.prefix(4))
    }
}
