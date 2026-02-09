import SwiftUI
import AVFoundation
import ApplicationServices

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var step = 0

    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var permCheckTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? Color.pink : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: apiKeyStep
                case 2: permissionsStep
                case 3: hotkeysStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer()
        }
        .frame(width: 480, height: 460)
        .padding()
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .pink.opacity(0.3), radius: 8, y: 4)

            Text("FlashASR")
                .font(.title)
                .fontWeight(.bold)

            Text("\u{2728} \u{6B22}\u{8FCE}\u{4F7F}\u{7528} FlashASR \u{2728}\n\u{8D85}\u{5FEB}\u{7684}\u{8BED}\u{97F3}\u{8F6C}\u{6587}\u{5B57}\u{5C0F}\u{52A9}\u{624B}\u{FF0C}\u{8BA9}\u{4F60}\u{7684}\u{58F0}\u{97F3}\u{79D2}\u{53D8}\u{6587}\u{5B57}\u{FF5E}")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Spacer()

            Button("\u{5F00}\u{59CB}\u{8BBE}\u{7F6E}\u{5427} \u{2192}") { step = 1 }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .controlSize(.large)
        }
    }

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("API \u{5BC6}\u{94A5}")
                .font(.title2)
                .fontWeight(.bold)

            Text("FlashASR \u{4F7F}\u{7528}\u{963F}\u{91CC} Dashscope \u{8BED}\u{97F3}\u{8BC6}\u{522B}\u{670D}\u{52A1}\n\u{5DF2}\u{7ECF}\u{5185}\u{7F6E}\u{4E86}\u{9ED8}\u{8BA4}\u{5BC6}\u{94A5}\u{FF0C}\u{4E5F}\u{53EF}\u{4EE5}\u{6362}\u{6210}\u{4F60}\u{81EA}\u{5DF1}\u{7684}\u{54E6}\u{FF5E}")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("sk-...", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
            .padding(.top, 8)

            Link(destination: URL(string: "https://dashscope.console.aliyun.com/")!) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.right.square")
                    Text("\u{83B7}\u{53D6}\u{4F60}\u{81EA}\u{5DF1}\u{7684} API Key")
                }
                .font(.caption)
            }

            Spacer()

            HStack {
                Button("\u{2190} \u{4E0A}\u{4E00}\u{6B65}") { step = 0 }
                    .buttonStyle(.bordered)
                Spacer()
                Button("\u{4E0B}\u{4E00}\u{6B65} \u{2192}") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(settings.apiKey.isEmpty)
            }
            .frame(maxWidth: 360)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)

            Text("\u{6743}\u{9650}\u{8BBE}\u{7F6E}")
                .font(.title2)
                .fontWeight(.bold)

            Text("\u{8BF7}\u{5141}\u{8BB8}\u{4EE5}\u{4E0B}\u{6743}\u{9650}\u{FF0C}\u{8FD9}\u{6837}\u{6211}\u{624D}\u{80FD}\u{597D}\u{597D}\u{5DE5}\u{4F5C}")
                .foregroundColor(.secondary)
                .font(.subheadline)

            VStack(spacing: 0) {
                permissionRow(
                    icon: "mic.fill",
                    color: .red,
                    title: "\u{9EA6}\u{514B}\u{98CE}",
                    desc: "\u{7528}\u{6765}\u{542C}\u{4F60}\u{8BF4}\u{8BDD}\u{FF0C}\u{8FD9}\u{4E2A}\u{5FC5}\u{987B}\u{8981}\u{6709}\u{54E6}",
                    granted: micGranted,
                    action: {
                        PermissionService.requestMicrophone { _ in refreshPermissions() }
                    },
                    settingsAction: {
                        PermissionService.openMicrophoneSettings()
                    }
                )

                Divider().padding(.leading, 44)

                permissionRow(
                    icon: "hand.raised.fill",
                    color: .blue,
                    title: "\u{8F85}\u{52A9}\u{529F}\u{80FD}",
                    desc: "\u{7528}\u{6765}\u{628A}\u{8F6C}\u{5199}\u{7ED3}\u{679C}\u{8F93}\u{5165}\u{5230}\u{5176}\u{4ED6} App",
                    granted: accessibilityGranted,
                    action: {
                        PermissionService.requestAccessibilityPrompt()
                    },
                    settingsAction: {
                        PermissionService.openAccessibilitySettings()
                    }
                )

                Divider().padding(.leading, 44)

                permissionRow(
                    icon: "keyboard.fill",
                    color: .purple,
                    title: "\u{8F93}\u{5165}\u{76D1}\u{542C}",
                    desc: "\u{7528}\u{6765}\u{76D1}\u{542C}\u{5FEB}\u{6377}\u{952E}\u{FF0C}\u{968F}\u{65F6}\u{547C}\u{5524}\u{6211}",
                    granted: inputMonitoringGranted,
                    action: {
                        PermissionService.requestInputMonitoringPrompt()
                    },
                    settingsAction: {
                        PermissionService.openInputMonitoringSettings()
                    }
                )
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
            .frame(maxWidth: 400)

            if allPermissionsGranted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\u{6240}\u{6709}\u{6743}\u{9650}\u{5DF2}\u{5C31}\u{7EEA}\u{FF0C}\u{68D2}\u{68D2}\u{54D2}")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                Text("点击去开启跳转系统设置。若权限明明已开却仍显示未授权，请在系统设置中用“-”删掉 FlashASR 再重新添加授权。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("\u{6211}\u{5DF2}\u{624B}\u{52A8}\u{6388}\u{6743}\u{FF0C}\u{7EE7}\u{7EED}\u{FF08}\u{68C0}\u{6D4B}\u{53EF}\u{80FD}\u{8BEF}\u{5224}\u{FF09}") {
                    settings.permissionTrustOverride = true
                    step = 3
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Spacer()

            HStack {
                Button("\u{2190} \u{4E0A}\u{4E00}\u{6B65}") { step = 1 }
                    .buttonStyle(.bordered)
                Spacer()
                Button("\u{4E0B}\u{4E00}\u{6B65} \u{2192}") { step = 3 }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
            }
            .frame(maxWidth: 400)
        }
        .onAppear {
            refreshPermissions()
            permCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                refreshPermissions()
            }
        }
        .onDisappear {
            permCheckTimer?.invalidate()
            permCheckTimer = nil
        }
    }

    private var hotkeysStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 40))
                .foregroundColor(.purple)

            Text("\u{5FEB}\u{6377}\u{952E}\u{8BF4}\u{660E}")
                .font(.title2)
                .fontWeight(.bold)

            Text("\u{5728} Mac \u{4E0A}\u{968F}\u{65F6}\u{968F}\u{5730}\u{6309}\u{4E0B}\u{5FEB}\u{6377}\u{952E}\u{5C31}\u{80FD}\u{547C}\u{5524}\u{6211}")
                .foregroundColor(.secondary)
                .font(.subheadline)

            VStack(spacing: 12) {
                hotkeyRow(
                    label: "\u{5B9E}\u{65F6}\u{8F6C}\u{5199}",
                    shortcut: settings.realtimeHotkeyDisplay(),
                    desc: "\u{8FB9}\u{8BF4}\u{8FB9}\u{8F6C}\u{FF0C}\u{5B9E}\u{65F6}\u{770B}\u{5230}\u{6587}\u{5B57}"
                )
                hotkeyRow(
                    label: "\u{5F55}\u{97F3}\u{8F6C}\u{5199}",
                    shortcut: settings.fileHotkeyDisplay(),
                    desc: "\u{5148}\u{5F55}\u{97F3}\u{518D}\u{8F6C}\u{6587}\u{5B57}\u{FF0C}\u{66F4}\u{7A33}\u{5B9A}"
                )
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
            .frame(maxWidth: 380)

            Text("\u{53EF}\u{4EE5}\u{5728}\u{8BBE}\u{7F6E}\u{91CC}\u{4FEE}\u{6539}")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Button("\u{2190} \u{4E0A}\u{4E00}\u{6B65}") { step = 2 }
                    .buttonStyle(.bordered)
                Spacer()
                Button("\u{5F00}\u{59CB}\u{4F7F}\u{7528}\u{5427}") {
                    settings.hasCompletedOnboarding = true
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .controlSize(.large)
            }
            .frame(maxWidth: 380)
        }
    }

    private var allPermissionsGranted: Bool {
        micGranted && accessibilityGranted && inputMonitoringGranted
    }

    private func refreshPermissions() {
        let snap = PermissionService.snapshot()
        micGranted = snap.microphone
        accessibilityGranted = snap.accessibility
        inputMonitoringGranted = snap.inputMonitoring
    }

    private func permissionRow(
        icon: String, color: Color, title: String, desc: String,
        granted: Bool, action: @escaping () -> Void, settingsAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else {
                Button("\u{53BB}\u{5F00}\u{542F}") {
                    action()
                    settingsAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.pink)
            }
        }
        .padding(.vertical, 8)
    }

    private func hotkeyRow(label: String, shortcut: String, desc: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).fontWeight(.medium)
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(shortcut)
                .font(.system(size: 14, design: .rounded))
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.pink.opacity(0.15)))
        }
    }
}
