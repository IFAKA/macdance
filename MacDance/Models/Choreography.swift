import Foundation
import CoreGraphics

struct PoseFrame: Codable {
    let timestamp: TimeInterval
    let joints: [String: CGPoint]

    func joint(_ name: JointName) -> CGPoint? {
        joints[name.rawValue]
    }
}

struct Choreography: Codable {
    let songMD5: String
    let bpm: Double
    let frames: [PoseFrame]
    let totalDuration: TimeInterval

    func frame(at time: TimeInterval) -> PoseFrame {
        guard !frames.isEmpty else {
            return PoseFrame(timestamp: time, joints: [:])
        }
        guard frames.count > 1 else {
            return frames[0]
        }

        let lastIndex = frames.count - 1
        if time <= frames[0].timestamp { return frames[0] }
        if time >= frames[lastIndex].timestamp { return frames[lastIndex] }

        var lo = 0
        var hi = lastIndex
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if frames[mid].timestamp <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let a = frames[lo]
        let b = frames[hi]
        let t = (time - a.timestamp) / (b.timestamp - a.timestamp)
        return interpolated(from: a, to: b, t: t)
    }

    func upcomingKeyframes(after time: TimeInterval, count: Int) -> [PoseFrame] {
        let future = frames.filter { $0.timestamp > time }
        return Array(future.prefix(count))
    }

    /// Calculates difficulty 1-4 based on joint angle variance between consecutive frames.
    /// Higher variance = more movement = harder choreography.
    func calculateDifficulty() -> Int {
        guard frames.count >= 2 else { return 1 }

        let scoringPairs: [(JointName, JointName)] = [
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.leftHip, .leftKnee), (.rightHip, .rightKnee)
        ]

        var totalAngleChange: Float = 0
        var comparisons: Int = 0

        for i in 1..<frames.count {
            let prev = frames[i - 1]
            let curr = frames[i]

            for (parent, child) in scoringPairs {
                guard let pp = prev.joint(parent), let pc = prev.joint(child),
                      let cp = curr.joint(parent), let cc = curr.joint(child) else { continue }

                let prevAngle = atan2(Float(pc.y - pp.y), Float(pc.x - pp.x))
                let currAngle = atan2(Float(cc.y - cp.y), Float(cc.x - cp.x))
                var diff = abs(currAngle - prevAngle)
                if diff > .pi { diff = 2 * .pi - diff }
                totalAngleChange += diff
                comparisons += 1
            }
        }

        guard comparisons > 0 else { return 1 }
        let avgChange = totalAngleChange / Float(comparisons)

        switch avgChange {
        case 0..<0.15: return 1  // Easy
        case 0.15..<0.35: return 2  // Medium
        case 0.35..<0.6: return 3  // Hard
        default: return 4  // Expert
        }
    }

    private func interpolated(from a: PoseFrame, to b: PoseFrame, t: Double) -> PoseFrame {
        var joints: [String: CGPoint] = [:]
        let allKeys = Set(a.joints.keys).union(b.joints.keys)
        for key in allKeys {
            if let pa = a.joints[key], let pb = b.joints[key] {
                joints[key] = CGPoint(
                    x: pa.x + (pb.x - pa.x) * t,
                    y: pa.y + (pb.y - pa.y) * t
                )
            } else if let pa = a.joints[key] {
                joints[key] = pa
            } else if let pb = b.joints[key] {
                joints[key] = pb
            }
        }
        return PoseFrame(timestamp: a.timestamp + (b.timestamp - a.timestamp) * t, joints: joints)
    }
}

enum JointName: String, CaseIterable, Codable {
    case nose
    case leftEye = "left_eye"
    case rightEye = "right_eye"
    case leftEar = "left_ear"
    case rightEar = "right_ear"
    case leftShoulder = "left_shoulder"
    case rightShoulder = "right_shoulder"
    case leftElbow = "left_elbow"
    case rightElbow = "right_elbow"
    case leftWrist = "left_wrist"
    case rightWrist = "right_wrist"
    case leftHip = "left_hip"
    case rightHip = "right_hip"
    case leftKnee = "left_knee"
    case rightKnee = "right_knee"
    case leftAnkle = "left_ankle"
    case rightAnkle = "right_ankle"

    var weight: Float {
        switch self {
        case .leftShoulder, .rightShoulder,
             .leftElbow, .rightElbow,
             .leftWrist, .rightWrist:
            return 0.40 / 6
        case .leftHip, .rightHip,
             .leftKnee, .rightKnee,
             .leftAnkle, .rightAnkle:
            return 0.30 / 6
        default:
            return 0.30 / 5
        }
    }
}
