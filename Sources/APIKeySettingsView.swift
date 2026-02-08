import SwiftUI

struct APIKeySettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var showKey = false
    @State private var saved = false

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
                        .help(showKey ? "Hide key" : "Show key")
                    }

                    HStack(spacing: 12) {
                        Text("Used for Alibaba Dashscope speech recognition API")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Link(destination: URL(string: "https://dashscope.console.aliyun.com/")!) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Get API Key")
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Authentication", systemImage: "key.fill")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Advanced")
                        .font(.headline)

                    LabeledContent("Realtime Model") {
                        TextField("", text: $settings.model)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }

                    LabeledContent("File Model") {
                        TextField("", text: $settings.fileModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }

                    LabeledContent("WebSocket URL") {
                        TextField("", text: $settings.wsBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }

                    LabeledContent("File ASR URL") {
                        TextField("", text: $settings.fileASRURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 250)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
