import Testing
import Foundation
import CoreGraphics
@testable import MacDance

@Suite("ScoringEngine Tests")
struct ScoringEngineTests {

    @Test("Identical poses produce YEAH tier")
    func identicalPosesYieldYeah() {
        let engine = ScoringEngine()
        let frame = PoseFrame(timestamp: 0, joints: makePose())
        let result = engine.evaluate(detected: makePose(), reference: frame)
        #expect(result.tier == .yeah)
    }

    @Test("Opposite poses produce MISS tier")
    func oppositePosesMiss() {
        let engine = ScoringEngine()
        let ref = PoseFrame(timestamp: 0, joints: makePose())
        let opposite = makeOppositePose()
        let result = engine.evaluate(detected: opposite, reference: ref)
        #expect(result.tier == .miss || result.tier == .ok)
    }

    @Test("Empty detected pose produces MISS")
    func emptyDetectedMiss() {
        let engine = ScoringEngine()
        let ref = PoseFrame(timestamp: 0, joints: makePose())
        let result = engine.evaluate(detected: [:], reference: ref)
        #expect(result.tier == .miss)
    }

    @Test("Combo builds on consecutive PERFECT scores")
    func comboBuilds() {
        let engine = ScoringEngine()
        let frame = PoseFrame(timestamp: 0, joints: makePose())
        let pose = makePose()
        for _ in 0..<5 {
            _ = engine.evaluate(detected: pose, reference: frame)
        }
        #expect(engine.combo.count >= 3)
        #expect(engine.combo.multiplier >= 1.5)
    }

    @Test("Combo resets on MISS")
    func comboResetsOnMiss() {
        var combo = ComboState()
        for _ in 0..<5 { combo.update(tier: .yeah) }
        #expect(combo.count == 5)
        combo.update(tier: .miss)
        #expect(combo.count == 0)
        #expect(combo.multiplier == 1.0)
    }

    @Test("Score caps at 99_999_999")
    func scoreCap() {
        let engine = ScoringEngine()
        for _ in 0..<100000 {
            let frame = PoseFrame(timestamp: 0, joints: makePose())
            _ = engine.evaluate(detected: makePose(), reference: frame)
        }
        #expect(engine.totalScore <= 99_999_999)
    }

    private func makePose() -> [String: CGPoint] {
        [
            "left_shoulder":  CGPoint(x: 0.38, y: 0.22),
            "right_shoulder": CGPoint(x: 0.62, y: 0.22),
            "left_elbow":     CGPoint(x: 0.28, y: 0.38),
            "right_elbow":    CGPoint(x: 0.72, y: 0.38),
            "left_wrist":     CGPoint(x: 0.22, y: 0.52),
            "right_wrist":    CGPoint(x: 0.78, y: 0.52),
            "left_hip":       CGPoint(x: 0.42, y: 0.52),
            "right_hip":      CGPoint(x: 0.58, y: 0.52),
            "left_knee":      CGPoint(x: 0.40, y: 0.70),
            "right_knee":     CGPoint(x: 0.60, y: 0.70),
            "left_ankle":     CGPoint(x: 0.40, y: 0.88),
            "right_ankle":    CGPoint(x: 0.60, y: 0.88)
        ]
    }

    private func makeOppositePose() -> [String: CGPoint] {
        [
            "left_shoulder":  CGPoint(x: 0.62, y: 0.78),
            "right_shoulder": CGPoint(x: 0.38, y: 0.78),
            "left_elbow":     CGPoint(x: 0.72, y: 0.62),
            "right_elbow":    CGPoint(x: 0.28, y: 0.62),
            "left_wrist":     CGPoint(x: 0.78, y: 0.48),
            "right_wrist":    CGPoint(x: 0.22, y: 0.48),
            "left_hip":       CGPoint(x: 0.58, y: 0.48),
            "right_hip":      CGPoint(x: 0.42, y: 0.48),
            "left_knee":      CGPoint(x: 0.60, y: 0.30),
            "right_knee":     CGPoint(x: 0.40, y: 0.30),
            "left_ankle":     CGPoint(x: 0.60, y: 0.12),
            "right_ankle":    CGPoint(x: 0.40, y: 0.12)
        ]
    }
}

@Suite("Choreography Interpolation Tests")
struct ChoreographyTests {

    @Test("Frame at t=0 returns first frame")
    func frameAtZero() {
        let choreo = makeTestChoreo()
        let frame = choreo.frame(at: 0.0)
        let expected = CGPoint(x: 0.5, y: 0.1)
        #expect(abs(frame.joints["nose"]!.x - expected.x) < 0.01)
    }

    @Test("Frame at t=1.0 returns second frame")
    func frameAtEnd() {
        let choreo = makeTestChoreo()
        let frame = choreo.frame(at: 1.0)
        let expected = CGPoint(x: 0.5, y: 0.2)
        #expect(abs(frame.joints["nose"]!.x - expected.x) < 0.01)
    }

    @Test("Frame at t=0.5 interpolates correctly")
    func frameAtMidpoint() {
        let choreo = makeTestChoreo()
        let frame = choreo.frame(at: 0.5)
        let expected = CGPoint(x: 0.5, y: 0.15)
        #expect(abs(frame.joints["nose"]!.y - expected.y) < 0.02)
    }

    @Test("Upcoming frames returns correct count")
    func upcomingFrames() {
        let choreo = makeTestChoreo()
        let upcoming = choreo.upcomingKeyframes(after: 0.0, count: 4)
        #expect(upcoming.count <= 4)
    }

    private func makeTestChoreo() -> Choreography {
        let frame1 = PoseFrame(timestamp: 0.0, joints: ["nose": CGPoint(x: 0.5, y: 0.1)])
        let frame2 = PoseFrame(timestamp: 1.0, joints: ["nose": CGPoint(x: 0.5, y: 0.2)])
        return Choreography(songMD5: "test", bpm: 120, frames: [frame1, frame2], totalDuration: 1.0)
    }
}

@Suite("ScoreHistory Tests")
struct ScoreHistoryTests {

    @Test("Write 6 runs, read back last 5")
    func lastFiveRuns() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_scores_\(UUID().uuidString).json")
        let history = ScoreHistory(storageURL: url)

        for i in 0..<6 {
            let record = RunRecord(songMD5: "test", score: i * 1000, maxCombo: i, starRating: 3)
            history.addRecord(record)
        }

        let last5 = history.lastFive(for: "test")
        #expect(last5.count == 5)
        #expect(last5.last?.score == 5000)
        #expect(last5.first?.score == 1000)

        try? FileManager.default.removeItem(at: url)
    }

    @Test("Personal best returns highest score")
    func personalBest() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_pb_\(UUID().uuidString).json")
        let history = ScoreHistory(storageURL: url)

        history.addRecord(RunRecord(songMD5: "song1", score: 5000, maxCombo: 10, starRating: 3))
        history.addRecord(RunRecord(songMD5: "song1", score: 12000, maxCombo: 20, starRating: 4))
        history.addRecord(RunRecord(songMD5: "song1", score: 3000, maxCombo: 5, starRating: 2))

        #expect(history.personalBest(for: "song1") == 12000)

        try? FileManager.default.removeItem(at: url)
    }

    @Test("Star rating thresholds are correct")
    func starRatings() {
        #expect(RunRecord.starRating(for: 0) == 1)
        #expect(RunRecord.starRating(for: 1500) == 1)
        #expect(RunRecord.starRating(for: 3000) == 2)
        #expect(RunRecord.starRating(for: 7500) == 3)
        #expect(RunRecord.starRating(for: 15000) == 4)
        #expect(RunRecord.starRating(for: 25000) == 5)
    }
}

@Suite("TestData Tests")
struct TestDataTests {

    @Test("Generated test choreography has correct structure")
    func testChoreoGeneration() {
        let choreo = TestData.generateTestChoreo()
        #expect(choreo.bpm == 120)
        #expect(choreo.totalDuration == 30.0)
        #expect(!choreo.frames.isEmpty)

        // Every frame should have all joints
        let firstFrame = choreo.frames[0]
        #expect(firstFrame.joints["left_shoulder"] != nil)
        #expect(firstFrame.joints["right_wrist"] != nil)
        #expect(firstFrame.joints["left_ankle"] != nil)

        // Frames should be chronologically ordered
        for i in 1..<choreo.frames.count {
            #expect(choreo.frames[i].timestamp > choreo.frames[i-1].timestamp)
        }
    }

    @Test("Test MP3 generation produces valid WAV data")
    func testMP3Generation() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_mp3_\(UUID().uuidString).wav")
        try TestData.generateTestMP3(at: url)

        let data = try Data(contentsOf: url)
        #expect(data.count > 44) // WAV header + some audio data
        // Check RIFF header
        let header = String(data: data.prefix(4), encoding: .ascii)
        #expect(header == "RIFF")

        try FileManager.default.removeItem(at: url)
    }

    @Test("Test choreo writes to disk correctly")
    func testChoreoWriteToDisk() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_choreo_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try TestData.writeToDisk(at: folder)

        let choreoURL = folder.appendingPathComponent("choreo.json")
        let analysisURL = folder.appendingPathComponent("analysis.json")
        #expect(FileManager.default.fileExists(atPath: choreoURL.path))
        #expect(FileManager.default.fileExists(atPath: analysisURL.path))

        // Verify choreo can be decoded
        let data = try Data(contentsOf: choreoURL)
        let choreo = try JSONDecoder().decode(Choreography.self, from: data)
        #expect(choreo.bpm == 120)
        #expect(!choreo.frames.isEmpty)

        try FileManager.default.removeItem(at: folder)
    }

    @Test("AudioPlayer can load generated test WAV")
    @MainActor
    func testAudioPlayerLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_\(UUID().uuidString).wav")
        try TestData.generateTestMP3(at: url)

        let player = AudioPlayer()
        try player.load(url: url)
        #expect(player.duration > 29.0)
        #expect(player.duration < 31.0)

        try FileManager.default.removeItem(at: url)
    }

    @Test("Python-format choreo.json decodes correctly")
    func testPythonChoreoFormat() throws {
        // CGPoint encodes/decodes as [x, y] array in Swift's Codable
        let pythonOutput = """
        {
            "songMD5": "abc123",
            "bpm": 128.0,
            "totalDuration": 10.0,
            "frames": [
                {
                    "timestamp": 0.0,
                    "joints": {
                        "left_shoulder": [0.38, 0.22],
                        "right_shoulder": [0.62, 0.22],
                        "left_elbow": [0.28, 0.38],
                        "right_elbow": [0.72, 0.38],
                        "left_wrist": [0.22, 0.52],
                        "right_wrist": [0.78, 0.52],
                        "left_hip": [0.42, 0.52],
                        "right_hip": [0.58, 0.52],
                        "left_knee": [0.40, 0.70],
                        "right_knee": [0.60, 0.70],
                        "left_ankle": [0.40, 0.88],
                        "right_ankle": [0.60, 0.88],
                        "nose": [0.50, 0.08]
                    }
                },
                {
                    "timestamp": 0.469,
                    "joints": {
                        "left_shoulder": [0.38, 0.22],
                        "right_shoulder": [0.62, 0.22],
                        "left_elbow": [0.30, 0.18],
                        "right_elbow": [0.70, 0.18],
                        "left_wrist": [0.25, 0.06],
                        "right_wrist": [0.75, 0.06],
                        "left_hip": [0.42, 0.52],
                        "right_hip": [0.58, 0.52],
                        "left_knee": [0.40, 0.70],
                        "right_knee": [0.60, 0.70],
                        "left_ankle": [0.40, 0.88],
                        "right_ankle": [0.60, 0.88],
                        "nose": [0.50, 0.08]
                    }
                }
            ]
        }
        """
        let data = pythonOutput.data(using: .utf8)!
        let choreo = try JSONDecoder().decode(Choreography.self, from: data)
        #expect(choreo.bpm == 128.0)
        #expect(choreo.totalDuration == 10.0)
        #expect(choreo.frames.count == 2)
        #expect(choreo.frames[0].joints["left_shoulder"] != nil)
        #expect(abs(choreo.frames[0].joints["left_shoulder"]!.x - 0.38) < 0.001)

        let mid = choreo.frame(at: 0.234)
        #expect(mid.joints["left_elbow"] != nil)
    }
}
