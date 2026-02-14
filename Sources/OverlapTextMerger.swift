import Foundation

enum OverlapTextMerger {
    private static let overlapIgnoredCharacterSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(.punctuationCharacters)
        set.formUnion(.symbols)
        return set
    }()

    static func mergeOrderedSegments(_ segments: [Int: String], total: Int) -> String {
        guard total > 0 else { return "" }
        var merged = ""
        for idx in 0..<total {
            guard let segment = segments[idx], !segment.isEmpty else { continue }
            if merged.isEmpty {
                merged = segment
            } else {
                merged = merge(base: merged, next: segment)
            }
        }
        return merged
    }

    static func merge(base: String, next: String) -> String {
        let baseText = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextText = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseText.isEmpty, !nextText.isEmpty else { return base + "\n" + next }

        let maxOverlap = min(260, baseText.count, nextText.count)
        guard maxOverlap >= 20 else { return baseText + "\n" + nextText }

        // 1) Prefer exact suffix-prefix match for deterministic merge.
        for size in stride(from: maxOverlap, through: 20, by: -1) {
            let suffix = String(baseText.suffix(size))
            let prefix = String(nextText.prefix(size))
            if suffix == prefix {
                return baseText + String(nextText.dropFirst(size))
            }
        }

        // 2) Relaxed exact match: ignore punctuation / whitespace differences.
        for size in stride(from: maxOverlap, through: 24, by: -2) {
            let suffix = String(baseText.suffix(size))
            let prefix = String(nextText.prefix(size))
            let normalizedSuffix = normalizeForOverlapMatch(suffix)
            if normalizedSuffix.count < 14 { continue }
            if normalizedSuffix == normalizeForOverlapMatch(prefix) {
                return baseText + String(nextText.dropFirst(size))
            }
        }

        // 3) Boundary-tolerant char match for minor ASR jitter near segment edges.
        if let drop = tolerantOverlapDrop(baseText: baseText, nextText: nextText, maxOverlap: maxOverlap) {
            return baseText + String(nextText.dropFirst(drop))
        }

        // 4) Final fallback: high-threshold positional fuzzy match with strict trim cap.
        var bestOverlap = 0
        var bestScore = 0.0
        for size in stride(from: maxOverlap, through: 40, by: -5) {
            let suffix = String(baseText.suffix(size))
            let prefix = String(nextText.prefix(size))
            let score = positionalSimilarity(suffix, prefix)
            if score > bestScore {
                bestScore = score
                bestOverlap = size
            }
        }
        guard bestScore >= 0.92, bestOverlap > 0, bestOverlap <= 80 else {
            return baseText + "\n" + nextText
        }
        return baseText + String(nextText.dropFirst(bestOverlap))
    }

    private static func normalizeForOverlapMatch(_ text: String) -> String {
        let lower = text.lowercased()
        let scalars = lower.unicodeScalars.filter { !overlapIgnoredCharacterSet.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func tolerantOverlapDrop(baseText: String, nextText: String, maxOverlap: Int) -> Int? {
        let nextChars = Array(nextText)
        guard !nextChars.isEmpty else { return nil }

        var bestDrop = 0
        var bestMatched = 0
        for size in stride(from: maxOverlap, through: 20, by: -1) {
            let suffixChars = Array(baseText.suffix(size))
            var i = 0
            var j = 0
            var consumed = 0
            var matchedCore = 0
            var mismatches = 0

            while i < suffixChars.count, j < nextChars.count {
                if isOverlapIgnorable(suffixChars[i]) {
                    i += 1
                    continue
                }
                if isOverlapIgnorable(nextChars[j]) {
                    j += 1
                    consumed += 1
                    continue
                }
                if normalizedOverlapChar(suffixChars[i]) == normalizedOverlapChar(nextChars[j]) {
                    matchedCore += 1
                    i += 1
                    j += 1
                    consumed += 1
                } else {
                    mismatches += 1
                    if mismatches > 2 { break }
                    i += 1
                    j += 1
                    consumed += 1
                }
            }

            while i < suffixChars.count, isOverlapIgnorable(suffixChars[i]) {
                i += 1
            }

            guard i == suffixChars.count else { continue }
            guard matchedCore >= 14, mismatches <= 2 else { continue }
            guard consumed > 0, consumed <= 120 else { continue }

            if matchedCore > bestMatched || (matchedCore == bestMatched && consumed > bestDrop) {
                bestMatched = matchedCore
                bestDrop = consumed
            }
        }

        return bestDrop > 0 ? bestDrop : nil
    }

    private static func isOverlapIgnorable(_ ch: Character) -> Bool {
        for scalar in String(ch).unicodeScalars {
            if !overlapIgnoredCharacterSet.contains(scalar) {
                return false
            }
        }
        return true
    }

    private static func normalizedOverlapChar(_ ch: Character) -> Character {
        let lowered = String(ch).lowercased()
        return lowered.first ?? ch
    }

    private static func positionalSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs)
        let b = Array(rhs)
        guard !a.isEmpty, a.count == b.count else { return 0.0 }
        var same = 0
        for i in 0..<a.count where a[i] == b[i] {
            same += 1
        }
        return Double(same) / Double(a.count)
    }
}
