import Foundation
import SwiftUI

enum ScoreTier: String, CaseIterable {
    case yeah = "YEAH!"
    case perfect = "PERFECT"
    case good = "GOOD"
    case ok = "OK"
    case miss = "MISS"

    static func tier(for similarity: Float) -> ScoreTier {
        switch similarity {
        case 0.85...: return .yeah
        case 0.70..<0.85: return .perfect
        case 0.50..<0.70: return .good
        case 0.30..<0.50: return .ok
        default: return .miss
        }
    }

    var points: Int {
        switch self {
        case .yeah: return 1000
        case .perfect: return 750
        case .good: return 500
        case .ok: return 250
        case .miss: return 0
        }
    }

    var color: Color {
        switch self {
        case .yeah: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .perfect: return .white
        case .good: return Color(red: 0.2, green: 0.9, blue: 0.2)
        case .ok: return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .miss: return Color(red: 1.0, green: 0.2, blue: 0.2)
        }
    }

    var soundFileName: String {
        switch self {
        case .yeah: return "yeah"
        case .perfect: return "perfect"
        case .good: return "good"
        case .ok: return "ok"
        case .miss: return "miss"
        }
    }

    var countsAsCombo: Bool {
        self == .yeah || self == .perfect
    }

    var breaksCombO: Bool {
        self == .miss || self == .ok
    }
}
