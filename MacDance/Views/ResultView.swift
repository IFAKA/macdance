import SwiftUI

struct ResultView: View {
    let song: Song
    let score: Int
    let maxCombo: Int
    @Environment(AppState.self) private var appState

    @State private var displayedScore: Int = 0
    @State private var showStars: Bool = false
    @State private var isPersonalBest: Bool = false

    private var starRating: Int { RunRecord.starRating(for: score) }

    private var history: [RunRecord] {
        appState.scoreHistory.lastFive(for: song.md5Hash)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 40) {
                    songInfo

                    scoreSection

                    if showStars {
                        starsSection
                            .transition(.scale.combined(with: .opacity))
                    }

                    if history.count > 1 {
                        historySparkline
                            .transition(.opacity)
                    }
                }

                Spacer()

                actionButtons
                    .padding(.bottom, 60)
            }
        }
        .onAppear {
            animateScore()
            checkPersonalBest()
        }
    }

    private var songInfo: some View {
        VStack(spacing: 8) {
            Text(song.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
            if !song.artist.isEmpty {
                Text(song.artist)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(white: 0.5))
            }
        }
    }

    private var scoreSection: some View {
        VStack(spacing: 12) {
            if isPersonalBest {
                Label("Personal Best!", systemImage: "trophy.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.1))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(red: 1, green: 0.85, blue: 0.1).opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(displayedScore >= 99_999_999 ? "MAX" : "\(displayedScore)")
                .font(.system(size: 72, weight: .black, design: .monospaced))
                .foregroundStyle(isPersonalBest ? Color(red: 1, green: 0.85, blue: 0.1) : .white)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: displayedScore)

            Text("Max Combo: \(maxCombo)")
                .font(.system(size: 16))
                .foregroundStyle(Color(white: 0.5))
        }
    }

    private var starsSection: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= starRating ? "star.fill" : "star")
                    .font(.system(size: 36))
                    .foregroundStyle(star <= starRating ? Color(red: 1, green: 0.85, blue: 0.1) : Color(white: 0.25))
                    .scaleEffect(star <= starRating ? 1.0 : 0.8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(star) * 0.1), value: showStars)
            }
        }
    }

    private var historySparkline: some View {
        VStack(spacing: 10) {
            Text("Recent Runs")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.35))

            HStack(spacing: 8) {
                ForEach(history) { run in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(dotColor(stars: run.starRating))
                            .frame(width: 10, height: 10)
                        Text("\(run.score)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button("Play Again") {
                appState.startPlaying(song)
            }
            .buttonStyle(GameButtonStyle(primary: true))

            Button("Back to Library") {
                appState.backToLibrary()
            }
            .buttonStyle(GameButtonStyle(primary: false))
        }
    }

    private func dotColor(stars: Int) -> Color {
        switch stars {
        case 4...: return .green
        case 3: return Color(red: 0.7, green: 0.9, blue: 0.2)
        case 2: return .orange
        default: return .red
        }
    }

    private func animateScore() {
        let target = score
        guard target > 0 else {
            displayedScore = 0
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showStars = true
            }
            return
        }
        let steps = 40
        let stepValue = target / steps
        Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(30))
                if i == steps {
                    displayedScore = target
                } else {
                    displayedScore = min(stepValue * i, target)
                }
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showStars = true
            }
        }
    }

    private func checkPersonalBest() {
        let pb = appState.scoreHistory.personalBest(for: song.md5Hash) ?? 0
        isPersonalBest = score >= pb && score > 0
    }
}

struct GameButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(primary ? .black : .white)
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(primary ? .white : Color(white: 0.15))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
