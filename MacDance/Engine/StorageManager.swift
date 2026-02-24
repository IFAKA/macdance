import Foundation
import CryptoKit

final class StorageManager {
    static let appSupportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacDance")
    }()

    static var songsDirectory: URL {
        appSupportURL.appendingPathComponent("songs")
    }

    private var libraryURL: URL {
        StorageManager.appSupportURL.appendingPathComponent("songs.json")
    }

    var scoreHistoryURL: URL {
        StorageManager.appSupportURL.appendingPathComponent("score_history.json")
    }

    init() {
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        let fm = FileManager.default
        let dirs = [
            StorageManager.appSupportURL,
            StorageManager.songsDirectory
        ]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    func loadLibrary() -> [Song] {
        guard FileManager.default.fileExists(atPath: libraryURL.path),
              let data = try? Data(contentsOf: libraryURL),
              let songs = try? JSONDecoder().decode([Song].self, from: data)
        else { return [] }
        return songs
    }

    func saveLibrary(_ songs: [Song]) {
        guard let data = try? JSONEncoder().encode(songs) else { return }
        try? data.write(to: libraryURL, options: .atomic)
    }

    func songFolder(md5: String) -> URL {
        StorageManager.songsDirectory.appendingPathComponent(md5)
    }

    func createSongFolder(md5: String) throws -> URL {
        let folder = songFolder(md5: md5)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func deleteSongFolder(md5: String) {
        let folder = songFolder(md5: md5)
        try? FileManager.default.removeItem(at: folder)
    }

    func copyMP3(from source: URL, md5: String) throws -> URL {
        let folder = try createSongFolder(md5: md5)
        let dest = folder.appendingPathComponent("song.mp3")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    func availableSpace() -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: StorageManager.appSupportURL.path
        ) else { return nil }
        return attrs[.systemFreeSize] as? Int64
    }

    static func md5(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
