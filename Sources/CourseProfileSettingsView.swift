import SwiftUI

struct CourseProfileSettingsView: View {
    @State private var profiles: [CourseProfile] = []
    @State private var searchQuery = ""
    @State private var editingProfile: CourseProfile? = nil
    @State private var isCreating = false

    // Inline edit fields
    @State private var editName = ""
    @State private var editKeywords = ""
    @State private var editFocus = ""
    @State private var editForbidden = ""

    private var filtered: [CourseProfile] {
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return profiles }
        return profiles.filter { $0.courseName.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\u{5168}\u{90E8}\u{8BFE}\u{7A0B}\u{753B}\u{50CF}")
                    .font(.headline)
                Spacer()
                Button("+ \u{65B0}\u{5EFA}") {
                    editingProfile = nil
                    editName = ""
                    editKeywords = ""
                    editFocus = ""
                    editForbidden = ""
                    isCreating = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("\u{641C}\u{7D22}\u{8BFE}\u{7A0B}...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            if isCreating || editingProfile != nil {
                profileForm
            }

            if filtered.isEmpty {
                Spacer()
                Text(searchQuery.isEmpty ? "\u{6682}\u{65E0}\u{8BFE}\u{7A0B}\u{753B}\u{50CF}" : "\u{672A}\u{627E}\u{5230}\u{7ED3}\u{679C}")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered, id: \.courseName) { profile in
                            profileCard(profile)
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear { reload() }
    }

    private var profileForm: some View {
        GroupBox(label: Text(isCreating ? "\u{65B0}\u{5EFA}\u{8BFE}\u{7A0B}\u{753B}\u{50CF}" : "\u{7F16}\u{8F91}\u{8BFE}\u{7A0B}\u{753B}\u{50CF}").font(.subheadline)) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("\u{8BFE}\u{7A0B}\u{540D}", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isCreating) // can't rename
                TextField("\u{5173}\u{952E}\u{8BCD}\u{FF08}\u{9017}\u{53F7}\u{5206}\u{9694}\u{FF09}", text: $editKeywords)
                    .textFieldStyle(.roundedBorder)
                TextField("\u{8003}\u{8BD5}\u{5BFC}\u{5411}", text: $editFocus)
                    .textFieldStyle(.roundedBorder)
                TextField("\u{7981}\u{6B62}\u{8FC7}\u{5EA6}\u{7B80}\u{5316}\u{FF08}\u{9017}\u{53F7}\u{5206}\u{9694}\u{FF09}", text: $editForbidden)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("\u{4FDD}\u{5B58}") {
                        saveForm()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("\u{53D6}\u{6D88}") {
                        isCreating = false
                        editingProfile = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func profileCard(_ profile: CourseProfile) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.courseName)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(formatDate(profile.updatedAt))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if !profile.majorKeywords.isEmpty {
                    Text("\u{5173}\u{952E}\u{8BCD}: \(profile.majorKeywords.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if !profile.examFocus.isEmpty {
                    Text("\u{8003}\u{8BD5}\u{5BFC}\u{5411}: \(profile.examFocus)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if !profile.forbiddenSimplifications.isEmpty {
                    Text("\u{7981}\u{6B62}\u{7B80}\u{5316}: \(profile.forbiddenSimplifications.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Button("\u{7F16}\u{8F91}") {
                        beginEdit(profile)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    Button("\u{5220}\u{9664}") {
                        CourseProfileStore.shared.deleteProfile(courseName: profile.courseName)
                        reload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundColor(.red)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func beginEdit(_ profile: CourseProfile) {
        isCreating = false
        editingProfile = profile
        editName = profile.courseName
        editKeywords = profile.majorKeywords.joined(separator: ", ")
        editFocus = profile.examFocus
        editForbidden = profile.forbiddenSimplifications.joined(separator: ", ")
    }

    private func saveForm() {
        let keywords = editKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let forbidden = editForbidden.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let profile = CourseProfile(
            courseName: editName.trimmingCharacters(in: .whitespacesAndNewlines),
            majorKeywords: keywords,
            examFocus: editFocus.trimmingCharacters(in: .whitespacesAndNewlines),
            forbiddenSimplifications: forbidden
        )
        CourseProfileStore.shared.upsert(profile)
        isCreating = false
        editingProfile = nil
        reload()
    }

    private func reload() {
        profiles = CourseProfileStore.shared.allProfiles()
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
