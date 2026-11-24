import Foundation

public enum TextCase: String, CaseIterable, Codable, Sendable, Identifiable {
    case upper
    case lower
    case title
    case sentence
    case camel
    case pascal
    case snake
    case kebab

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .upper: return "UPPER CASE"
        case .lower: return "lower case"
        case .title: return "Title Case"
        case .sentence: return "Sentence case"
        case .camel: return "camelCase"
        case .pascal: return "PascalCase"
        case .snake: return "snake_case"
        case .kebab: return "kebab-case"
        }
    }
}

public struct WordCount: Equatable, Sendable {
    public var characters: Int
    public var charactersNoSpaces: Int
    public var words: Int
    public var sentences: Int
    public var paragraphs: Int
    public var lines: Int
    public var readingMinutes: Int

    public init(
        characters: Int,
        charactersNoSpaces: Int,
        words: Int,
        sentences: Int,
        paragraphs: Int,
        lines: Int,
        readingMinutes: Int
    ) {
        self.characters = characters
        self.charactersNoSpaces = charactersNoSpaces
        self.words = words
        self.sentences = sentences
        self.paragraphs = paragraphs
        self.lines = lines
        self.readingMinutes = readingMinutes
    }
}

public enum TextTransforms {
    public static func count(_ text: String) -> WordCount {
        let characters = text.count
        let charactersNoSpaces = text.filter { !$0.isWhitespace }.count
        let words = text.split { $0.isWhitespace }.count
        let sentences = sentenceCount(text)
        let paragraphs = paragraphCount(text)
        let lines = lineCount(text)
        let reading = words == 0 ? 0 : max(1, Int((Double(words) / 200.0).rounded(.up)))
        return WordCount(
            characters: characters,
            charactersNoSpaces: charactersNoSpaces,
            words: words,
            sentences: sentences,
            paragraphs: paragraphs,
            lines: lines,
            readingMinutes: reading
        )
    }

    public static func apply(_ text: String, _ style: TextCase) -> String {
        switch style {
        case .upper:
            return text.uppercased()
        case .lower:
            return text.lowercased()
        case .title:
            let parts = words(in: text)
            return parts.map { capitalize($0) }.joined(separator: " ")
        case .sentence:
            let parts = words(in: text)
            guard let first = parts.first else { return "" }
            let rest = parts.dropFirst().map { $0.lowercased() }
            return ([capitalize(first)] + rest).joined(separator: " ")
        case .camel:
            let parts = words(in: text)
            guard let first = parts.first else { return "" }
            return first.lowercased() + parts.dropFirst().map { capitalize($0) }.joined()
        case .pascal:
            return words(in: text).map { capitalize($0) }.joined()
        case .snake:
            return words(in: text).map { $0.lowercased() }.joined(separator: "_")
        case .kebab:
            return words(in: text).map { $0.lowercased() }.joined(separator: "-")
        }
    }

    static func words(in text: String) -> [String] {
        let chars = Array(text)
        var broken = ""
        for index in chars.indices {
            let character = chars[index]
            if index > 0 {
                let previous = chars[index - 1]
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                let lowerToUpper = (previous.isLowercase || previous.isNumber) && character.isUppercase
                let acronymEdge = previous.isUppercase && character.isUppercase && next?.isLowercase == true
                if lowerToUpper || acronymEdge {
                    broken.append(" ")
                }
            }
            broken.append(character)
        }
        return broken.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func capitalize(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst().lowercased()
    }

    private static func sentenceCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        var count = 0
        var inSentence = false
        for character in trimmed {
            if ".!?".contains(character) {
                if inSentence { count += 1 }
                inSentence = false
            } else if !character.isWhitespace {
                inSentence = true
            }
        }
        if inSentence { count += 1 }
        return count
    }

    private static func paragraphCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let parts = trimmed.components(separatedBy: "\n\n")
        return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private static func lineCount(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines.count
    }
}
