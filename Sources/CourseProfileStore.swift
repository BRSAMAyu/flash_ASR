import Foundation

final class CourseProfileStore {
    static let shared = CourseProfileStore()

    private let maxProfiles = 30
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "course.profile.store.queue")
    private var profiles: [CourseProfile] = []

    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = appSupport.appendingPathComponent("FlashASR", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("course_profiles.json")
    }

    private init() {
        load()
    }

    func allProfiles() -> [CourseProfile] {
        queue.sync { profiles.sorted { $0.updatedAt > $1.updatedAt } }
    }

    func profile(courseName: String) -> CourseProfile? {
        let target = courseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return queue.sync { profiles.first { $0.courseName.lowercased() == target } }
    }

    func upsert(_ profile: CourseProfile) {
        queue.sync {
            let normalized = profile.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            let clean = CourseProfile(
                courseName: normalized,
                majorKeywords: profile.majorKeywords.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                examFocus: profile.examFocus.trimmingCharacters(in: .whitespacesAndNewlines),
                forbiddenSimplifications: profile.forbiddenSimplifications.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                updatedAt: Date()
            )
            if let idx = profiles.firstIndex(where: { $0.courseName.caseInsensitiveCompare(clean.courseName) == .orderedSame }) {
                profiles[idx] = clean
            } else {
                profiles.append(clean)
            }
            profiles.sort { $0.updatedAt > $1.updatedAt }
            if profiles.count > maxProfiles {
                profiles = Array(profiles.prefix(maxProfiles))
            }
            saveLocked()
        }
    }

    func deleteProfile(courseName: String) {
        queue.sync {
            let target = courseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            profiles.removeAll { $0.courseName.lowercased() == target }
            saveLocked()
        }
    }

    func allCoursenames() -> [String] {
        queue.sync { profiles.sorted { $0.updatedAt > $1.updatedAt }.map { $0.courseName } }
    }

    private func load() {
        queue.sync {
            guard fileManager.fileExists(atPath: storageURL.path),
                  let data = try? Data(contentsOf: storageURL),
                  let decoded = try? JSONDecoder().decode([CourseProfile].self, from: data) else {
                profiles = []
                return
            }
            profiles = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
