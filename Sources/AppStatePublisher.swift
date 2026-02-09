import Foundation
import SwiftUI

final class AppStatePublisher: ObservableObject {
    @Published var state: AppState = .idle
    @Published var mode: CaptureMode? = nil
    @Published var currentTranscript: String = ""
    @Published var lastFinalText: String = ""
    @Published var errorMessage: String? = nil
    @Published var permissions = PermissionSnapshot(microphone: false, accessibility: false, inputMonitoring: false)
    @Published var serviceReady: Bool = false
    @Published var remainingRecordSeconds: Int? = nil
    @Published var hotkeyConflictRealtime: Bool = false
    @Published var hotkeyConflictFile: Bool = false
}
