import Foundation

final class SessionManager {
    static let shared = SessionManager()

    private let maxSessions = 100
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "session.manager.queue")

    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = appSupport.appendingPathComponent("FlashASR", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    private var _sessions: [TranscriptionSession] = []
    var sessions: [TranscriptionSession] {
        queue.sync { _sessions }
    }

    private init() {
        load()
    }

    func createSession() -> TranscriptionSession {
        queue.sync {
            let session = TranscriptionSession()
            _sessions.insert(session, at: 0)
            trimToMaxLocked()
            saveLocked()
            return session
        }
    }

    func updateSession(_ session: TranscriptionSession) {
        queue.sync {
            guard let idx = _sessions.firstIndex(where: { $0.id == session.id }) else { return }
            var updated = session
            updated.updatedAt = Date()
            _sessions[idx] = updated
            saveLocked()
        }
    }

    func deleteSession(id: UUID) {
        queue.sync {
            _sessions.removeAll { $0.id == id }
            saveLocked()
        }
    }

    func deleteSessions(ids: Set<UUID>) {
        queue.sync {
            _sessions.removeAll { ids.contains($0.id) }
            saveLocked()
        }
    }

    func session(for id: UUID) -> TranscriptionSession? {
        queue.sync { _sessions.first { $0.id == id } }
    }

    func searchSessions(query: String, kind: SessionKind? = nil, requiresLectureNotes: Bool = false) -> [TranscriptionSession] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return queue.sync {
            _sessions.filter { session in
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
    }

    func addTag(to sessionId: UUID, tag: String) {
        queue.sync {
            guard let idx = _sessions.firstIndex(where: { $0.id == sessionId }) else { return }
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !_sessions[idx].tags.contains(trimmed) else { return }
            _sessions[idx].tags.append(trimmed)
            _sessions[idx].updatedAt = Date()
            saveLocked()
        }
    }

    func removeTag(from sessionId: UUID, tag: String) {
        queue.sync {
            guard let idx = _sessions.firstIndex(where: { $0.id == sessionId }) else { return }
            _sessions[idx].tags.removeAll { $0 == tag }
            _sessions[idx].updatedAt = Date()
            saveLocked()
        }
    }

    private func load() {
        queue.sync {
            guard fileManager.fileExists(atPath: storageURL.path),
                  let data = try? Data(contentsOf: storageURL),
                  let decoded = try? JSONDecoder().decode([TranscriptionSession].self, from: data)
            else {
                _sessions = []
                return
            }
            _sessions = decoded
        }
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(_sessions) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func trimToMaxLocked() {
        if _sessions.count > maxSessions {
            _sessions = Array(_sessions.prefix(maxSessions))
        }
    }
}
