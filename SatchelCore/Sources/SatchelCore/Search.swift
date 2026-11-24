import Foundation

public enum ToolSearch {
    /// Rank tools for a query. An empty query returns `tools` unchanged (already filtered by category when asked).
    public static func results(
        query: String,
        in tools: [ToolDefinition],
        category: ToolCategory? = nil
    ) -> [ToolDefinition] {
        let pool = category.map { cat in tools.filter { $0.category == cat } } ?? tools
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return pool }
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let scored: [(ToolDefinition, Int)] = pool.compactMap { tool in
            let value = score(tokens: tokens, phrase: normalized, tool: tool)
            return value > 0 ? (tool, value) : nil
        }
        return scored.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            let order = lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.0.id.rawValue < rhs.0.id.rawValue
        }.map(\.0)
    }

    static func score(tokens: [String], phrase: String, tool: ToolDefinition) -> Int {
        if tokens.isEmpty { return 0 }
        if tokens.count == 1 {
            return score(token: tokens[0], tool: tool)
        }
        var total = 0
        for token in tokens {
            let part = score(token: token, tool: tool)
            if part == 0 { return 0 }
            total += part
        }
        let name = tool.name.lowercased()
        if name == phrase { total += 5_000 }
        else if name.contains(phrase) { total += 2_500 }
        return total
    }

    static func score(token: String, tool: ToolDefinition) -> Int {
        let name = tool.name.lowercased()
        let summary = tool.summary.lowercased()
        let keywords = tool.keywords.map { $0.lowercased() }
        if name == token { return 10_000 }
        var best = 0
        if name.hasPrefix(token) {
            best = max(best, 8_000 - name.count)
        }
        let nameWords = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if nameWords.contains(where: { $0.hasPrefix(token) }) {
            best = max(best, 7_200 - name.count)
        }
        if name.contains(token) {
            best = max(best, 6_400 - (name.count / 4))
        }
        if token.count >= 3, let fuzzy = fuzzyScore(token, in: name) {
            best = max(best, min(fuzzy, 3_200))
        }
        for keyword in keywords {
            if keyword == token { best = max(best, 5_600) }
            else if keyword.hasPrefix(token) || keyword.contains(token) { best = max(best, 4_400) }
            else if token.count >= 3, let fuzzy = fuzzyScore(token, in: keyword) {
                best = max(best, min(fuzzy, 2_400))
            }
        }
        if summary.contains(token) { best = max(best, 2_200) }
        let summaryWords = summary.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if summaryWords.contains(where: { $0.hasPrefix(token) }) {
            best = max(best, 2_500)
        }
        return best
    }

    /// Subsequence score. Nil when `query` is not a subsequence of `text`.
    static func fuzzyScore(_ query: String, in text: String) -> Int? {
        guard !query.isEmpty else { return nil }
        var index = text.startIndex
        var streak = 0
        var score = 280
        var first = true
        for character in query {
            guard let found = text[index...].firstIndex(of: character) else { return nil }
            let gap = text.distance(from: index, to: found)
            if first && gap == 0 { score += 80 }
            first = false
            if gap == 0 {
                streak += 1
                score += 36 + streak * 10
            } else {
                streak = 0
                score += max(0, 14 - gap)
            }
            index = text.index(after: found)
        }
        score -= max(0, text.count - query.count)
        return score
    }
}
