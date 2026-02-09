import SwiftUI

struct PermissionGateView: View {
    @EnvironmentObject var appState: AppStatePublisher
    var onGrantMicrophone: () -> Void
    var onGrantAccessibility: () -> Void
    var onGrantInputMonitoring: () -> Void
    var onRefresh: () -> Void

    var body: some View {
        let snapshot = appState.permissions
        VStack(alignment: .leading, spacing: 16) {
            Text("FlashASR \u{9700}\u{8981} 3 \u{4E2A}\u{6743}\u{9650}\u{624D}\u{80FD}\u{6B63}\u{5E38}\u{5DE5}\u{4F5C}\u{54E6}")
                .font(.headline)

            permissionRow(title: "\u{9EA6}\u{514B}\u{98CE}", granted: snapshot.microphone, grantAction: onGrantMicrophone)
            permissionRow(title: "\u{8F85}\u{52A9}\u{529F}\u{80FD}", granted: snapshot.accessibility, grantAction: onGrantAccessibility)
            permissionRow(title: "\u{8F93}\u{5165}\u{76D1}\u{542C}", granted: snapshot.inputMonitoring, grantAction: onGrantInputMonitoring)

            if !snapshot.inputMonitoring {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\u{8F93}\u{5165}\u{76D1}\u{542C}\u{624B}\u{52A8}\u{6307}\u{5F15}\u{FF1A}")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("1) \u{70B9}\u{51FB}\u{201C}\u{6253}\u{5F00}\u{8F93}\u{5165}\u{76D1}\u{542C}\u{8BBE}\u{7F6E}\u{201D}\u{3002}2) \u{5982}\u{679C}\u{5217}\u{8868}\u{4E2D}\u{6CA1}\u{6709} FlashASR\u{FF0C}\u{8BF7}\u{70B9}\u{51FB}\u{201C}\u{5728} Finder \u{4E2D}\u{663E}\u{793A}\u{201D}\u{FF0C}\u{786E}\u{4FDD}\u{5E94}\u{7528}\u{5728} /Applications \u{76EE}\u{5F55}\u{FF0C}\u{7136}\u{540E}\u{91CD}\u{65B0}\u{6253}\u{5F00}\u{8BBE}\u{7F6E}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\u{5F53}\u{524D}\u{5E94}\u{7528}\u{8DEF}\u{5F84}\u{FF1A}\(PermissionService.currentAppPathString())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Button("\u{6253}\u{5F00}\u{8F93}\u{5165}\u{76D1}\u{542C}\u{8BBE}\u{7F6E}") { PermissionService.openInputMonitoringSettings() }
                        Button("\u{5728} Finder \u{4E2D}\u{663E}\u{793A}") { PermissionService.revealCurrentAppInFinder() }
                        Button("\u{590D}\u{5236}\u{5E94}\u{7528}\u{8DEF}\u{5F84}") { PermissionService.copyCurrentAppPathToClipboard() }
                    }
                    .buttonStyle(.bordered)

                    if !PermissionService.isInApplicationsFolder() || PermissionService.isRunningFromTranslocationOrDMG() {
                        Text("\u{5EFA}\u{8BAE}\u{FF1A}\u{8BF7}\u{5C06} FlashASR.app \u{79FB}\u{52A8}\u{5230} /Applications \u{76EE}\u{5F55}\u{540E}\u{518D}\u{542F}\u{52A8}\u{FF0C}\u{7136}\u{540E}\u{6388}\u{6743}\u{8F93}\u{5165}\u{76D1}\u{542C}")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            HStack {
                Button("\u{5237}\u{65B0}\u{72B6}\u{6001}", action: onRefresh)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text(snapshot.allGranted ? "\u{5C31}\u{7EEA}" : "\u{672A}\u{5C31}\u{7EEA}")
                    .foregroundColor(snapshot.allGranted ? .green : .orange)
                    .fontWeight(.semibold)
            }
        }
        .padding(20)
        .frame(width: 640, height: 360)
    }

    @ViewBuilder
    private func permissionRow(title: String, granted: Bool, grantAction: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(granted ? .green : .red)
            Text(title)
            Spacer()
            Button(granted ? "\u{5DF2}\u{6388}\u{6743}" : "\u{53BB}\u{6388}\u{6743}") {
                grantAction()
            }
            .disabled(granted)
        }
    }
}
