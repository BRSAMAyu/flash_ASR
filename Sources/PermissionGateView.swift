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
        .frame(width: 520, height: 250)
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
