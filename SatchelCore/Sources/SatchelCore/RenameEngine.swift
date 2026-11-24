import Foundation

public enum NumberPosition: String, Equatable, Codable, Sendable {
    case replace
    case prefix
    case suffix
}

public enum RenameOperation: Equatable, Sendable {
    case findReplace(find: String, replace: String, useRegex: Bool, caseInsensitive: Bool)
    case prefix(String)
    case suffix(String)
    case number(start: Int, padding: Int, position: NumberPosition)
    case changeCase(TextCase)
    case dateStamp(format: String, useFileDate: Bool)
    case newExtension(String)
}

public struct RenameItem: Equatable, Sendable {
    public var name: String
    public var modified: Date?

    public init(name: String, modified: Date? = nil) {
        self.name = name
        self.modified = modified
    }
}

public struct RenamePreviewRow: Equatable, Sendable {
    public var original: String
    public var proposed: String
    public var issue: String?

    public init(original: String, proposed: String, issue: String?) {
        self.original = original
        self.proposed = proposed
        self.issue = issue
    }
}

public enum RenameEngine {
    public static func preview(
        items: [RenameItem],
        operations: [RenameOperation],
        now: Date = Date(),
        timeZone: TimeZone = TimeZone(identifier: "UTC") ?? .current
    ) -> [RenamePreviewRow] {
        var rows: [RenamePreviewRow] = []
        rows.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            let proposed = apply(item: item, index: index, operations: operations, now: now, timeZone: timeZone)
            rows.append(RenamePreviewRow(original: item.name, proposed: proposed.name, issue: proposed.issue))
        }
        var seen: [String: Int] = [:]
        for (index, row) in rows.enumerated() where row.issue == nil {
            let key = row.proposed.lowercased()
            if let first = seen[key] {
                rows[index].issue = "Name collides with another file in this batch"
                if rows[first].issue == nil {
                    rows[first].issue = "Name collides with another file in this batch"
                }
            } else {
                seen[key] = index
            }
        }
        return rows
    }

    private static func apply(
        item: RenameItem,
        index: Int,
        operations: [RenameOperation],
        now: Date,
        timeZone: TimeZone
    ) -> (name: String, issue: String?) {
        var parts = OutputNaming.stemAndExtension(item.name)
        for operation in operations {
            switch operation {
            case let .findReplace(find, replace, useRegex, caseInsensitive):
                let full = join(parts)
                let replaced: String
                if useRegex {
                    do {
                        replaced = try regexReplace(full, find: find, replace: replace, caseInsensitive: caseInsensitive)
                    } catch {
                        return (full, "Invalid pattern")
                    }
                } else if find.isEmpty {
                    replaced = full
                } else if caseInsensitive {
                    replaced = replaceInsensitive(full, find: find, replace: replace)
                } else {
                    replaced = full.replacingOccurrences(of: find, with: replace)
                }
                parts = OutputNaming.stemAndExtension(replaced)
            case let .prefix(value):
                parts.stem = value + parts.stem
            case let .suffix(value):
                parts.stem += value
            case let .number(start, padding, position):
                let raw = String(start + index)
                let width = max(1, padding)
                let token = raw.count >= width ? raw : String(repeating: "0", count: width - raw.count) + raw
                switch position {
                case .replace:
                    parts.stem = token
                case .prefix:
                    parts.stem = parts.stem.isEmpty ? token : token + "-" + parts.stem
                case .suffix:
                    parts.stem = parts.stem.isEmpty ? token : parts.stem + "-" + token
                }
            case let .changeCase(style):
                parts.stem = TextTransforms.apply(parts.stem, style)
            case let .dateStamp(format, useFileDate):
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = format.isEmpty ? "yyyy-MM-dd" : format
                let stamp = formatter.string(from: useFileDate ? (item.modified ?? now) : now)
                parts.stem += stamp
            case let .newExtension(ext):
                parts.ext = ext.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            }
        }
        let name = join(parts)
        if name.isEmpty || name == "." || name == ".." || name.contains("/") || name.contains("\0") {
            return (name, "That name is not allowed")
        }
        return (name, nil)
    }

    private static func join(_ parts: (stem: String, ext: String)) -> String {
        if parts.ext.isEmpty { return parts.stem }
        return "\(parts.stem).\(parts.ext)"
    }

    private static func regexReplace(_ text: String, find: String, replace: String, caseInsensitive: Bool) throws -> String {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        let expression = try NSRegularExpression(pattern: find, options: options)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replace)
    }

    private static func replaceInsensitive(_ text: String, find: String, replace: String) -> String {
        var result = ""
        var index = text.startIndex
        let needle = find.lowercased()
        while index < text.endIndex {
            let rest = text[index...]
            if let found = rest.range(of: needle, options: [.caseInsensitive]) {
                result += text[index..<found.lowerBound]
                result += replace
                index = found.upperBound
            } else {
                result += rest
                break
            }
        }
        return result
    }
}
