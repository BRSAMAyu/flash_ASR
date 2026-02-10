import SwiftUI

struct APIKeySettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var showDashscopeCustomKey = false
    @State private var showMimoCustomKey = false
    @State private var showGLMCustomKey = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dashscope API Key (ASR)")
                        .font(.headline)

                    Toggle("使用内置 Dashscope API", isOn: $settings.useBuiltinDashscopeAPI)
                    if settings.useBuiltinDashscopeAPI {
                        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("未配置内置 Dashscope API Key，请切换到自定义 Key 或先写入内置 Key。")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("当前使用内置 Dashscope API（默认 Key 不展示）。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Group {
                                if showDashscopeCustomKey {
                                    TextField("输入你自己的 Dashscope API Key", text: $settings.dashscopeCustomAPIKey)
                                } else {
                                    SecureField("输入你自己的 Dashscope API Key", text: $settings.dashscopeCustomAPIKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            Button(action: { showDashscopeCustomKey.toggle() }) {
                                Image(systemName: showDashscopeCustomKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Link("获取 Dashscope API Key", destination: URL(string: "https://dashscope.console.aliyun.com/")!)
                        .font(.caption)
                }
            } header: {
                Label("ASR 认证", systemImage: "waveform")
            }

            Section {
                Toggle("使用内置 MiMo API", isOn: $settings.useBuiltinMimoAPI)
                if settings.useBuiltinMimoAPI {
                    if settings.mimoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("未配置内置 MiMo API Key，请切换到自定义 Key 或先写入内置 Key。")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("当前使用内置 MiMo API（默认 Key 不展示）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Group {
                            if showMimoCustomKey {
                                TextField("输入你自己的 MiMo API Key", text: $settings.mimoCustomAPIKey)
                            } else {
                                SecureField("输入你自己的 MiMo API Key", text: $settings.mimoCustomAPIKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button(action: { showMimoCustomKey.toggle() }) {
                            Image(systemName: showMimoCustomKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                LabeledContent("MiMo 模型") {
                    TextField("", text: $settings.mimoModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 270)
                }
                LabeledContent("MiMo API URL") {
                    TextField("", text: $settings.mimoBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 270)
                }
                Link("获取 MiMo API（官方文档）", destination: URL(string: "https://platform.xiaomimimo.com/#/docs/welcome")!)
                    .font(.caption)
            } header: {
                Label("MiMo", systemImage: "sparkles")
            }

            Section {
                Toggle("使用内置 GLM API", isOn: $settings.useBuiltinGLMAPI)
                if settings.useBuiltinGLMAPI {
                    if settings.glmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("未配置内置 GLM API Key，请切换到自定义 Key 或先写入内置 Key。")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("当前使用内置 GLM API（默认 Key 不展示）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Group {
                            if showGLMCustomKey {
                                TextField("输入你自己的 GLM API Key", text: $settings.glmCustomAPIKey)
                            } else {
                                SecureField("输入你自己的 GLM API Key", text: $settings.glmCustomAPIKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        Button(action: { showGLMCustomKey.toggle() }) {
                            Image(systemName: showGLMCustomKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                LabeledContent("GLM 模型") {
                    TextField("", text: $settings.glmModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 270)
                }
                LabeledContent("GLM API URL") {
                    TextField("", text: $settings.glmBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 270)
                }
                Link("获取 GLM API（官方）", destination: URL(string: "https://bigmodel.cn/usercenter/proj-mgmt/apikeys")!)
                    .font(.caption)
            } header: {
                Label("GLM", systemImage: "brain")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("说明")
                        .font(.headline)
                    Text("默认 API 不会在界面中展示。你可随时切换为自定义 API。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("安全与使用", systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
