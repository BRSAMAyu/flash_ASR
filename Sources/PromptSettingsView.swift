import SwiftUI

struct PromptSettingsView: View {
    @State private var selectedProfile: PromptProfile = .light
    @State private var promptText: String = ""
    @State private var showResetAlert = false
    @State private var showDefaultSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile selector
            HStack(spacing: 8) {
                Text("\u{63D0}\u{793A}\u{8BCD}\u{6A21}\u{677F}")
                    .font(.headline)
                Picker("", selection: $selectedProfile) {
                    ForEach(PromptProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)

                if PromptManager.shared.hasCustomPrompt(for: selectedProfile) {
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
                    PromptManager.shared.savePrompt(promptText, for: selectedProfile)
                }
                .buttonStyle(.borderedProminent)
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("\u{91CD}\u{7F6E}\u{4E3A}\u{9ED8}\u{8BA4}") {
                    showResetAlert = true
                }
                .buttonStyle(.bordered)
                .disabled(!PromptManager.shared.hasCustomPrompt(for: selectedProfile))

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
            loadPromptForProfile()
        }
        .onChange(of: selectedProfile) { _, _ in
            loadPromptForProfile()
        }
        .alert("\u{91CD}\u{7F6E}\u{63D0}\u{793A}\u{8BCD}", isPresented: $showResetAlert) {
            Button("\u{91CD}\u{7F6E}", role: .destructive) {
                PromptManager.shared.resetPrompt(for: selectedProfile)
                loadPromptForProfile()
            }
            Button("\u{53D6}\u{6D88}", role: .cancel) {}
        } message: {
            Text("\u{786E}\u{5B9A}\u{8981}\u{5C06}\u{300C}\(selectedProfile.displayName)\u{300D}\u{7684}\u{63D0}\u{793A}\u{8BCD}\u{91CD}\u{7F6E}\u{4E3A}\u{9ED8}\u{8BA4}\u{FF1F}")
        }
        .sheet(isPresented: $showDefaultSheet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\u{9ED8}\u{8BA4}\u{6A21}\u{677F} - \(selectedProfile.displayName)")
                        .font(.headline)
                    Spacer()
                    Button("\u{5173}\u{95ED}") {
                        showDefaultSheet = false
                    }
                }
                ScrollView {
                    Text(PromptManager.shared.defaultPrompt(for: selectedProfile))
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

    private func loadPromptForProfile() {
        if let custom = PromptManager.shared.loadPrompt(for: selectedProfile) {
            promptText = custom
        } else {
            promptText = PromptManager.shared.defaultPrompt(for: selectedProfile)
        }
    }
}
