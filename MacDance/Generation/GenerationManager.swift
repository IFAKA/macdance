import Foundation
import AVFoundation

struct GenerationProgress: Codable {
    let stage: String
    let progress: Double
    var error: String?
}

@Observable
@MainActor
final class GenerationManager {
    static let shared = GenerationManager()

    private var activeGenerations: Set<String> = []
    private var generationQueue: [(url: URL, md5: String)] = []
    private var isProcessingQueue: Bool = false
    private var activeProcess: Process?

    private let pythonBinURL: URL? = {
        Bundle.main.url(forResource: "python_bin", withExtension: nil)
    }()

    private let generationTimeout: TimeInterval = 300 // 5 minutes

    func enqueue(url: URL, appState: AppState) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let md5: String
        do {
            md5 = try StorageManager.md5(of: url)
        } catch {
            return
        }

        if appState.songs.contains(where: { $0.md5Hash == md5 }) {
            return
        }

        let storage = StorageManager()

        let freeSpace = storage.availableSpace() ?? 0
        let minRequired: Int64 = 500 * 1024 * 1024
        guard freeSpace >= minRequired else {
            return
        }

        let asset = AVURLAsset(url: url)
        let isPlayable: Bool
        do {
            isPlayable = try await asset.load(.isPlayable)
        } catch {
            isPlayable = false
        }
        guard isPlayable else { return }

        let title = url.deletingPathExtension().lastPathComponent
        let duration: TimeInterval
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
        } catch {
            duration = 0
        }

        let mp3URL: URL
        do {
            mp3URL = try storage.copyMP3(from: url, md5: md5)
        } catch {
            return
        }

        let song = Song(
            title: title,
            artist: "",
            duration: duration,
            md5Hash: md5,
            choreoState: .generating,
            generationProgress: 0
        )
        appState.addSongToLibrary(song)

        generationQueue.append((url: mp3URL, md5: md5))
        if !isProcessingQueue {
            await processQueue(appState: appState)
        }
    }

    func retryGeneration(for song: Song, appState: AppState) async {
        generationQueue.append((url: song.mp3URL, md5: song.md5Hash))
        if !isProcessingQueue {
            await processQueue(appState: appState)
        }
    }

    func cancelGeneration(for md5: String) {
        generationQueue.removeAll { $0.md5 == md5 }
        if activeGenerations.contains(md5) {
            activeProcess?.terminate()
        }
    }

    private func processQueue(appState: AppState) async {
        isProcessingQueue = true
        while !generationQueue.isEmpty {
            let item = generationQueue.removeFirst()
            await generate(mp3URL: item.url, md5: item.md5, appState: appState)
        }
        isProcessingQueue = false
    }

    private func generate(mp3URL: URL, md5: String, appState: AppState) async {
        guard !activeGenerations.contains(md5) else { return }
        activeGenerations.insert(md5)
        defer { activeGenerations.remove(md5) }

        let outputDir = StorageManager.songsDirectory.appendingPathComponent(md5)

        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        if let pythonBin = pythonBinURL {
            process.executableURL = pythonBin
            process.arguments = [
                "generate",
                "--mp3", mp3URL.path,
                "--output", outputDir.path
            ]
        } else if let scriptURL = devScriptURL() {
            let scriptsDir = scriptURL.deletingLastPathComponent()
            let venvPython = scriptsDir.appendingPathComponent(".venv/bin/python3")
            if FileManager.default.fileExists(atPath: venvPython.path) {
                process.executableURL = venvPython
                process.arguments = [
                    scriptURL.path,
                    "generate",
                    "--mp3", mp3URL.path,
                    "--output", outputDir.path
                ]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [
                    "python3",
                    scriptURL.path,
                    "generate",
                    "--mp3", mp3URL.path,
                    "--output", outputDir.path
                ]
            }
        } else {
            await markFailed(md5: md5, error: "Generation engine not found. Reinstall the app or check Scripts/generate_choreo.py exists.", appState: appState)
            return
        }

        activeProcess = process

        do {
            try process.run()
        } catch {
            activeProcess = nil
            await markFailed(md5: md5, error: "Failed to launch generation: \(error.localizedDescription)", appState: appState)
            return
        }

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(generationTimeout))
            if process.isRunning {
                process.terminate()
            }
        }

        let handle = pipe.fileHandleForReading
        var buffer = Data()

        while process.isRunning {
            let chunk = handle.availableData
            if !chunk.isEmpty {
                buffer.append(chunk)
                await parseProgressLines(buffer: &buffer, md5: md5, appState: appState)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        let remaining = handle.readDataToEndOfFile()
        if !remaining.isEmpty {
            buffer.append(remaining)
            await parseProgressLines(buffer: &buffer, md5: md5, appState: appState)
        }

        timeoutTask.cancel()
        activeProcess = nil

        guard process.terminationStatus == 0 else {
            let reason = process.terminationReason == .uncaughtSignal ? "timed out" : "failed (exit code \(process.terminationStatus))"
            await markFailed(md5: md5, error: "Generation \(reason)", appState: appState)
            return
        }

        let choreoURL = outputDir.appendingPathComponent("choreo.json")
        guard FileManager.default.fileExists(atPath: choreoURL.path) else {
            await markFailed(md5: md5, error: "Generation completed but no choreography was produced", appState: appState)
            return
        }

        let choreo: Choreography
        do {
            let data = try Data(contentsOf: choreoURL)
            choreo = try JSONDecoder().decode(Choreography.self, from: data)
            guard !choreo.frames.isEmpty else {
                await markFailed(md5: md5, error: "Generated choreography has no frames", appState: appState)
                return
            }
        } catch {
            await markFailed(md5: md5, error: "Generated choreography is invalid: \(error.localizedDescription)", appState: appState)
            return
        }

        let difficulty = choreo.calculateDifficulty()
        await markReady(md5: md5, difficulty: difficulty, appState: appState)
    }

    private func devScriptURL() -> URL? {
        let candidates = [
            // From source file location (compile time)
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/generate_choreo.py"),
            // From Xcode build products (DerivedData)
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/generate_choreo.py"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func parseProgressLines(buffer: inout Data, md5: String, appState: AppState) async {
        guard let text = String(data: buffer, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")
        for line in lines.dropLast() {
            if let data = line.data(using: .utf8),
               let progress = try? JSONDecoder().decode(GenerationProgress.self, from: data) {
                if var song = appState.songs.first(where: { $0.md5Hash == md5 }) {
                    song.generationProgress = progress.progress
                    appState.updateSong(song)
                }
            }
        }
        if let lastNewline = text.lastIndex(of: "\n") {
            let remaining = String(text[text.index(after: lastNewline)...])
            buffer = remaining.data(using: .utf8) ?? Data()
        }
    }

    private func markReady(md5: String, difficulty: Int, appState: AppState) async {
        if var song = appState.songs.first(where: { $0.md5Hash == md5 }) {
            song.choreoState = .ready
            song.generationProgress = 1.0
            song.generationError = nil
            song.difficulty = difficulty
            appState.updateSong(song)
        }
    }

    private func markFailed(md5: String, error: String, appState: AppState) async {
        if var song = appState.songs.first(where: { $0.md5Hash == md5 }) {
            song.choreoState = .failed
            song.generationError = error
            appState.updateSong(song)
        }
    }
}
