import SwiftUI
import MetalKit
@preconcurrency import AVFoundation

struct GameView: View {
    let song: Song
    @Environment(AppState.self) private var appState

    @State private var audioPlayer = AudioPlayer()
    @State private var poseDetector = PoseDetector()
    @State private var scoringEngine = ScoringEngine()
    @State private var choreoPlayer = ChoreoPlayer()
    @State private var soundEffects = SoundEffects()
    @State private var ghostRenderer: GhostRenderer? = GhostRenderer()

    @State private var isPaused = false
    @State private var isCountingIn = false
    @State private var countInBeat = 0
    @State private var isTrackingLost = false
    @State private var choreo: Choreography?
    @State private var scoreDisplayTier: ScoreTier?
    @State private var lastTierFlashTime: Date = .distantPast
    @State private var gameLoopTimer: Timer?
    @State private var lastScoredBeatIndex: Int = -1
    @State private var deactivationObserver: Any?
    @State private var comboScaleEffect: CGFloat = 1.0
    @State private var previousComboMilestone: Int = 0
    @State private var isPracticing = false

    private var displayScore: String {
        let s = scoringEngine.totalScore
        return s >= 99_999_999 ? "MAX" : "\(s)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Darkened camera background
            CameraBackgroundView(session: poseDetector.captureSession)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.6))

            // Metal ghost avatar
            if let renderer = ghostRenderer {
                MetalGhostView(renderer: renderer)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // HUD layer
            gameHUD

            // Move preview strip
            previewStripLayer

            if isTrackingLost {
                trackingLostOverlay
            }

            if isCountingIn {
                countInOverlay
            }

            if isPaused {
                PauseOverlayView(
                    onResume: resumeGame,
                    onRestart: restartGame,
                    onPractice: enterPracticeMode,
                    onExit: exitToLibrary
                )
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .task {
            await setupGame()
        }
        .onDisappear {
            teardown()
        }
        .onKeyPress(.space) {
            togglePause()
            return .handled
        }
        .onKeyPress(.escape) {
            togglePause()
            return .handled
        }
    }

    // MARK: - HUD

    private var gameHUD: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayScore)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            scoringEngine.combo.count >= 3
                                ? Color(red: 1, green: 0.85, blue: 0.1)
                                : .white
                        )
                        .shadow(
                            color: scoringEngine.combo.count >= 3
                                ? Color(red: 1, green: 0.85, blue: 0.1).opacity(0.6)
                                : .clear,
                            radius: scoringEngine.combo.count >= 10 ? 20 : 10
                        )
                        .scaleEffect(comboScaleEffect)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.2), value: scoringEngine.totalScore)

                    if scoringEngine.combo.count >= 3 {
                        HStack(spacing: 4) {
                            Text("×\(String(format: "%.1f", scoringEngine.combo.multiplier))")
                                .font(.system(size: 16, weight: .bold))
                            Text("COMBO \(scoringEngine.combo.count)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.1))
                        .scaleEffect(comboScaleEffect)
                    }
                }
                .padding(.leading, 32)
                .padding(.top, 32)

                Spacer()

                // PiP camera (bottom-left per plan, but top-right works too)
                pipCameraView
                    .padding(.trailing, 20)
                    .padding(.top, 20)
            }

            if appState.upperBodyOnly {
                HStack {
                    Spacer()
                    Text("Upper Body Mode")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(white: 0.2).opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.trailing, 20)
                        .padding(.top, 150)
                    Spacer().frame(width: 0)
                }
            }

            if isPracticing {
                Text("Practice Mode — 0.5x")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.15))
                    .clipShape(Capsule())
            }

            Spacer()

            if let tier = scoreDisplayTier {
                Text(tier.rawValue)
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(tier.color)
                    .shadow(color: tier.color.opacity(0.8), radius: 20)
                    .transition(.scale(scale: 1.5).combined(with: .opacity))
                    .id(lastTierFlashTime)
            }

            Spacer()
        }
        .animation(.spring(response: 0.15), value: scoreDisplayTier?.rawValue)
    }

    private var previewStripLayer: some View {
        VStack {
            Spacer()
            if let state = choreoPlayer.state {
                MovePreviewStrip(
                    currentFrame: state.currentFrame,
                    upcomingFrames: state.upcomingFrames
                )
            }
        }
    }

    private var pipCameraView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
            PiPCameraView(session: poseDetector.captureSession)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(width: 180, height: 120)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private var trackingLostOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                Text("Step into frame")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .transition(.opacity)
    }

    private var countInOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(countInBeat > 0 ? "\(5 - countInBeat)" : "")
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.3), radius: 20)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring(response: 0.2), value: countInBeat)

                Text("Get ready!")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(white: 0.7))
            }
        }
    }

    // MARK: - Game lifecycle

    private func setupGame() async {
        scoringEngine.upperBodyOnly = appState.upperBodyOnly
        await poseDetector.requestPermissionAndStart()

        poseDetector.onTrackingLost = {
            isTrackingLost = true
        }
        poseDetector.onTrackingRestored = {
            isTrackingLost = false
        }

        if let choreoData = try? Data(contentsOf: song.choreoURL),
           let decoded = try? JSONDecoder().decode(Choreography.self, from: choreoData) {
            choreo = decoded
            choreoPlayer.load(decoded)
        }

        // App deactivation → auto-pause
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if !isPaused && !isCountingIn {
                    pauseGame()
                }
            }
        }

        await startCountIn()
    }

    private func startCountIn() async {
        isCountingIn = true
        let bpm = choreo?.bpm ?? 120
        let beatInterval = 60.0 / bpm

        for beat in 1...4 {
            countInBeat = beat
            soundEffects.playTick(accented: beat == 1)
            ghostRenderer?.pulseBeat()
            try? await Task.sleep(for: .seconds(beatInterval))
        }

        isCountingIn = false
        countInBeat = 0

        do {
            try audioPlayer.load(url: song.mp3URL)
            try audioPlayer.play()
        } catch {
            return
        }

        choreoPlayer.start(audioTime: 0)
        startGameLoop()
    }

    private func startGameLoop() {
        lastScoredBeatIndex = -1

        // Single loop at 60fps that drives both ghost rendering and scoring
        gameLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [self] _ in
            Task { @MainActor in
                guard !self.isPaused else { return }
                let time = self.audioPlayer.currentTime

                // Update choreo state
                self.choreoPlayer.update(audioTime: time)

                // Update ghost renderer with current choreo frame
                if let frame = self.choreoPlayer.state?.currentFrame {
                    self.ghostRenderer?.updatePose(frame)
                }

                // Score at beat intervals only (not every frame)
                if let c = self.choreo, !self.isTrackingLost {
                    let beatInterval = 60.0 / c.bpm
                    let currentBeatIndex = Int(time / beatInterval)
                    if currentBeatIndex > self.lastScoredBeatIndex {
                        self.lastScoredBeatIndex = currentBeatIndex
                        self.scoreOnBeat()
                    }
                }
            }
        }

        audioPlayer.onFinished = {
            endGame()
        }
    }

    private func scoreOnBeat() {
        guard let pose = poseDetector.currentPose,
              let refFrame = choreoPlayer.state?.currentFrame else { return }

        let result = scoringEngine.evaluate(detected: pose.joints, reference: refFrame)
        lastTierFlashTime = Date()

        withAnimation(.spring(response: 0.15)) {
            scoreDisplayTier = result.tier
        }

        soundEffects.play(tier: result.tier)

        // Update ghost glow based on combo
        ghostRenderer?.setComboMultiplier(result.comboMultiplier)

        // Scale particle burst with combo
        let comboCount = scoringEngine.combo.count
        if result.tier == .yeah || result.tier == .perfect {
            let particlesPerJoint = comboCount >= 10 ? 20 : (comboCount >= 5 ? 14 : 8)
            ghostRenderer?.triggerBurst(at: [.leftWrist, .rightWrist], particlesPerJoint: particlesPerJoint)
        } else if result.tier == .miss {
            ghostRenderer?.flashMissed(result.missedJoints)
        }

        // Combo milestone swell at 3, 5, 10
        let milestone = comboCount >= 10 ? 10 : (comboCount >= 5 ? 5 : (comboCount >= 3 ? 3 : 0))
        if milestone > previousComboMilestone && milestone > 0 {
            soundEffects.playComboMilestone()
            withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                comboScaleEffect = 1.3
            }
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation(.spring(response: 0.3)) {
                    comboScaleEffect = 1.0
                }
            }
        }
        previousComboMilestone = milestone

        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.2)) {
                if scoreDisplayTier == result.tier {
                    scoreDisplayTier = nil
                }
            }
        }
    }

    // MARK: - Controls

    private func togglePause() {
        if isPaused {
            resumeGame()
        } else {
            pauseGame()
        }
    }

    private func pauseGame() {
        audioPlayer.pause()
        gameLoopTimer?.invalidate()
        withAnimation { isPaused = true }
    }

    private func resumeGame() {
        if isPracticing { exitPracticeMode() }
        withAnimation { isPaused = false }
        do {
            try audioPlayer.resume()
            startGameLoop()
        } catch {}
    }

    private func restartGame() {
        if isPracticing { exitPracticeMode() }
        isPaused = false
        gameLoopTimer?.invalidate()
        scoringEngine.reset()
        previousComboMilestone = 0
        comboScaleEffect = 1.0
        ghostRenderer?.setComboMultiplier(1.0)
        audioPlayer.stop()
        choreoPlayer.stop()
        Task { await startCountIn() }
    }

    private func enterPracticeMode() {
        guard let c = choreo else {
            isPaused = false
            return
        }

        let beatInterval = 60.0 / c.bpm
        let phraseLength = beatInterval * 8
        let time = audioPlayer.currentTime
        let phraseStart = floor(time / phraseLength) * phraseLength
        let phraseEnd = min(phraseStart + phraseLength, c.totalDuration)

        audioPlayer.setRate(0.5)
        audioPlayer.setLoopRange(start: phraseStart, end: phraseEnd)

        isPracticing = true
        isPaused = false
        do {
            try audioPlayer.seek(to: phraseStart)
            startGameLoop()
        } catch {}
    }

    private func exitPracticeMode() {
        audioPlayer.clearLoop()
        isPracticing = false
    }

    private func exitToLibrary() {
        teardown()
        appState.backToLibrary()
    }

    private func endGame() {
        gameLoopTimer?.invalidate()
        appState.gameEnded(
            song: song,
            score: scoringEngine.totalScore,
            maxCombo: scoringEngine.maxCombo
        )
    }

    private func teardown() {
        gameLoopTimer?.invalidate()
        audioPlayer.stop()
        poseDetector.stop()
        choreoPlayer.stop()
        if let obs = deactivationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

// MARK: - Camera views using AVCaptureSession (not shared preview layers)

struct CameraBackgroundView: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        if let session {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(previewLayer)
            context.coordinator.previewLayer = previewLayer
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.previewLayer?.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

struct PiPCameraView: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        if let session {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(previewLayer)
            context.coordinator.previewLayer = previewLayer
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.previewLayer?.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

struct MetalGhostView: NSViewRepresentable {
    let renderer: GhostRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        let delegate = GhostRendererDelegate(renderer: renderer)
        context.coordinator.delegate = delegate
        renderer.configureView(view, delegate: delegate)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var delegate: GhostRendererDelegate?
    }
}
