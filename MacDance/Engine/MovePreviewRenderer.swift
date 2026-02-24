import SwiftUI
import CoreGraphics

struct MovePreviewItem: View {
    let frame: PoseFrame
    let isCurrent: Bool
    let beatsAway: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isCurrent ? Color.white.opacity(0.6) : Color.white.opacity(0.2), lineWidth: isCurrent ? 2 : 1)
                )

            StickFigureView(frame: frame, color: isCurrent ? .white : Color(white: 0.7))
                .padding(8)

            if !isCurrent {
                VStack {
                    Spacer()
                    Text("\(beatsAway)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 4)
                }
            }
        }
        .frame(width: isCurrent ? 100 : 72, height: isCurrent ? 110 : 80)
        .scaleEffect(isCurrent ? 1.0 : 0.9)
        .animation(.spring(response: 0.3), value: isCurrent)
    }
}

struct StickFigureView: View {
    let frame: PoseFrame
    let color: Color

    var body: some View {
        Canvas { context, size in
            drawSkeleton(context: context, size: size)
        }
    }

    private func drawSkeleton(context: GraphicsContext, size: CGSize) {
        let connections: [(JointName, JointName)] = [
            (.leftShoulder, .rightShoulder),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
            (.leftHip, .rightHip),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
            (.nose, .leftShoulder), (.nose, .rightShoulder)
        ]

        func pt(_ joint: JointName) -> CGPoint? {
            guard let p = frame.joint(joint) else { return nil }
            return CGPoint(x: p.x * size.width, y: p.y * size.height)
        }

        for (a, b) in connections {
            guard let pa = pt(a), let pb = pt(b) else { continue }
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            context.stroke(path, with: .color(color), lineWidth: 2)
        }

        for joint in JointName.allCases {
            guard let p = pt(joint) else { continue }
            let rect = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}

struct MovePreviewStrip: View {
    let currentFrame: PoseFrame?
    let upcomingFrames: [PoseFrame]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<min(2, upcomingFrames.count), id: \.self) { i in
                let reversed = Array(upcomingFrames.prefix(2).reversed())
                if i < reversed.count {
                    MovePreviewItem(
                        frame: reversed[i],
                        isCurrent: false,
                        beatsAway: 2 - i
                    )
                    .opacity(0.6 + Double(i) * 0.2)
                }
            }

            if let current = currentFrame {
                MovePreviewItem(frame: current, isCurrent: true, beatsAway: 0)
            }

            ForEach(0..<min(2, upcomingFrames.count), id: \.self) { i in
                if i < upcomingFrames.count {
                    MovePreviewItem(
                        frame: upcomingFrames[i],
                        isCurrent: false,
                        beatsAway: i + 1
                    )
                    .opacity(1.0 - Double(i) * 0.2)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.5))
    }
}
