import Foundation

struct RunRecord: Codable, Identifiable {
    let id: UUID
    let songMD5: String
    let score: Int
    let maxCombo: Int
    let starRating: Int
    let playedAt: Date

    init(songMD5: String, score: Int, maxCombo: Int, starRating: Int, playedAt: Date = Date()) {
        self.id = UUID()
        self.songMD5 = songMD5
        self.score = score
        self.maxCombo = maxCombo
        self.starRating = starRating
        self.playedAt = playedAt
    }

    static func starRating(for score: Int) -> Int {
        switch score {
        case 0..<2000: return 1
        case 2000..<5000: return 2
        case 5000..<10000: return 3
        case 10000..<20000: return 4
        default: return 5
        }
    }
}

@Observable
final class ScoreHistory {
    private(set) var records: [String: [RunRecord]] = [:]
    private let storageURL: URL

    init(storageURL: URL) {
        self.storageURL = storageURL
        load()
    }

    func records(for songMD5: String) -> [RunRecord] {
        records[songMD5] ?? []
    }

    func lastFive(for songMD5: String) -> [RunRecord] {
        Array((records[songMD5] ?? []).suffix(5))
    }

    func personalBest(for songMD5: String) -> Int? {
        records[songMD5]?.map(\.score).max()
    }

    func addRecord(_ record: RunRecord) {
        var list = records[record.songMD5] ?? []
        list.append(record)
        if list.count > 20 {
            list = Array(list.suffix(20))
        }
        records[record.songMD5] = list
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: [RunRecord]].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
