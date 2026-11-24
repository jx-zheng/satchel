import Foundation

public enum OutputNaming {
    public static func fileName(original: String, suffix: String, newExtension: String? = nil) -> String {
        let parts = stemAndExtension(original)
        let stem = parts.stem
        let ext: String
        if let newExtension {
            ext = newExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        } else {
            ext = parts.ext
        }
        let base = stem + suffix
        if ext.isEmpty { return base }
        return "\(base).\(ext)"
    }

    /// Picks `name`, or `name` with `-2`, `-3`, … inserted before the extension, until it is not in `existing`.
    public static func unique(_ name: String, existing: Set<String>) -> String {
        if !existing.contains(name) { return name }
        let parts = stemAndExtension(name)
        var number = 2
        while number < 100_000 {
            let candidate = parts.ext.isEmpty ? "\(parts.stem)-\(number)" : "\(parts.stem)-\(number).\(parts.ext)"
            if !existing.contains(candidate) { return candidate }
            number += 1
        }
        return name
    }

    public static func stemAndExtension(_ name: String) -> (stem: String, ext: String) {
        if name.hasPrefix("."), name.dropFirst().contains(".") == false {
            return (name, "")
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return (name, "")
        }
        let stem = String(name[..<dot])
        let ext = String(name[name.index(after: dot)...])
        if stem.isEmpty { return (name, "") }
        return (stem, ext)
    }
}

public struct DuplicateFile: Equatable, Sendable {
    public var path: String
    public var size: Int64
    public var hash: String?

    public init(path: String, size: Int64, hash: String? = nil) {
        self.path = path
        self.size = size
        self.hash = hash
    }
}

public enum DuplicateGrouper {
    /// Files that share a non-zero size with at least one other file. Sorted by wasted bytes.
    public static func sizeCandidates(_ files: [DuplicateFile]) -> [[DuplicateFile]] {
        let grouped = Dictionary(grouping: files.filter { $0.size > 0 }, by: \.size)
        return grouped.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.path < $1.path } }
            .sorted { wasted($0) > wasted($1) }
    }

    /// Exact hash groups with more than one file. Files without a hash are ignored.
    public static func hashGroups(_ files: [DuplicateFile]) -> [[DuplicateFile]] {
        let hashed = files.filter { ($0.hash?.isEmpty == false) }
        let grouped = Dictionary(grouping: hashed, by: { $0.hash ?? "" })
        return grouped.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.path < $1.path } }
            .sorted { lhs, rhs in
                let left = wasted(lhs)
                let right = wasted(rhs)
                if left != right { return left > right }
                return (lhs[0].hash ?? "") < (rhs[0].hash ?? "")
            }
    }

    private static func wasted(_ group: [DuplicateFile]) -> Int64 {
        guard let size = group.first?.size else { return 0 }
        return size * Int64(group.count - 1)
    }
}

public struct DownloadEntry: Equatable, Sendable {
    public var name: String
    public var isDirectory: Bool

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

public struct PlannedMove: Equatable, Sendable {
    public var name: String
    public var folder: String

    public init(name: String, folder: String) {
        self.name = name
        self.folder = folder
    }
}

public enum DownloadOrganizer {
    public static let reservedFolders: Set<String> = [
        "Images", "Videos", "Audio", "Documents", "Archives", "Installers", "Applications", "Code", "Other"
    ]

    public static func folder(forFileName name: String) -> String {
        let ext = OutputNaming.stemAndExtension(name).ext.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "svg":
            return "Images"
        case "mp4", "mov", "m4v", "mkv", "avi", "webm":
            return "Videos"
        case "mp3", "m4a", "wav", "aac", "flac", "aiff", "caf":
            return "Audio"
        case "pdf", "doc", "docx", "rtf", "txt", "md", "pages", "key", "ppt", "pptx", "xls", "xlsx", "csv":
            return "Documents"
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2":
            return "Archives"
        case "dmg", "pkg", "iso":
            return "Installers"
        case "app":
            return "Applications"
        case "json", "xml", "html", "css", "js", "ts", "py", "swift", "go", "rs":
            return "Code"
        default:
            return "Other"
        }
    }

    /// Plans moves for loose files. Hidden names and the category folders themselves stay put. Directories are not moved.
    public static func plan(_ entries: [DownloadEntry]) -> [PlannedMove] {
        entries.compactMap { entry in
            if entry.name.hasPrefix(".") { return nil }
            if entry.isDirectory { return nil }
            if reservedFolders.contains(entry.name) { return nil }
            return PlannedMove(name: entry.name, folder: folder(forFileName: entry.name))
        }
    }
}

public enum PageList {
    public enum ParseError: Error, Equatable {
        case empty
        case invalidToken(String)
        case outOfRange(Int)
    }

    /// Parses `1-3, 5` and `all` into 1-based page numbers. Ranges may run backward.
    public static func parse(_ text: String, count: Int) throws -> [Int] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ParseError.empty }
        if trimmed.lowercased() == "all" {
            guard count > 0 else { throw ParseError.empty }
            return Array(1...count)
        }
        var pages: [Int] = []
        let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for part in parts where !part.isEmpty {
            if part.contains("-"), part != "-" {
                let bits = part.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard bits.count == 2, let start = Int(bits[0]), let end = Int(bits[1]) else {
                    throw ParseError.invalidToken(part)
                }
                try check(start, count: count)
                try check(end, count: count)
                if start <= end {
                    pages.append(contentsOf: start...end)
                } else {
                    pages.append(contentsOf: stride(from: start, through: end, by: -1))
                }
            } else {
                guard let number = Int(part) else { throw ParseError.invalidToken(part) }
                try check(number, count: count)
                pages.append(number)
            }
        }
        if pages.isEmpty { throw ParseError.empty }
        return pages
    }

    /// `order` must list every page from 1...count exactly once.
    public static func permutation(_ order: [Int], count: Int) throws -> [Int] {
        if order.count != count {
            throw ParseError.invalidToken("expected \(count) pages")
        }
        var seen = Set<Int>()
        for number in order {
            try check(number, count: count)
            if seen.contains(number) {
                throw ParseError.invalidToken("duplicate \(number)")
            }
            seen.insert(number)
        }
        return order
    }

    private static func check(_ number: Int, count: Int) throws {
        if number < 1 || number > count { throw ParseError.outOfRange(number) }
    }
}
