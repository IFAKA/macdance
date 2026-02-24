@preconcurrency import AVFoundation
import Vision
import Foundation
import CoreGraphics

struct DetectedPose {
    let joints: [String: CGPoint]
    let confidence: Float
    let bodyCount: Int
}

@Observable
@MainActor
final class PoseDetector: NSObject {
    private(set) var currentPose: DetectedPose?
    private(set) var isRunning: Bool = false
    private(set) var cameraPermissionDenied: Bool = false
    private(set) var cameraInUse: Bool = false
    private(set) var availableCameras: [AVCaptureDevice] = []
    private(set) var selectedCamera: AVCaptureDevice?

    var onPoseUpdate: ((DetectedPose?) -> Void)?
    var onTrackingLost: (() -> Void)?
    var onTrackingRestored: (() -> Void)?

    private let session = AVCaptureSession()

    var captureSession: AVCaptureSession? {
        isRunning ? session : nil
    }
    private var videoOutput: AVCaptureVideoDataOutput?
    private var trackingLostTimer: Timer?
    private var wasTracking: Bool = false
    private let requestQueue = DispatchSerialQueue(label: "com.macdance.posedetector")

    func requestPermissionAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await startSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await startSession()
            } else {
                cameraPermissionDenied = true
            }
        case .denied, .restricted:
            cameraPermissionDenied = true
        @unknown default:
            cameraPermissionDenied = true
        }
    }

    func startSession() async {
        discoverCameras()
        guard let device = selectedCamera ?? availableCameras.first else { return }
        await configureSession(device: device)
    }

    private func discoverCameras() {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .front
        )
        availableCameras = discovery.devices
        if selectedCamera == nil {
            selectedCamera = availableCameras.first(where: { $0.position == .front }) ?? availableCameras.first
        }
    }

    private func configureSession(device: AVCaptureDevice) async {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                cameraInUse = true
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            cameraInUse = true
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: requestQueue)
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        videoOutput = output
        session.commitConfiguration()

        let captureSession = session
        Task.detached {
            captureSession.startRunning()
            Task { @MainActor in
                self.isRunning = true
            }
        }
    }

    func stop() {
        session.stopRunning()
        isRunning = false
        trackingLostTimer?.invalidate()
    }

    func selectCamera(_ device: AVCaptureDevice) {
        selectedCamera = device
        Task {
            await configureSession(device: device)
        }
    }

    private func handleTrackingLost() {
        if wasTracking {
            wasTracking = false
            trackingLostTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onTrackingLost?()
                }
            }
        }
    }

    private func handleTrackingRestored() {
        trackingLostTimer?.invalidate()
        if !wasTracking {
            wasTracking = true
            onTrackingRestored?()
        }
    }
}

extension PoseDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observations = request.results, !observations.isEmpty else {
            Task { @MainActor in
                self.currentPose = nil
                self.onPoseUpdate?(nil)
                self.handleTrackingLost()
            }
            return
        }

        let primary = selectPrimaryBody(from: observations)
        let joints = extractJoints(from: primary)
        let confidence = Float(primary.confidence)

        let pose = DetectedPose(joints: joints, confidence: confidence, bodyCount: observations.count)
        Task { @MainActor in
            self.currentPose = pose
            self.onPoseUpdate?(pose)
            self.handleTrackingRestored()
        }
    }

    nonisolated private func selectPrimaryBody(from observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation {
        guard observations.count > 1 else { return observations[0] }
        return observations.max(by: { a, b in
            let aArea = bodyArea(a)
            let bArea = bodyArea(b)
            return aArea < bArea
        }) ?? observations[0]
    }

    nonisolated private func bodyArea(_ obs: VNHumanBodyPoseObservation) -> CGFloat {
        guard let points = try? obs.recognizedPoints(.all) else { return 0 }
        let xs = points.values.map(\.location.x)
        let ys = points.values.map(\.location.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return (maxX - minX) * (maxY - minY)
    }

    nonisolated private func extractJoints(from observation: VNHumanBodyPoseObservation) -> [String: CGPoint] {
        guard let points = try? observation.recognizedPoints(.all) else { return [:] }

        let mapping: [VNHumanBodyPoseObservation.JointName: String] = [
            .nose: JointName.nose.rawValue,
            .leftEye: JointName.leftEye.rawValue,
            .rightEye: JointName.rightEye.rawValue,
            .leftEar: JointName.leftEar.rawValue,
            .rightEar: JointName.rightEar.rawValue,
            .leftShoulder: JointName.leftShoulder.rawValue,
            .rightShoulder: JointName.rightShoulder.rawValue,
            .leftElbow: JointName.leftElbow.rawValue,
            .rightElbow: JointName.rightElbow.rawValue,
            .leftWrist: JointName.leftWrist.rawValue,
            .rightWrist: JointName.rightWrist.rawValue,
            .leftHip: JointName.leftHip.rawValue,
            .rightHip: JointName.rightHip.rawValue,
            .leftKnee: JointName.leftKnee.rawValue,
            .rightKnee: JointName.rightKnee.rawValue,
            .leftAnkle: JointName.leftAnkle.rawValue,
            .rightAnkle: JointName.rightAnkle.rawValue
        ]

        var joints: [String: CGPoint] = [:]
        for (vnJoint, name) in mapping {
            if let point = points[vnJoint], point.confidence > 0.3 {
                joints[name] = CGPoint(x: point.location.x, y: 1.0 - point.location.y)
            }
        }
        return joints
    }
}
