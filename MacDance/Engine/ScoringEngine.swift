import Foundation
import CoreGraphics

struct ScoringResult {
    let tier: ScoreTier
    let similarity: Float
    let missedJoints: [JointName]
    let pointsAwarded: Int
    let comboMultiplier: Float
}

struct ComboState {
    var count: Int = 0
    var multiplier: Float = 1.0

    mutating func update(tier: ScoreTier) {
        if tier.countsAsCombo {
            count += 1
        } else if tier.breaksCombO {
            count = 0
        }
        multiplier = comboMultiplier(for: count)
    }

    private func comboMultiplier(for count: Int) -> Float {
        switch count {
        case 0..<3: return 1.0
        case 3..<5: return 1.5
        case 5..<10: return 2.0
        default: return 3.0
        }
    }
}

final class ScoringEngine {
    private(set) var totalScore: Int = 0
    private(set) var combo: ComboState = ComboState()
    private(set) var maxCombo: Int = 0
    var upperBodyOnly: Bool = false

    func evaluate(detected: [String: CGPoint], reference: PoseFrame) -> ScoringResult {
        var totalWeight: Float = 0
        var weightedSimilarity: Float = 0
        var missedJoints: [JointName] = []

        let jointPairs = upperBodyOnly ? Self.upperBodyPairs : Self.scoringPairs

        for (parent, child) in jointPairs {
            guard let detParent = detected[parent.rawValue],
                  let detChild = detected[child.rawValue],
                  let refParent = reference.joint(parent),
                  let refChild = reference.joint(child) else {
                continue
            }

            let detAngle = jointAngle(from: detParent, to: detChild)
            let refAngle = jointAngle(from: refParent, to: refChild)
            let dist = angularDistance(detAngle, refAngle)
            let similarity = 1.0 - dist

            let weight = child.weight
            weightedSimilarity += similarity * weight
            totalWeight += weight

            if similarity < 0.30 {
                missedJoints.append(child)
            }
        }

        let finalSimilarity: Float = totalWeight > 0 ? weightedSimilarity / totalWeight : 0
        let tier = ScoreTier.tier(for: finalSimilarity)
        combo.update(tier: tier)

        if combo.count > maxCombo {
            maxCombo = combo.count
        }

        let raw = tier.points
        let awarded = Int(Float(raw) * combo.multiplier)
        totalScore = min(totalScore + awarded, 99_999_999)

        return ScoringResult(
            tier: tier,
            similarity: finalSimilarity,
            missedJoints: missedJoints,
            pointsAwarded: awarded,
            comboMultiplier: combo.multiplier
        )
    }

    func reset() {
        totalScore = 0
        combo = ComboState()
        maxCombo = 0
    }

    private func jointAngle(from parent: CGPoint, to child: CGPoint) -> Float {
        atan2(Float(child.y - parent.y), Float(child.x - parent.x))
    }

    private func angularDistance(_ a: Float, _ b: Float) -> Float {
        var d = abs(a - b)
        if d > .pi { d = 2 * .pi - d }
        return d / .pi
    }

    static let scoringPairs: [(JointName, JointName)] = [
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftShoulder, .rightShoulder)
    ]

    static let upperBodyPairs: [(JointName, JointName)] = [
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftShoulder, .rightShoulder)
    ]
}
