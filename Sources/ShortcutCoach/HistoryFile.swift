import CoachCore
import Foundation

/// The switch history, as JSON at `~/Library/Application Support/<bundle id>/history.json`.
struct HistoryFile {
    private let url = URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "ShortcutCoach").appending(path: "history.json")
    private(set) var records: [SwitchRecord]

    /// A missing or unreadable file starts an empty history; the next append replaces it.
    init() {
        let stored = (try? JSONDecoder().decode([SwitchRecord].self, from: Data(contentsOf: url))) ?? []
        records = capped(stored, now: .now)
    }

    mutating func append(_ record: SwitchRecord) {
        records = capped(records + [record], now: record.at)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: url, options: .atomic)
        } catch {
            print("history not saved: \(error.localizedDescription)")
        }
    }
}
