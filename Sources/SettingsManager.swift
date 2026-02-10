import Foundation
import SwiftUI
import Carbon

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    static let maxRecordLimitSeconds = 3 * 60 * 60
    static let minRecordLimitSeconds = 60

    // MARK: - Hotkeys
    @AppStorage("realtimeHotkeyCode") var realtimeHotkeyCode: Int = kVK_Space       // 49
    @AppStorage("realtimeHotkeyModifiers") var realtimeHotkeyModifiers: Int = Int(CGEventFlags.maskAlternate.rawValue)
    @AppStorage("fileHotkeyCode") var fileHotkeyCode: Int = kVK_LeftArrow            // 123
    @AppStorage("fileHotkeyModifiers") var fileHotkeyModifiers: Int = Int(CGEventFlags.maskAlternate.rawValue)

    // MARK: - ASR Configuration
    @AppStorage("language") var language: String = "zh"
    @AppStorage("model") var model: String = "qwen3-asr-flash-realtime"
    @AppStorage("fileModel") var fileModel: String = "qwen3-asr-flash"
    @AppStorage("wsBaseURL") var wsBaseURL: String = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
    @AppStorage("fileASRURL") var fileASRURL: String = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    // MARK: - API Key (stored in UserDefaults with default)
    @AppStorage("apiKey") var apiKey: String = "sk-82f726c10954417187fa35d39630fd7c"
    @AppStorage("dashscopeCustomAPIKey") var dashscopeCustomAPIKey: String = ""
    @AppStorage("useBuiltinDashscopeAPI") var useBuiltinDashscopeAPI: Bool = true

    // MARK: - Behavior
    @AppStorage("autoStopEnabled") var autoStopEnabled: Bool = true
    @AppStorage("autoStopDelay") var autoStopDelay: Double = 2.2
    @AppStorage("realtimeTypeEnabled") var realtimeTypeEnabled: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("didAutoShowOnboardingOnce") var didAutoShowOnboardingOnce: Bool = false
    @AppStorage("openDashboardOnLaunch") var openDashboardOnLaunch: Bool = true
    @AppStorage("showRecordingIndicator") var showRecordingIndicator: Bool = true
    @AppStorage("recordingIndicatorAutoHide") var recordingIndicatorAutoHide: Bool = true
    @AppStorage("punctuationStabilizationEnabled") var punctuationStabilizationEnabled: Bool = true
    @AppStorage("punctuationStabilizationDelayMs") var punctuationStabilizationDelayMs: Double = 280
    @AppStorage("secondPassCleanupEnabled") var secondPassCleanupEnabled: Bool = true
    @AppStorage("permissionTrustOverride") var permissionTrustOverride: Bool = false
    @AppStorage("normalRecordLimitSeconds") var normalRecordLimitSeconds: Double = 300
    @AppStorage("markdownRecordLimitSeconds") var markdownRecordLimitSeconds: Double = 900
    @AppStorage("lectureRecordLimitSeconds") var lectureRecordLimitSeconds: Double = 3600

    // MARK: - Markdown Mode
    @AppStorage("markdownModeEnabled") var markdownModeEnabled: Bool = false
    @AppStorage("mimoAPIKey") var mimoAPIKey: String = "sk-ci6ls0cfzvw5z9jg81f54f8p1wxix0p7xe00fkz9knekwv3r"
    @AppStorage("mimoCustomAPIKey") var mimoCustomAPIKey: String = ""
    @AppStorage("useBuiltinMimoAPI") var useBuiltinMimoAPI: Bool = true
    @AppStorage("mimoBaseURL") var mimoBaseURL: String = "https://api.xiaomimimo.com/v1/chat/completions"
    @AppStorage("mimoModel") var mimoModel: String = "mimo-v2-flash"
    @AppStorage("defaultMarkdownLevel") var defaultMarkdownLevel: Int = 1  // 0=faithful, 1=light, 2=deep
    @AppStorage("obsidianVaultPath") var obsidianVaultPath: String = ""
    @AppStorage("llmMode") var llmMode: String = "dual"  // "mimo" | "glm" | "dual"
    @AppStorage("glmAPIKey") var glmAPIKey: String = "9b6b180bd5b34638a2e9eade11c46591.GhjSzVT4RoSkPmTp"
    @AppStorage("glmCustomAPIKey") var glmCustomAPIKey: String = ""
    @AppStorage("useBuiltinGLMAPI") var useBuiltinGLMAPI: Bool = true
    @AppStorage("glmBaseURL") var glmBaseURL: String = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    @AppStorage("glmModel") var glmModel: String = "GLM-4.7"
    @AppStorage("mimoThinkingEnabled") var mimoThinkingEnabled: Bool = false
    @AppStorage("glmThinkingEnabled") var glmThinkingEnabled: Bool = false
    @AppStorage("dashboardPreviewEnabled") var dashboardPreviewEnabled: Bool = true
    @AppStorage("panelPreviewEnabled") var panelPreviewEnabled: Bool = false

    var hasAPIKey: Bool { !apiKey.isEmpty }
    var effectiveDashscopeAPIKey: String { useBuiltinDashscopeAPI ? apiKey : dashscopeCustomAPIKey }
    var effectiveMimoAPIKey: String { useBuiltinMimoAPI ? mimoAPIKey : mimoCustomAPIKey }
    var effectiveGLMAPIKey: String { useBuiltinGLMAPI ? glmAPIKey : glmCustomAPIKey }
    var effectiveNormalRecordLimitSeconds: Int { clampRecordLimit(normalRecordLimitSeconds) }
    var effectiveMarkdownRecordLimitSeconds: Int { clampRecordLimit(markdownRecordLimitSeconds) }
    var effectiveLectureRecordLimitSeconds: Int { clampRecordLimit(lectureRecordLimitSeconds) }

    func clampRecordLimit(_ rawValue: Double) -> Int {
        let minValue = Double(Self.minRecordLimitSeconds)
        let maxValue = Double(Self.maxRecordLimitSeconds)
        let clamped = min(max(rawValue, minValue), maxValue)
        return Int(clamped.rounded())
    }

    // MARK: - Hotkey display helpers

    func realtimeHotkeyDisplay() -> String {
        hotkeyDisplayString(keyCode: realtimeHotkeyCode, modifiers: realtimeHotkeyModifiers)
    }

    func fileHotkeyDisplay() -> String {
        hotkeyDisplayString(keyCode: fileHotkeyCode, modifiers: fileHotkeyModifiers)
    }

    func hotkeyDisplayString(keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        if flags.contains(.maskControl) { parts.append("\u{2303}") }
        if flags.contains(.maskAlternate) { parts.append("\u{2325}") }
        if flags.contains(.maskShift) { parts.append("\u{21E7}") }
        if flags.contains(.maskCommand) { parts.append("\u{2318}") }
        parts.append(keyCodeName(keyCode))
        return parts.joined()
    }

    func keyCodeName(_ code: Int) -> String {
        switch code {
        case kVK_Space: return "Space"
        case kVK_Return: return "\u{21A9}"
        case kVK_Tab: return "\u{21E5}"
        case kVK_Delete: return "\u{232B}"
        case kVK_Escape: return "\u{238B}"
        case kVK_LeftArrow: return "\u{2190}"
        case kVK_RightArrow: return "\u{2192}"
        case kVK_UpArrow: return "\u{2191}"
        case kVK_DownArrow: return "\u{2193}"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_0: return "0"
        default: return "Key\(code)"
        }
    }
}
