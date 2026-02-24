import Foundation

struct Song: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var duration: TimeInterval
    var md5Hash: String
    var addedAt: Date
    var choreoState: ChoreoState
    var generationProgress: Double
    var generationError: String?
    var difficulty: Int?

    enum ChoreoState: String, Codable {
        case generating
        case ready
        case failed
    }

    var folderURL: URL {
        StorageManager.songsDirectory.appendingPathComponent(md5Hash)
    }

    var mp3URL: URL {
        folderURL.appendingPathComponent("song.mp3")
    }

    var choreoURL: URL {
        folderURL.appendingPathComponent("choreo.json")
    }

    var analysisURL: URL {
        folderURL.appendingPathComponent("analysis.json")
    }

    var coverURL: URL {
        folderURL.appendingPathComponent("cover.jpg")
    }

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        duration: TimeInterval,
        md5Hash: String,
        addedAt: Date = Date(),
        choreoState: ChoreoState = .generating,
        generationProgress: Double = 0,
        generationError: String? = nil,
        difficulty: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.md5Hash = md5Hash
        self.addedAt = addedAt
        self.choreoState = choreoState
        self.generationProgress = generationProgress
        self.generationError = generationError
        self.difficulty = difficulty
    }
}
