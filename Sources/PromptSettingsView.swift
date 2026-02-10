import SwiftUI

struct PromptSettingsView: View {
    @State private var selectedLevel: MarkdownLevel = .light
    @State private var promptText: String = ""
    @State private var showResetAlert = false
    @State private var showDefaultSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Level selector
            HStack(spacing: 8) {
                Text("\u{6574}\u{7406}\u{7EA7}\u{522B}")
                    .font(.headline)
                Picker("", selection: $selectedLevel) {
                    ForEach(MarkdownLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                if PromptManager.shared.hasCustomPrompt(for: selectedLevel) {
                    Text("\u{5DF2}\u{81EA}\u{5B9A}\u{4E49}")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
                Spacer()
            }

            // Editor
            TextEditor(text: $promptText)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25), lineWidth: 1))

            // Actions
            HStack(spacing: 8) {
                Button("\u{4FDD}\u{5B58}") {
                    PromptManager.shared.savePrompt(promptText, for: selectedLevel)
                }
                .buttonStyle(.borderedProminent)
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("\u{91CD}\u{7F6E}\u{4E3A}\u{9ED8}\u{8BA4}") {
                    showResetAlert = true
                }
                .buttonStyle(.bordered)
                .disabled(!PromptManager.shared.hasCustomPrompt(for: selectedLevel))

                Button("\u{67E5}\u{770B}\u{9ED8}\u{8BA4}\u{6A21}\u{677F}") {
                    showDefaultSheet = true
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\u{63D0}\u{793A}\u{8BCD}\u{4FEE}\u{6539}\u{540E}\u{5BF9}\u{65B0}\u{5F55}\u{97F3}\u{751F}\u{6548}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            loadPromptForLevel()
        }
        .onChange(of: selectedLevel) { _, _ in
            loadPromptForLevel()
        }
        .alert("\u{91CD}\u{7F6E}\u{63D0}\u{793A}\u{8BCD}", isPresented: $showResetAlert) {
            Button("\u{91CD}\u{7F6E}", role: .destructive) {
                PromptManager.shared.resetPrompt(for: selectedLevel)
                loadPromptForLevel()
            }
            Button("\u{53D6}\u{6D88}", role: .cancel) {}
        } message: {
            Text("\u{786E}\u{5B9A}\u{8981}\u{5C06}\u{300C}\(selectedLevel.displayName)\u{300D}\u{7EA7}\u{522B}\u{7684}\u{63D0}\u{793A}\u{8BCD}\u{91CD}\u{7F6E}\u{4E3A}\u{9ED8}\u{8BA4}\u{FF1F}")
        }
        .sheet(isPresented: $showDefaultSheet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\u{9ED8}\u{8BA4}\u{6A21}\u{677F} - \(selectedLevel.displayName)")
                        .font(.headline)
                    Spacer()
                    Button("\u{5173}\u{95ED}") {
                        showDefaultSheet = false
                    }
                }
                ScrollView {
                    Text(MarkdownPrompts.defaultSystemPrompt(for: selectedLevel))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25), lineWidth: 1))
            }
            .padding()
            .frame(minWidth: 500, minHeight: 400)
        }
    }

    private func loadPromptForLevel() {
        if let custom = PromptManager.shared.loadPrompt(for: selectedLevel) {
            promptText = custom
        } else {
            promptText = MarkdownPrompts.defaultSystemPrompt(for: selectedLevel)
        }
    }
}
