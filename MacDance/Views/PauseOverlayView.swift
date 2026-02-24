import SwiftUI

struct PauseOverlayView: View {
    var onResume: () -> Void
    var onRestart: () -> Void
    var onPractice: () -> Void
    var onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 28) {
                Text("Paused")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                VStack(spacing: 14) {
                    pauseButton("Resume", icon: "play.fill", primary: true, action: onResume)
                    pauseButton("Restart", icon: "arrow.counterclockwise", action: onRestart)
                    pauseButton("Practice This Section", icon: "repeat", action: onPractice)
                    pauseButton("Exit to Library", icon: "xmark", destructive: true, action: onExit)
                }
            }
            .frame(width: 320)
        }
    }

    private func pauseButton(
        _ label: String,
        icon: String,
        primary: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        primary ? Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.9) :
                        destructive ? Color.red.opacity(0.25) :
                        Color(white: 0.18)
                    )
            )
            .foregroundStyle(destructive ? Color.red.opacity(0.9) : .white)
        }
        .buttonStyle(.plain)
    }
}
