import Foundation
import AppKit

enum DiagnosticsService {
    static func export(settings: SettingsManager, state: AppStatePublisher) throws -> URL {
        let fm = FileManager.default
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FlashASR-diagnostic-\(ts)", isDirectory: true)
        try? fm.removeItem(at: tempDir)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let reportURL = tempDir.appendingPathComponent("report.txt")
        let perms = PermissionService.snapshot()
        let report = """
        FlashASR Diagnostic Report
        Time: \(Date())

        Service Ready: \(state.serviceReady)
        App State: \(state.state)
        Mode: \(String(describing: state.mode))

        Permissions:
          Microphone: \(perms.microphone)
          Accessibility: \(perms.accessibility)
          Input Monitoring: \(perms.inputMonitoring)

        Hotkeys:
          Realtime: \(settings.realtimeHotkeyDisplay()) (code=\(settings.realtimeHotkeyCode), mods=\(settings.realtimeHotkeyModifiers))
          File: \(settings.fileHotkeyDisplay()) (code=\(settings.fileHotkeyCode), mods=\(settings.fileHotkeyModifiers))
          Realtime conflict: \(state.hotkeyConflictRealtime)
          File conflict: \(state.hotkeyConflictFile)

        Settings:
          language=\(settings.language)
          model=\(settings.model)
          fileModel=\(settings.fileModel)
          wsBaseURL=\(settings.wsBaseURL)
          fileASRURL=\(settings.fileASRURL)
          autoStopEnabled=\(settings.autoStopEnabled)
          autoStopDelay=\(settings.autoStopDelay)
          realtimeTypeEnabled=\(settings.realtimeTypeEnabled)
          showRecordingIndicator=\(settings.showRecordingIndicator)
          recordingIndicatorAutoHide=\(settings.recordingIndicatorAutoHide)
          punctuationStabilizationEnabled=\(settings.punctuationStabilizationEnabled)
          punctuationStabilizationDelayMs=\(settings.punctuationStabilizationDelayMs)
          secondPassCleanupEnabled=\(settings.secondPassCleanupEnabled)
          segmentedFilePipelineEnabled=\(settings.segmentedFilePipelineEnabled)

        Segmented Pipeline:
          activeFileSegmentSessionId=\(String(describing: state.activeFileSegmentSessionId))
          fileSegmentProgress=\(state.fileSegmentProgress)
          fileSegmentStageText=\(state.fileSegmentStageText)
          failedFileSegments=\(state.failedFileSegments)
          fileTotalSegments=\(state.fileTotalSegments)
          \(SegmentedRecordingPipeline.diagnosticsSummary())
        """
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        let logURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/FlashASR.log")
        if fm.fileExists(atPath: logURL.path) {
            let dst = tempDir.appendingPathComponent("FlashASR.log")
            try? fm.copyItem(at: logURL, to: dst)
        }

        let zipURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/FlashASR-diagnostic-\(ts).zip")
        try? fm.removeItem(at: zipURL)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", tempDir.path, zipURL.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "DiagnosticsService", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to create diagnostic zip"])
        }
        return zipURL
    }

    static func copyPermissionSelfCheck(state: AppStatePublisher) {
        let p = state.permissions
        let s = "Permission Self-Check\nMicrophone=\(p.microphone)\nAccessibility=\(p.accessibility)\nInputMonitoring=\(p.inputMonitoring)\nServiceReady=\(state.serviceReady)"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}
