import SwiftUI
import UniformTypeIdentifiers

struct EmptyLibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var isDraggingOver = false
    @State private var showFilePicker = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 64))
                        .foregroundStyle(Color(white: 0.3))

                    VStack(spacing: 12) {
                        Text("Add your first song to start dancing.")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Drop an MP3 or M4A here, or click + to browse")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(white: 0.5))
                    }

                    dropZone

                    Button {
                        appState.createDemoSong()
                    } label: {
                        Text("or try the demo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }

                Spacer()
            }

            if let error = errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.mp3, UTType("public.m4a-audio") ?? .audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            handleDrop(providers)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isDraggingOver ? Color.white.opacity(0.8) : Color(white: 0.25),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .frame(width: 360, height: 200)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isDraggingOver ? Color.white.opacity(0.08) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isDraggingOver)

            VStack(spacing: 16) {
                Button {
                    showFilePicker = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(white: 0.15))
                            .frame(width: 52, height: 52)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                Text("or drag an audio file here")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                await processURL(url)
            }
        }
        return true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await processURL(url) }
        case .failure:
            break
        }
    }

    private func processURL(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        guard ext == "mp3" || ext == "m4a" else {
            showError("Only MP3 or M4A files are supported.")
            return
        }
        await appState.addSong(from: url)
    }

    private func showError(_ msg: String) {
        withAnimation {
            errorMessage = msg
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                errorMessage = nil
            }
        }
    }
}
