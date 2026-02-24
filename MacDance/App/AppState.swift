import Foundation
import SwiftUI

enum AppScreen {
    case emptyLibrary
    case library
    case generating(Song)
    case calibration(Song)
    case game(Song)
    case result(Song, score: Int, maxCombo: Int)
}

@Observable
@MainActor
final class AppState {
    var songs: [Song] = []
    var currentScreen: AppScreen = .emptyLibrary
    var isCalibrated: Bool = false
    var upperBodyOnly: Bool = false
    var calibratedSessionID: UUID = UUID()
    var generationQueue: [UUID] = []

    let scoreHistory: ScoreHistory
    private let storage: StorageManager

    init() {
        let sm = StorageManager()
        self.storage = sm
        self.scoreHistory = ScoreHistory(storageURL: sm.scoreHistoryURL)
        self.songs = sm.loadLibrary()
        updateScreen()
        reQueueOrphanedSongs()
    }

    func updateScreen() {
        if songs.isEmpty {
            currentScreen = .emptyLibrary
        } else if case .emptyLibrary = currentScreen {
            currentScreen = .library
        }
    }

    func addSong(from url: URL) async {
        await GenerationManager.shared.enqueue(url: url, appState: self)
    }

    func startPlaying(_ song: Song) {
        guard song.choreoState == .ready else { return }
        if isCalibrated {
            currentScreen = .game(song)
        } else {
            currentScreen = .calibration(song)
        }
    }

    func calibrationComplete(for song: Song, upperBodyOnly: Bool = false) {
        isCalibrated = true
        self.upperBodyOnly = upperBodyOnly
        currentScreen = .game(song)
    }

    func gameEnded(song: Song, score: Int, maxCombo: Int) {
        let stars = RunRecord.starRating(for: score)
        let record = RunRecord(songMD5: song.md5Hash, score: score, maxCombo: maxCombo, starRating: stars)
        scoreHistory.addRecord(record)
        currentScreen = .result(song, score: score, maxCombo: maxCombo)
    }

    func backToLibrary() {
        currentScreen = .library
    }

    func updateSong(_ song: Song) {
        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
            songs[idx] = song
            storage.saveLibrary(songs)
        }
    }

    func removeSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        storage.saveLibrary(songs)
        storage.deleteSongFolder(md5: song.md5Hash)
        updateScreen()
    }

    func addSongToLibrary(_ song: Song) {
        let wasEmpty = songs.isEmpty
        songs.append(song)
        storage.saveLibrary(songs)
        if wasEmpty {
            currentScreen = .generating(song)
        }
    }

    func createDemoSong() {
        let md5 = "demo_metronome_120bpm"
        guard !songs.contains(where: { $0.md5Hash == md5 }) else { return }

        do {
            let folder = try storage.createSongFolder(md5: md5)
            let mp3URL = folder.appendingPathComponent("song.mp3")
            try TestData.generateTestMP3(at: mp3URL)
            try TestData.writeToDisk(at: folder)

            let song = Song(
                title: "Demo — 120 BPM Metronome",
                artist: "MacDance",
                duration: TestData.duration,
                md5Hash: md5,
                choreoState: .ready,
                generationProgress: 1.0
            )
            addSongToLibrary(song)
        } catch {}
    }

    private func reQueueOrphanedSongs() {
        let orphans = songs.filter { $0.choreoState == .generating }
        for song in orphans {
            generationQueue.append(song.id)
        }
        if !orphans.isEmpty {
            Task {
                for song in orphans {
                    await GenerationManager.shared.retryGeneration(for: song, appState: self)
                }
            }
        }
    }
}
