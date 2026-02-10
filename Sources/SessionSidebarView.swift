import SwiftUI

struct SessionSidebarView: View {
    enum DateFilter: String, CaseIterable {
        case all
        case days7
        case days30

        var displayName: String {
            switch self {
            case .all: return "\u{5168}\u{90E8}\u{65E5}\u{671F}"
            case .days7: return "7\u{5929}\u{5185}"
            case .days30: return "30\u{5929}\u{5185}"
            }
        }
    }

    enum SortOrder: String, CaseIterable {
        case time
        case name
        case wordCount

        var displayName: String {
            switch self {
            case .time: return "\u{6309}\u{65F6}\u{95F4}"
            case .name: return "\u{6309}\u{540D}\u{79F0}"
            case .wordCount: return "\u{6309}\u{5B57}\u{6570}"
            }
        }
    }

    @EnvironmentObject var appState: AppStatePublisher
    @State private var searchQuery = ""
    @State private var hoveredId: UUID? = nil
    @State private var selectedKind: SessionKind? = nil
    @State private var requiresLectureNotes = false
    @State private var dateFilter: DateFilter = .all
    @State private var sortOrder: SortOrder = .time
    @State private var renamingId: UUID? = nil
    @State private var renameText = ""

    private var filteredSessions: [TranscriptionSession] {
        let base = SessionManager.shared.searchSessions(
            query: searchQuery,
            kind: selectedKind,
            requiresLectureNotes: requiresLectureNotes
        )
        let dateFiltered = base.filter { session in
            switch dateFilter {
            case .all:
                return true
            case .days7:
                return Date().timeIntervalSince(session.lectureDate ?? session.createdAt) <= 7 * 24 * 3600
            case .days30:
                return Date().timeIntervalSince(session.lectureDate ?? session.createdAt) <= 30 * 24 * 3600
            }
        }
        switch sortOrder {
        case .time:
            return dateFiltered // already sorted by time from SessionManager
        case .name:
            return dateFiltered.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .wordCount:
            return dateFiltered.sorted { $0.wordCount > $1.wordCount }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("\u{641C}\u{7D22}\u{4F1A}\u{8BDD}...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { selectedKind?.rawValue ?? "all" },
                    set: { selectedKind = $0 == "all" ? nil : SessionKind(rawValue: $0) }
                )) {
                    Text("\u{5168}\u{90E8}").tag("all")
                    Text("\u{8BFE}\u{5802}").tag(SessionKind.lecture.rawValue)
                    Text("\u{5E38}\u{89C4}").tag(SessionKind.regular.rawValue)
                }
                .pickerStyle(.segmented)
                .font(.system(size: 11))

                Toggle("\u{5DF2}\u{751F}\u{6210}", isOn: $requiresLectureNotes)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                    .frame(width: 64)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            HStack(spacing: 6) {
                Picker("", selection: $dateFilter) {
                    ForEach(DateFilter.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 11))

                Picker("", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 11))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            // Session list
            if filteredSessions.isEmpty {
                Spacer()
                Text(searchQuery.isEmpty ? "\u{6682}\u{65E0}\u{4F1A}\u{8BDD}" : "\u{672A}\u{627E}\u{5230}\u{7ED3}\u{679C}")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredSessions) { session in
                            sessionCard(session)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(filteredSessions.count) \u{4E2A}\u{4F1A}\u{8BDD}")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func sessionCard(_ session: TranscriptionSession) -> some View {
        let isSelected = appState.currentSession?.id == session.id
        return HStack(spacing: 4) {
            Button(action: {
                NotificationCenter.default.post(name: .openSession, object: nil, userInfo: ["id": session.id.uuidString])
            }) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        if renamingId == session.id {
                            TextField("", text: $renameText, onCommit: {
                                commitRename(session)
                            })
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(session.displayTitle)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .onTapGesture(count: 2) {
                                    renamingId = session.id
                                    renameText = session.title.isEmpty ? session.displayTitle : session.title
                                }
                        }
                        if session.kind == .lecture {
                            Text("\u{8BFE}")
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.18))
                                .cornerRadius(3)
                            lectureNoteBadge(session)
                        }
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Text(session.formattedDate)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        if session.rounds.count > 0 {
                            Text("\(session.rounds.count)\u{8F6E}")
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }

                        let wc = session.wordCount
                        if wc > 0 {
                            Text("\(wc)\u{5B57}")
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }

                        Spacer()
                    }

                    if !session.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(session.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(3)
                            }
                            if session.tags.count > 3 {
                                Text("+\(session.tags.count - 3)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hoveredId == session.id && appState.state == .idle {
                Button(action: {
                    NotificationCenter.default.post(name: .deleteSession, object: nil, userInfo: ["id": session.id.uuidString])
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
        }
        .onHover { isHovering in
            hoveredId = isHovering ? session.id : nil
        }
        .contextMenu {
            Button("\u{91CD}\u{547D}\u{540D}") {
                renamingId = session.id
                renameText = session.title.isEmpty ? session.displayTitle : session.title
            }
            Button("\u{5220}\u{9664}", role: .destructive) {
                NotificationCenter.default.post(name: .deleteSession, object: nil, userInfo: ["id": session.id.uuidString])
            }
        }
    }

    @ViewBuilder
    private func lectureNoteBadge(_ session: TranscriptionSession) -> some View {
        let hasLesson = !(session.lectureOutputs?[LectureNoteMode.lessonPlan.rawValue] ?? "").isEmpty
        let hasReview = !(session.lectureOutputs?[LectureNoteMode.review.rawValue] ?? "").isEmpty
        if hasLesson && hasReview {
            Text("\u{2713}\u{7B14}\u{8BB0}")
                .font(.system(size: 8, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.20))
                .foregroundColor(.green)
                .cornerRadius(3)
        } else if hasLesson || hasReview {
            Text("\u{90E8}\u{5206}")
                .font(.system(size: 8, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.20))
                .foregroundColor(.orange)
                .cornerRadius(3)
        } else {
            Text("\u{5F85}\u{751F}\u{6210}")
                .font(.system(size: 8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .foregroundColor(.secondary)
                .cornerRadius(3)
        }
    }

    private func commitRename(_ session: TranscriptionSession) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingId = nil
        guard !trimmed.isEmpty else { return }
        NotificationCenter.default.post(name: .renameSession, object: nil, userInfo: [
            "id": session.id.uuidString,
            "title": trimmed
        ])
    }
}
