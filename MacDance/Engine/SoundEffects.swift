import AVFoundation
import Foundation

@Observable
@MainActor
final class SoundEffects {
    private var players: [String: AVAudioPlayer] = [:]

    init() {
        preload()
    }

    private func preload() {
        let names = ["yeah", "perfect", "good", "ok", "miss", "tick", "tick_accent", "combo_milestone"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "wav") ??
                         Bundle.main.url(forResource: name, withExtension: "mp3"),
               let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players[name] = player
            }
        }

        // Generate synthetic sounds for any missing tiers
        if players.isEmpty {
            generateSyntheticSounds()
        }
    }

    func play(tier: ScoreTier) {
        play(named: tier.soundFileName)
    }

    func playTick(accented: Bool = false) {
        play(named: accented ? "tick_accent" : "tick")
    }

    func playComboMilestone() {
        play(named: "combo_milestone")
    }

    private func play(named name: String) {
        guard let player = players[name] else { return }
        if player.isPlaying {
            player.currentTime = 0
        }
        player.play()
    }

    // MARK: - Synthetic sound generation

    private func generateSyntheticSounds() {
        // Rising chime for YEAH
        if players["yeah"] == nil {
            players["yeah"] = makeTone(
                frequencies: [880, 1108, 1318],
                durations: [0.08, 0.08, 0.15],
                volume: 0.6
            )
        }
        // Clean bell tone for PERFECT
        if players["perfect"] == nil {
            players["perfect"] = makeTone(
                frequencies: [1046],
                durations: [0.2],
                volume: 0.5
            )
        }
        // Soft positive for GOOD
        if players["good"] == nil {
            players["good"] = makeTone(
                frequencies: [784],
                durations: [0.15],
                volume: 0.35
            )
        }
        // Neutral tick for OK
        if players["ok"] == nil {
            players["ok"] = makeTone(
                frequencies: [440],
                durations: [0.08],
                volume: 0.2
            )
        }
        // Low thud for MISS
        if players["miss"] == nil {
            players["miss"] = makeTone(
                frequencies: [120],
                durations: [0.12],
                volume: 0.3,
                waveform: .noise
            )
        }
        // Metronome tick
        if players["tick"] == nil {
            players["tick"] = makeTone(
                frequencies: [1200],
                durations: [0.03],
                volume: 0.4
            )
        }
        // Accented tick
        if players["tick_accent"] == nil {
            players["tick_accent"] = makeTone(
                frequencies: [1600],
                durations: [0.05],
                volume: 0.55
            )
        }
        // Combo milestone: ascending sweep
        if players["combo_milestone"] == nil {
            players["combo_milestone"] = makeTone(
                frequencies: [660, 880, 1320],
                durations: [0.06, 0.06, 0.1],
                volume: 0.4
            )
        }
    }

    private enum Waveform {
        case sine
        case noise
    }

    private func makeTone(
        frequencies: [Double],
        durations: [Double],
        volume: Float,
        waveform: Waveform = .sine
    ) -> AVAudioPlayer? {
        let sampleRate: Double = 44100
        var samples: [Float] = []

        for (freq, dur) in zip(frequencies, durations) {
            let count = Int(dur * sampleRate)
            for i in 0..<count {
                let t = Float(i) / Float(sampleRate)
                let envelope = min(1.0, Float(count - i) / Float(min(count, 500)))
                    * min(1.0, Float(i) / 50.0)

                let sample: Float
                switch waveform {
                case .sine:
                    sample = sin(Float(2.0 * .pi * freq) * t) * envelope * volume
                case .noise:
                    let noise = Float.random(in: -1...1)
                    let filtered = sin(Float(2.0 * .pi * freq) * t) * 0.5 + noise * 0.5
                    sample = filtered * envelope * volume
                }
                samples.append(sample)
            }
        }

        guard !samples.isEmpty else { return nil }
        return playerFromSamples(samples, sampleRate: sampleRate)
    }

    private func playerFromSamples(_ samples: [Float], sampleRate: Double) -> AVAudioPlayer? {
        // Build a minimal WAV in memory
        let numSamples = samples.count
        let dataSize = numSamples * 2  // 16-bit PCM
        let fileSize = 44 + dataSize

        var data = Data(capacity: fileSize)

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        appendUInt32(&data, UInt32(fileSize - 8))
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        appendUInt32(&data, 16)             // chunk size
        appendUInt16(&data, 1)              // PCM format
        appendUInt16(&data, 1)              // mono
        appendUInt32(&data, UInt32(sampleRate))
        appendUInt32(&data, UInt32(sampleRate * 2))  // byte rate
        appendUInt16(&data, 2)              // block align
        appendUInt16(&data, 16)             // bits per sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        appendUInt32(&data, UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intVal = Int16(clamped * Float(Int16.max))
            appendInt16(&data, intVal)
        }

        return try? AVAudioPlayer(data: data)
    }

    private func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private func appendInt16(_ data: inout Data, _ value: Int16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
}
