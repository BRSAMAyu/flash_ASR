import Foundation

enum TextPostProcessor {
    static func clean(_ text: String) -> String {
        var out = text

        // Collapse repeated spaces
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Remove common filler words (Chinese) when standalone-ish
        let fillerPatterns = ["(^|\\s)(嗯+|呃+|那个|就是)(\\s|$)"]
        for p in fillerPatterns {
            out = out.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }

        // De-duplicate immediately repeated short tokens, e.g. "好的好的" -> "好的"
        out = out.replacingOccurrences(of: "([\\p{Han}A-Za-z0-9]{3,6})\\1+", with: "$1", options: .regularExpression)

        // Punctuation spacing normalization
        out = out.replacingOccurrences(of: "\\s+([，。！？；：,.!?;:])", with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "([A-Za-z0-9])([\\p{Han}])", with: "$1 $2", options: .regularExpression)
        out = out.replacingOccurrences(of: "([\\p{Han}])([A-Za-z0-9])", with: "$1 $2", options: .regularExpression)

        // Trim
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }
}
