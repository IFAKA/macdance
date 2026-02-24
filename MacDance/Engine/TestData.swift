import Foundation
import CoreGraphics

enum TestData {
    static let bpm: Double = 120
    static let duration: TimeInterval = 30.0

    static func generateTestChoreo() -> Choreography {
        let beatInterval = 60.0 / bpm
        var frames: [PoseFrame] = []
        let totalBeats = Int(duration / beatInterval)

        for beat in 0..<totalBeats {
            let time = Double(beat) * beatInterval
            let phase = Double(beat % 8) / 8.0
            let moveGroup = (beat / 4) % 4

            let joints: [String: CGPoint]
            switch moveGroup {
            case 0: joints = armsUp(phase: phase)
            case 1: joints = sideStep(phase: phase, direction: 1.0)
            case 2: joints = waveArms(phase: phase)
            case 3: joints = sideStep(phase: phase, direction: -1.0)
            default: joints = restPose()
            }

            frames.append(PoseFrame(timestamp: time, joints: joints))
        }

        return Choreography(
            songMD5: "test_demo",
            bpm: bpm,
            frames: frames,
            totalDuration: duration
        )
    }

    static func writeToDisk(at folder: URL) throws {
        let choreo = generateTestChoreo()
        let data = try JSONEncoder().encode(choreo)
        try data.write(to: folder.appendingPathComponent("choreo.json"), options: .atomic)

        let analysis: [String: Any] = [
            "bpm": bpm,
            "duration": duration,
            "beat_times": (0..<Int(duration * bpm / 60)).map { Double($0) * 60.0 / bpm }
        ]
        let analysisData = try JSONSerialization.data(withJSONObject: analysis)
        try analysisData.write(to: folder.appendingPathComponent("analysis.json"), options: .atomic)
    }

    static func generateTestMP3(at url: URL) throws {
        // Generate a minimal WAV file with metronome clicks at 120 BPM
        let sampleRate: Double = 44100
        let totalSamples = Int(duration * sampleRate)
        let beatSamples = Int(60.0 / bpm * sampleRate)

        var samples = [Float](repeating: 0, count: totalSamples)

        // Generate click sound at each beat
        for beat in 0..<Int(duration * bpm / 60) {
            let beatStart = beat * beatSamples
            let clickDuration = min(2000, totalSamples - beatStart)
            let isAccented = beat % 4 == 0
            let freq: Float = isAccented ? 1200 : 800
            let vol: Float = isAccented ? 0.5 : 0.3

            for i in 0..<clickDuration {
                let idx = beatStart + i
                guard idx < totalSamples else { break }
                let t = Float(i) / Float(sampleRate)
                let envelope = max(0, 1.0 - t * 20.0) // Quick decay
                samples[idx] += sin(Float(2.0 * .pi) * freq * t) * envelope * vol
            }

            // Add a low bass note on accented beats
            if isAccented {
                let bassDuration = min(8000, totalSamples - beatStart)
                for i in 0..<bassDuration {
                    let idx = beatStart + i
                    guard idx < totalSamples else { break }
                    let t = Float(i) / Float(sampleRate)
                    let envelope = max(0, 1.0 - t * 5.0)
                    samples[idx] += sin(Float(2.0 * .pi) * 100 * t) * envelope * 0.2
                }
            }
        }

        // Write as WAV
        var data = Data()
        let dataSize = totalSamples * 2
        let fileSize = 44 + dataSize

        func append32(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func appendS16(_ value: Int16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: "RIFF".utf8)
        append32(UInt32(fileSize - 8))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        data.append(contentsOf: "data".utf8)
        append32(UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            appendS16(Int16(clamped * Float(Int16.max)))
        }

        try data.write(to: url, options: .atomic)
    }

    // MARK: - Pose generators

    private static func restPose() -> [String: CGPoint] {
        [
            "nose":            CGPoint(x: 0.50, y: 0.08),
            "left_shoulder":   CGPoint(x: 0.38, y: 0.22),
            "right_shoulder":  CGPoint(x: 0.62, y: 0.22),
            "left_elbow":      CGPoint(x: 0.30, y: 0.38),
            "right_elbow":     CGPoint(x: 0.70, y: 0.38),
            "left_wrist":      CGPoint(x: 0.24, y: 0.50),
            "right_wrist":     CGPoint(x: 0.76, y: 0.50),
            "left_hip":        CGPoint(x: 0.42, y: 0.52),
            "right_hip":       CGPoint(x: 0.58, y: 0.52),
            "left_knee":       CGPoint(x: 0.40, y: 0.70),
            "right_knee":      CGPoint(x: 0.60, y: 0.70),
            "left_ankle":      CGPoint(x: 0.40, y: 0.88),
            "right_ankle":     CGPoint(x: 0.60, y: 0.88)
        ]
    }

    private static func armsUp(phase: Double) -> [String: CGPoint] {
        var p = restPose()
        let lift = CGFloat(sin(phase * .pi))
        p["left_elbow"]  = CGPoint(x: 0.30 - lift * 0.05, y: 0.22 - lift * 0.12)
        p["right_elbow"] = CGPoint(x: 0.70 + lift * 0.05, y: 0.22 - lift * 0.12)
        p["left_wrist"]  = CGPoint(x: 0.25 - lift * 0.08, y: 0.10 - lift * 0.08)
        p["right_wrist"] = CGPoint(x: 0.75 + lift * 0.08, y: 0.10 - lift * 0.08)
        return p
    }

    private static func sideStep(phase: Double, direction: Double) -> [String: CGPoint] {
        var p = restPose()
        let shift = CGFloat(direction * 0.06 * sin(phase * .pi))
        for (key, point) in p {
            p[key] = CGPoint(x: point.x + shift, y: point.y)
        }
        p["left_elbow"]  = CGPoint(x: 0.22 + shift, y: 0.35)
        p["right_elbow"] = CGPoint(x: 0.78 + shift, y: 0.35)
        p["left_wrist"]  = CGPoint(x: 0.16 + shift, y: 0.50)
        p["right_wrist"] = CGPoint(x: 0.84 + shift, y: 0.50)
        // Leg step
        let legShift = shift * 1.5
        p["left_knee"]  = CGPoint(x: 0.38 + legShift, y: 0.70)
        p["right_knee"] = CGPoint(x: 0.62 + legShift, y: 0.70)
        p["left_ankle"] = CGPoint(x: 0.38 + legShift, y: 0.88)
        p["right_ankle"] = CGPoint(x: 0.62 + legShift, y: 0.88)
        return p
    }

    private static func waveArms(phase: Double) -> [String: CGPoint] {
        var p = restPose()
        let wave = CGFloat(sin(phase * .pi * 2))
        p["left_elbow"]  = CGPoint(x: 0.28 + wave * 0.08, y: 0.30 + wave * 0.06)
        p["left_wrist"]  = CGPoint(x: 0.18 + wave * 0.14, y: 0.18 + wave * 0.10)
        p["right_elbow"] = CGPoint(x: 0.72 - wave * 0.08, y: 0.30 - wave * 0.06)
        p["right_wrist"] = CGPoint(x: 0.82 - wave * 0.14, y: 0.18 - wave * 0.10)
        return p
    }
}
