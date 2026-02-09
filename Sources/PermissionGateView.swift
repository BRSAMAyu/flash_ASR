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
            Text("FlashASR needs 3 permissions before hotkeys and transcription are enabled.")
                .font(.headline)

            permissionRow(title: "Microphone", granted: snapshot.microphone, grantAction: onGrantMicrophone)
            permissionRow(title: "Accessibility", granted: snapshot.accessibility, grantAction: onGrantAccessibility)
            permissionRow(title: "Input Monitoring", granted: snapshot.inputMonitoring, grantAction: onGrantInputMonitoring)

            if !snapshot.inputMonitoring {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Input Monitoring manual fallback:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("1) Click Open Input Monitoring. 2) If FlashASR is not listed, click Reveal App in Finder, ensure app is in /Applications, then re-open settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Current app path: \(PermissionService.currentAppPathString())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Button("Open Input Monitoring") { PermissionService.openInputMonitoringSettings() }
                        Button("Reveal App in Finder") { PermissionService.revealCurrentAppInFinder() }
                        Button("Copy App Path") { PermissionService.copyCurrentAppPathToClipboard() }
                    }
                    .buttonStyle(.bordered)

                    if !PermissionService.isInApplicationsFolder() || PermissionService.isRunningFromTranslocationOrDMG() {
                        Text("Recommendation: move FlashASR.app to /Applications and launch from there, then grant Input Monitoring.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }

            HStack {
                Button("Refresh Status", action: onRefresh)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text(snapshot.allGranted ? "Ready" : "Not Ready")
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
            Button(granted ? "Granted" : "Grant") {
                grantAction()
            }
            .disabled(granted)
        }
    }
}
