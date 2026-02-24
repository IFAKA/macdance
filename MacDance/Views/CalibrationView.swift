import SwiftUI
@preconcurrency import AVFoundation

struct CalibrationView: View {
    let song: Song
    @Environment(AppState.self) private var appState
    @State private var poseDetector = PoseDetector()
    @State private var bodyDetected = false
    @State private var detectedSince: Date?
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var lightingWarning: Bool = false
    @State private var isUpperBodyOnly: Bool = false
    @State private var multipleBodyWarning: Bool = false
    @State private var distanceHint: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if poseDetector.cameraPermissionDenied {
                cameraPermissionView
            } else if poseDetector.cameraInUse {
                cameraInUseView
            } else {
                cameraFeedView
            }
        }
        .task {
            await poseDetector.requestPermissionAndStart()
            poseDetector.onPoseUpdate = { pose in
                handlePoseUpdate(pose)
            }
        }
        .onDisappear {
            poseDetector.stop()
            autoAdvanceTask?.cancel()
        }
    }

    private var cameraFeedView: some View {
        ZStack {
            CalibrationCameraView(session: poseDetector.captureSession)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.3))

            bodyOutline

            VStack {
                Spacer()
                instructionPanel
                    .padding(.bottom, 60)
            }

            if let hint = distanceHint {
                Text(hint)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if multipleBodyWarning {
                Text("Multiple people detected — the closest dancer is being tracked.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 20)
            }

            if lightingWarning {
                VStack {
                    Text("Lighting looks poor — try a light facing you")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.yellow.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 20)
                    Spacer()
                }
            }

            if isUpperBodyOnly {
                VStack {
                    Spacer()
                    Text("Only your upper body is visible. Dance with your arms — leg scoring disabled.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 130)
                }
            }

            if poseDetector.availableCameras.count > 1 {
                VStack {
                    HStack {
                        Spacer()
                        cameraSelectorMenu
                            .padding(.top, 16)
                            .padding(.trailing, 20)
                    }
                    Spacer()
                }
            }
        }
    }

    private var bodyOutline: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w * 0.5
            let cy = h * 0.45
            let scale = min(w, h) * 0.55

            ZStack {
                if let pose = poseDetector.currentPose {
                    Canvas { context, size in
                        drawDetectedPose(context: context, pose: pose, size: size)
                    }
                    .frame(width: w, height: h)
                } else {
                    RoundedRectangle(cornerRadius: 60)
                        .stroke(
                            bodyDetected ? Color.green.opacity(0.8) : Color.white.opacity(0.25),
                            style: StrokeStyle(lineWidth: 2, dash: bodyDetected ? [] : [8, 6])
                        )
                        .frame(width: scale * 0.45, height: scale)
                        .position(x: cx, y: cy)
                        .animation(.easeInOut(duration: 0.3), value: bodyDetected)
                }
            }
        }
    }

    private func drawDetectedPose(context: GraphicsContext, pose: DetectedPose, size: CGSize) {
        let connections: [(JointName, JointName)] = [
            (.leftShoulder, .rightShoulder),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
            (.leftHip, .rightHip),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
        ]

        let color = bodyDetected ? Color.green.opacity(0.9) : Color.white.opacity(0.6)

        for (a, b) in connections {
            guard let pa = pose.joints[a.rawValue], let pb = pose.joints[b.rawValue] else { continue }
            var path = Path()
            path.move(to: CGPoint(x: pa.x * size.width, y: pa.y * size.height))
            path.addLine(to: CGPoint(x: pb.x * size.width, y: pb.y * size.height))
            context.stroke(path, with: .color(color), lineWidth: 3)
        }

        for joint in JointName.allCases {
            guard let p = pose.joints[joint.rawValue] else { continue }
            let pt = CGPoint(x: p.x * size.width, y: p.y * size.height)
            context.fill(
                Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                with: .color(color)
            )
        }
    }

    private var instructionPanel: some View {
        VStack(spacing: 16) {
            if bodyDetected {
                Label("Full body detected", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.green)
            } else {
                Text("Step back until your full body is visible")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if bodyDetected {
                Text("Starting in a moment...")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(white: 0.6))
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var cameraSelectorMenu: some View {
        Menu {
            ForEach(poseDetector.availableCameras, id: \.uniqueID) { camera in
                Button(camera.localizedName) {
                    poseDetector.selectCamera(camera)
                }
            }
        } label: {
            Label("Camera", systemImage: "camera.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var cameraPermissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.4))
            Text("Camera access required")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("MacDance needs camera access to track your dance moves.")
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
            .font(.system(size: 16, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cameraInUseView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.4))
            Text("Camera is in use by another app")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("Close Zoom, FaceTime, or other apps using the camera, then try again.")
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Try Again") {
                Task { await poseDetector.startSession() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
            .font(.system(size: 16, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handlePoseUpdate(_ pose: DetectedPose?) {
        guard let pose = pose else {
            bodyDetected = false
            detectedSince = nil
            autoAdvanceTask?.cancel()
            return
        }

        multipleBodyWarning = pose.bodyCount > 1
        lightingWarning = pose.confidence < 0.4

        let hasLowerBody = pose.joints[JointName.leftKnee.rawValue] != nil ||
                           pose.joints[JointName.rightKnee.rawValue] != nil
        isUpperBodyOnly = !hasLowerBody

        let hasFullBody = pose.joints[JointName.leftShoulder.rawValue] != nil &&
                          pose.joints[JointName.leftHip.rawValue] != nil

        if hasFullBody && pose.confidence > 0.5 {
            if !bodyDetected {
                bodyDetected = true
                detectedSince = Date()
                autoAdvanceTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        appState.calibrationComplete(for: song, upperBodyOnly: isUpperBodyOnly)
                    }
                }
            }
        } else {
            bodyDetected = false
            detectedSince = nil
            autoAdvanceTask?.cancel()
        }
    }
}

struct CalibrationCameraView: NSViewRepresentable {
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
