import SwiftUI

struct SessionSidebarView: View {
    @EnvironmentObject var appState: AppStatePublisher
    @State private var searchQuery = ""
    @State private var hoveredId: UUID? = nil

    private var filteredSessions: [TranscriptionSession] {
        SessionManager.shared.searchSessions(query: searchQuery)
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
        return Button(action: {
            NotificationCenter.default.post(name: .openSession, object: nil, userInfo: ["id": session.id.uuidString])
        }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer()
                    if hoveredId == session.id {
                        Button(action: {
                            SessionManager.shared.deleteSession(id: session.id)
                            if appState.currentSession?.id == session.id {
                                appState.currentSession = nil
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
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
        .onHover { isHovering in
            hoveredId = isHovering ? session.id : nil
        }
        .contextMenu {
            Button("\u{5220}\u{9664}", role: .destructive) {
                SessionManager.shared.deleteSession(id: session.id)
                if appState.currentSession?.id == session.id {
                    appState.currentSession = nil
                }
            }
        }
    }
}
