import Foundation

final class SessionManager {
    static let shared = SessionManager()

    private let maxSessions = 10
    private let fileManager = FileManager.default

    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FlashASR", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    private(set) var sessions: [TranscriptionSession] = []

    private init() {
        load()
    }

    func createSession() -> TranscriptionSession {
        let session = TranscriptionSession()
        sessions.insert(session, at: 0)
        trimToMax()
        save()
        return session
    }

    func updateSession(_ session: TranscriptionSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var updated = session
        updated.updatedAt = Date()
        sessions[idx] = updated
        save()
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func session(for id: UUID) -> TranscriptionSession? {
        sessions.first { $0.id == id }
    }

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([TranscriptionSession].self, from: data)
        else {
            sessions = []
            return
        }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func trimToMax() {
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }
    }
}
