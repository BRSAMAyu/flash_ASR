import Foundation

enum TextPostProcessor {
    private static let validReduplications: Set<String> = [
        "考虑", "商量", "照顾", "学习", "活动", "意思", "打扫", "整理", "观察", "比划", "凉快", "暖和", "通融", "收拾", "溜达", "探讨", "研究", "切磋", "交流", "沟通", "安排", "布置", "准备", "休息"
    ]

    static func clean(_ text: String) -> String {
        var out = text

        // Collapse repeated spaces
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Remove common filler words (Chinese) when standalone-ish
        let fillerPatterns = ["(^|\\s)(嗯+|呃+|那个|就是)(\\s|$)"]
        for p in fillerPatterns {
            out = out.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }

        // De-duplicate immediately repeated short tokens (ABAB -> AB), e.g. "但是但是" -> "但是"
        // We use {2,6} to catch 2-char stutters like "但是", but we must protect valid ABAB verbs (e.g. "商量商量")
        let pattern = "([\\p{Han}A-Za-z0-9]{2,6})\\1+"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = out as NSString
            let matches = regex.matches(in: out, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Process from end to start to maintain indices
            for match in matches.reversed() {
                let fullRange = match.range
                let captureRange = match.range(at: 1) // The token (AB)
                let word = nsString.substring(with: captureRange)
                
                // Only replace if NOT in whitelist
                if !validReduplications.contains(word) {
                    out = (out as NSString).replacingCharacters(in: fullRange, with: word)
                }
            }
        }

        // Punctuation spacing normalization
        out = out.replacingOccurrences(of: "\\s+([，。！？；：,.!?;:])", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "([A-Za-z0-9])([\\p{Han}])", with: "$1 $2", options: .regularExpression)
        out = out.replacingOccurrences(of: "([\\p{Han}])([A-Za-z0-9])", with: "$1 $2", options: .regularExpression)

        // Trim
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }
}
