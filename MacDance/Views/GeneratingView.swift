import SwiftUI

struct GeneratingView: View {
    let songID: UUID
    @Environment(AppState.self) private var appState

    private var song: Song {
        appState.songs.first(where: { $0.id == songID }) ?? Song(
            id: songID, title: "Unknown", artist: "", duration: 0,
            md5Hash: "", choreoState: .failed
        )
    }

    private var stageLabel: String {
        switch song.generationProgress {
        case 0..<0.3: return "Analyzing music..."
        case 0.3..<0.7: return "Generating moves..."
        case 0.7..<1.0: return "Finalizing..."
        default: return "Done ✓"
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                if song.choreoState == .failed {
                    failedContent
                } else {
                    progressContent
                }

                Spacer()
            }
        }
        .onChange(of: song.choreoState) { _, newState in
            if newState == .ready {
                appState.startPlaying(song)
            }
        }
    }

    private var progressContent: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .stroke(Color(white: 0.15), lineWidth: 6)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: song.generationProgress)
                    .stroke(
                        Color(red: 0.4, green: 0.7, blue: 1.0),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: song.generationProgress)

                Text("\(Int(song.generationProgress * 100))%")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 12) {
                Text(song.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Text(stageLabel)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.6))
                    .animation(.easeInOut, value: stageLabel)
            }
        }
    }

    private var failedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(spacing: 12) {
                Text("Generation Failed")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)

                Text(song.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.6))

                if let error = song.generationError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.4))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
            }

            HStack(spacing: 16) {
                Button {
                    Task {
                        var retrying = song
                        retrying.choreoState = .generating
                        retrying.generationProgress = 0
                        retrying.generationError = nil
                        appState.updateSong(retrying)
                        await GenerationManager.shared.retryGeneration(for: song, appState: appState)
                    }
                } label: {
                    Text("Try Again")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.4, green: 0.7, blue: 1.0))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    appState.backToLibrary()
                } label: {
                    Text("Back to Library")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
