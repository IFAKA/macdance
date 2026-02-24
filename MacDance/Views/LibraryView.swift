import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var isDraggingOver = false
    @State private var toastMessage: String?
    @State private var showFilePicker = false

    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 20)
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                songGrid
            }

            if isDraggingOver {
                dropOverlay
            }

            if let toast = toastMessage {
                toastView(toast)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.mp3, UTType("public.m4a-audio") ?? .audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    for url in urls {
                        await appState.addSong(from: url)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("MacDance")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                showFilePicker = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(white: 0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }

    private var songGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(appState.songs) { song in
                    SongCard(song: song)
                        .onTapGesture {
                            if song.choreoState == .failed {
                                Task {
                                    var retrying = song
                                    retrying.choreoState = .generating
                                    retrying.generationProgress = 0
                                    retrying.generationError = nil
                                    appState.updateSong(retrying)
                                    await GenerationManager.shared.retryGeneration(for: retrying, appState: appState)
                                }
                            } else {
                                appState.startPlaying(song)
                            }
                        }
                        .contextMenu {
                            contextMenu(for: song)
                        }
                }
            }
            .padding(32)
        }
    }

    @ViewBuilder
    private func contextMenu(for song: Song) -> some View {
        if song.choreoState == .generating {
            Button(role: .destructive) {
                appState.removeSong(song)
            } label: {
                Label("Cancel Generation", systemImage: "xmark.circle")
            }
        } else {
            Button {
                Task { await appState.addSong(from: song.mp3URL) }
            } label: {
                Label("Regenerate Choreography", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive) {
                appState.removeSong(song)
            } label: {
                Label("Delete Song", systemImage: "trash")
            }
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Color.white.opacity(0.08)
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.white.opacity(0.4), lineWidth: 3)
            VStack(spacing: 16) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                Text("Drop to add song")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func toastView(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(white: 0.15).opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    let ext = url.pathExtension.lowercased()
                    guard ext == "mp3" || ext == "m4a" else {
                        self.showToast("Only MP3 or M4A files are supported.")
                        return
                    }
                    if appState.songs.contains(where: { $0.mp3URL == url }) {
                        self.showToast("This song is already in your library.")
                        return
                    }
                    await appState.addSong(from: url)
                    self.showToast("Generating choreography — keep playing while you wait")
                }
            }
        }
        return true
    }

    private func showToast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                toastMessage = nil
            }
        }
    }
}

struct SongCard: View {
    let song: Song
    @Environment(AppState.self) private var appState

    private var history: [RunRecord] {
        appState.scoreHistory.lastFive(for: song.md5Hash)
    }

    private var personalBest: Int? {
        appState.scoreHistory.personalBest(for: song.md5Hash)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverArt
                .frame(height: 140)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if !song.artist.isEmpty {
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(1)
                }

                HStack {
                    if let diff = song.difficulty {
                        difficultyBadge(diff)
                    }
                    if !history.isEmpty {
                        scoreDotsRow
                    }
                }

                stateIndicator
            }
            .padding(12)
        }
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(white: 0.2), lineWidth: 1)
        )
        .opacity(song.choreoState == .generating ? 0.8 : 1.0)
    }

    @ViewBuilder
    private var coverArt: some View {
        if FileManager.default.fileExists(atPath: song.coverURL.path),
           let img = NSImage(contentsOf: song.coverURL) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(white: 0.15)
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(white: 0.3))
            }
        }
    }

    private var scoreDotsRow: some View {
        HStack(spacing: 4) {
            ForEach(history) { run in
                let stars = run.starRating
                Circle()
                    .fill(dotColor(stars: stars))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func difficultyBadge(_ level: Int) -> some View {
        let (label, color): (String, Color) = switch level {
        case 1: ("Easy", .green)
        case 2: ("Medium", .yellow)
        case 3: ("Hard", .orange)
        default: ("Expert", .red)
        }
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func dotColor(stars: Int) -> Color {
        switch stars {
        case 4...: return .green
        case 3: return Color(red: 0.7, green: 0.9, blue: 0.2)
        case 2: return .orange
        default: return .red
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch song.choreoState {
        case .generating:
            HStack(spacing: 8) {
                ProgressView(value: song.generationProgress)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.4, green: 0.7, blue: 1.0))
                Text("\(Int(song.generationProgress * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.5))
            }
        case .ready:
            if let pb = personalBest {
                Text("Best: \(pb)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.45))
            }
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("Generation failed")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .help(song.generationError ?? "Choreography generation failed")
        }
    }
}
