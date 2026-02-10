import SwiftUI

struct CourseProfileSheet: View {
    @EnvironmentObject var appState: AppStatePublisher
    @State private var selectedCourseName: String = ""
    @State private var isNewProfile = false

    // New profile fields
    @State private var newName = ""
    @State private var newKeywords = ""
    @State private var newFocus = ""
    @State private var newForbidden = ""

    private var existingNames: [String] {
        CourseProfileStore.shared.allCoursenames()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\u{8BFE}\u{7A0B}\u{753B}\u{50CF}")
                .font(.headline)

            if !existingNames.isEmpty && !isNewProfile {
                Picker("\u{9009}\u{62E9}\u{8BFE}\u{7A0B}", selection: $selectedCourseName) {
                    Text("\u{8BF7}\u{9009}\u{62E9}...").tag("")
                    ForEach(existingNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Button(isNewProfile ? "\u{9009}\u{62E9}\u{5DF2}\u{6709}" : "+ \u{65B0}\u{5EFA}\u{8BFE}\u{7A0B}") {
                    isNewProfile.toggle()
                    if isNewProfile {
                        selectedCourseName = ""
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }

            if isNewProfile {
                TextField("\u{8BFE}\u{7A0B}\u{540D}", text: $newName)
                    .textFieldStyle(.roundedBorder)
                TextField("\u{5173}\u{952E}\u{8BCD}\u{FF08}\u{9017}\u{53F7}\u{5206}\u{9694}\u{FF09}", text: $newKeywords)
                    .textFieldStyle(.roundedBorder)
                TextField("\u{8003}\u{8BD5}\u{5BFC}\u{5411}", text: $newFocus)
                    .textFieldStyle(.roundedBorder)
                TextField("\u{7981}\u{6B62}\u{8FC7}\u{5EA6}\u{7B80}\u{5316}\u{FF08}\u{9017}\u{53F7}\u{5206}\u{9694}\u{FF09}", text: $newForbidden)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("\u{53D6}\u{6D88}") {
                    appState.showCourseProfileSheet = false
                    appState.pendingLectureURL = nil
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                Button("\u{786E}\u{5B9A}") {
                    confirm()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(confirmDisabled)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let first = existingNames.first {
                selectedCourseName = first
            }
            if existingNames.isEmpty {
                isNewProfile = true
            }
        }
    }

    private var confirmDisabled: Bool {
        if isNewProfile {
            return newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return selectedCourseName.isEmpty
    }

    private func confirm() {
        let profile: CourseProfile
        if isNewProfile {
            let keywords = newKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let forbidden = newForbidden.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            profile = CourseProfile(
                courseName: newName.trimmingCharacters(in: .whitespacesAndNewlines),
                majorKeywords: keywords,
                examFocus: newFocus.trimmingCharacters(in: .whitespacesAndNewlines),
                forbiddenSimplifications: forbidden
            )
        } else {
            profile = CourseProfileStore.shared.profile(courseName: selectedCourseName) ?? CourseProfile(courseName: selectedCourseName)
        }
        NotificationCenter.default.post(name: .completeLectureProfile, object: nil, userInfo: ["profile": profile])
    }
}
