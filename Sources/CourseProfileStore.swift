import Foundation

final class CourseProfileStore {
    static let shared = CourseProfileStore()

    private let maxProfiles = 30
    private let fileManager = FileManager.default
    private var profiles: [CourseProfile] = []

    private var storageURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FlashASR", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("course_profiles.json")
    }

    private init() {
        load()
    }

    func allProfiles() -> [CourseProfile] {
        profiles.sorted { $0.updatedAt > $1.updatedAt }
    }

    func profile(courseName: String) -> CourseProfile? {
        let target = courseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.first { $0.courseName.lowercased() == target }
    }

    func upsert(_ profile: CourseProfile) {
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
        save()
    }

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([CourseProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
