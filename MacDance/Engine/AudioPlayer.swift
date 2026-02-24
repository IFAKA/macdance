@preconcurrency import AVFoundation
import Foundation

@Observable
@MainActor
final class AudioPlayer {
    private var engine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var timePitch: AVAudioUnitTimePitch
    private var audioFile: AVAudioFile?
    private var pauseTime: TimeInterval = 0
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private(set) var isPlaying: Bool = false
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1.0
    private var loopRange: (start: TimeInterval, end: TimeInterval)?

    var currentTime: TimeInterval {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              let file = audioFile else {
            return pauseTime
        }
        let sampleRate = file.processingFormat.sampleRate
        let elapsed = Double(playerTime.sampleTime) / sampleRate
        let time = max(0, min(pauseTime + elapsed, duration))

        if let loop = loopRange, time >= loop.end {
            Task { @MainActor in
                try? self.seek(to: loop.start)
            }
            return loop.start
        }
        return time
    }

    var onFinished: (() -> Void)?

    private nonisolated(unsafe) var interruptionObserver: Any?

    init() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        timePitch = AVAudioUnitTimePitch()
        engine.attach(playerNode)
        engine.attach(timePitch)
        setupNotifications()
    }

    deinit {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func load(url: URL) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        audioFile = file
        duration = Double(file.length) / file.processingFormat.sampleRate
        engine.connect(playerNode, to: timePitch, format: file.processingFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
    }

    func play() throws {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate

        if !engine.isRunning {
            try engine.start()
        }

        let startFrame = AVAudioFramePosition(pauseTime * sampleRate)
        let totalFrames = file.length
        let remainingFrames = AVAudioFrameCount(max(0, totalFrames - startFrame))

        guard remainingFrames > 0 else {
            isPlaying = false
            onFinished?()
            return
        }

        playerNode.stop()
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.isPlaying = false
                self.onFinished?()
            }
        }
        scheduledStartFrame = startFrame
        playerNode.play()
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        pauseTime = currentTime
        playerNode.stop()
        isPlaying = false
    }

    func resume() throws {
        try play()
    }

    func seek(to time: TimeInterval) throws {
        let wasPlaying = isPlaying
        if wasPlaying {
            playerNode.stop()
            isPlaying = false
        }
        pauseTime = max(0, min(time, duration))
        if wasPlaying {
            try play()
        }
    }

    func stop() {
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        pauseTime = 0
        isPlaying = false
    }

    func setVolume(_ volume: Float) {
        playerNode.volume = volume
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        timePitch.rate = newRate
    }

    func setLoopRange(start: TimeInterval, end: TimeInterval) {
        loopRange = (start: start, end: end)
    }

    func clearLoop() {
        loopRange = nil
        setRate(1.0)
    }

    private func setupNotifications() {
        // On macOS, AVAudioEngine handles configuration changes automatically.
        // We observe engine config changes to detect audio device disconnects.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.pause()
            }
        }
    }
}
