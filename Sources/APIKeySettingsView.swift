import SwiftUI

struct APIKeySettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var showKey = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dashscope API Key")
                        .font(.headline)

                    HStack {
                        Group {
                            if showKey {
                                TextField("sk-...", text: $settings.apiKey)
                            } else {
                                SecureField("sk-...", text: $settings.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(showKey ? "\u{9690}\u{85CF}" : "\u{663E}\u{793A}")
                    }

                    HStack(spacing: 12) {
                        Text("\u{7528}\u{4E8E}\u{963F}\u{91CC} Dashscope \u{8BED}\u{97F3}\u{8BC6}\u{522B} \u{2764}")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Link(destination: URL(string: "https://dashscope.console.aliyun.com/")!) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                Text("\u{83B7}\u{53D6} API Key")
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("\u{8EAB}\u{4EFD}\u{9A8C}\u{8BC1}", systemImage: "key.fill")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\u{9AD8}\u{7EA7}\u{8BBE}\u{7F6E}")
                        .font(.headline)

                    LabeledContent("\u{5B9E}\u{65F6}\u{6A21}\u{578B}") {
                        TextField("", text: $settings.model)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }

                    LabeledContent("\u{5F55}\u{97F3}\u{6A21}\u{578B}") {
                        TextField("", text: $settings.fileModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }

                    LabeledContent("WebSocket URL") {
                        TextField("", text: $settings.wsBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }

                    LabeledContent("\u{5F55}\u{97F3} ASR URL") {
                        TextField("", text: $settings.fileASRURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("\u{4E13}\u{5BB6}\u{8BBE}\u{7F6E}", systemImage: "gearshape.2")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
