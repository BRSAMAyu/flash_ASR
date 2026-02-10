import Foundation

final class SessionManager {
    static let shared = SessionManager()

    private let maxSessions = 100
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

    func deleteSessions(ids: Set<UUID>) {
        sessions.removeAll { ids.contains($0.id) }
        save()
    }

    func session(for id: UUID) -> TranscriptionSession? {
        sessions.first { $0.id == id }
    }

    func searchSessions(query: String, kind: SessionKind? = nil, requiresLectureNotes: Bool = false) -> [TranscriptionSession] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { session in
            if let kind, session.kind != kind { return false }
            if requiresLectureNotes && !session.hasLectureNotes { return false }
            if q.isEmpty { return true }
            return session.title.lowercased().contains(q)
            || (session.courseName?.lowercased().contains(q) == true)
            || (session.chapter?.lowercased().contains(q) == true)
            || session.tags.contains(where: { $0.lowercased().contains(q) })
            || session.allOriginalText.lowercased().contains(q)
        }
    }

    func addTag(to sessionId: UUID, tag: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sessions[idx].tags.contains(trimmed) else { return }
        sessions[idx].tags.append(trimmed)
        sessions[idx].updatedAt = Date()
        save()
    }

    func removeTag(from sessionId: UUID, tag: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].tags.removeAll { $0 == tag }
        sessions[idx].updatedAt = Date()
        save()
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
