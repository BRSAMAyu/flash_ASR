import Foundation
import SwiftUI

final class AppStatePublisher: ObservableObject {
    @Published var state: AppState = .idle
    @Published var mode: CaptureMode? = nil
    @Published var currentTranscript: String = ""
    @Published var lastFinalText: String = ""
    @Published var errorMessage: String? = nil
}
