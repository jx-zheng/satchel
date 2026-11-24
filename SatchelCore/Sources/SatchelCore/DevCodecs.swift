import Foundation

public enum Digests {
    public static func sha256Hex(_ data: Data) -> String { hex(sha256(data)) }
    public static func sha1Hex(_ data: Data) -> String { hex(sha1(data)) }

    public static func sha256Hex(_ text: String) -> String {
        sha256Hex(Data(text.utf8))
    }

    public static func sha1Hex(_ text: String) -> String {
        sha1Hex(Data(text.utf8))
    }

    public static func sha256(_ data: Data) -> [UInt8] {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var offset = 0
        while offset < message.count {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = offset + i * 4
                w[i] = (UInt32(message[j]) << 24) | (UInt32(message[j + 1]) << 16) | (UInt32(message[j + 2]) << 8) | UInt32(message[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ ((~e) & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g
                g = f
                f = e
                e = d &+ t1
                d = c
                c = b
                b = a
                a = t1 &+ t2
            }
            h[0] = h[0] &+ a
            h[1] = h[1] &+ b
            h[2] = h[2] &+ c
            h[3] = h[3] &+ d
            h[4] = h[4] &+ e
            h[5] = h[5] &+ f
            h[6] = h[6] &+ g
            h[7] = h[7] &+ hh
            offset += 64
        }
        var out: [UInt8] = []
        out.reserveCapacity(32)
        for value in h {
            out.append(UInt8((value >> 24) & 0xff))
            out.append(UInt8((value >> 16) & 0xff))
            out.append(UInt8((value >> 8) & 0xff))
            out.append(UInt8(value & 0xff))
        }
        return out
    }

    public static func sha1(_ data: Data) -> [UInt8] {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0
        func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
        var offset = 0
        while offset < message.count {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let j = offset + i * 4
                w[i] = (UInt32(message[j]) << 24) | (UInt32(message[j + 1]) << 16) | (UInt32(message[j + 2]) << 8) | UInt32(message[j + 3])
            }
            for i in 16..<80 {
                w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = rotl(a, 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = rotl(b, 30)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
            offset += 64
        }
        var out: [UInt8] = []
        for value in [h0, h1, h2, h3, h4] {
            out.append(UInt8((value >> 24) & 0xff))
            out.append(UInt8((value >> 16) & 0xff))
            out.append(UInt8((value >> 8) & 0xff))
            out.append(UInt8(value & 0xff))
        }
        return out
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public enum Base64Codec {
    public enum CodecError: Error, Equatable { case invalid }

    public static func encode(_ text: String, urlSafe: Bool) -> String {
        encode(Data(text.utf8), urlSafe: urlSafe)
    }

    public static func encode(_ data: Data, urlSafe: Bool) -> String {
        var encoded = data.base64EncodedString()
        if urlSafe {
            encoded = encoded.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            while encoded.hasSuffix("=") { encoded.removeLast() }
        }
        return encoded
    }

    public static func decode(_ text: String, urlSafe: Bool) throws -> String {
        let data = try decodeData(text, urlSafe: urlSafe)
        guard let string = String(data: data, encoding: .utf8) else { throw CodecError.invalid }
        return string
    }

    public static func decodeData(_ text: String, urlSafe: Bool) throws -> Data {
        var padded = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if urlSafe {
            padded = padded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        }
        let remainder = padded.count % 4
        if remainder > 0 { padded += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: padded) else { throw CodecError.invalid }
        return data
    }
}

public struct JWTParts: Equatable, Sendable {
    public var headerJSON: String
    public var payloadJSON: String

    public init(headerJSON: String, payloadJSON: String) {
        self.headerJSON = headerJSON
        self.payloadJSON = payloadJSON
    }
}

public enum JWTDecoder {
    public enum DecodeError: Error, Equatable { case malformed, invalidJSON }

    /// Decodes header and payload. Does not check the signature.
    public static func decode(_ token: String) throws -> JWTParts {
        let pieces = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").map(String.init)
        guard pieces.count == 3 || pieces.count == 2 else { throw DecodeError.malformed }
        let header = try jsonObjectString(pieces[0])
        let payload = try jsonObjectString(pieces[1])
        return JWTParts(headerJSON: header, payloadJSON: payload)
    }

    private static func jsonObjectString(_ segment: String) throws -> String {
        let data: Data
        do { data = try Base64Codec.decodeData(segment, urlSafe: true) } catch { throw DecodeError.malformed }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.invalidJSON
        }
        return try JSONFormat.pretty(object)
    }
}

public enum JSONFormat {
    public enum FormatError: Error, Equatable { case invalid }

    public static func pretty(_ text: String) throws -> String {
        let object = try parse(text)
        return try pretty(object)
    }

    public static func minify(_ text: String) throws -> String {
        let object = try parse(text)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else { throw FormatError.invalid }
        return string
    }

    static func pretty(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else { throw FormatError.invalid }
        return string
    }

    private static func parse(_ text: String) throws -> Any {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            throw FormatError.invalid
        }
        return object
    }
}

public enum TabularConvert {
    public enum ConvertError: Error, Equatable { case invalid, empty }

    public static func csvToJSON(_ csv: String) throws -> String {
        let rows = try parseCSV(csv)
        guard let header = rows.first, !header.isEmpty else { throw ConvertError.empty }
        let body = rows.dropFirst()
        let objects: [[String: String]] = body.map { row in
            var object: [String: String] = [:]
            for (index, key) in header.enumerated() where !key.isEmpty {
                object[key] = index < row.count ? row[index] : ""
            }
            return object
        }
        let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else { throw ConvertError.invalid }
        return string
    }

    public static func jsonToCSV(_ json: String) throws -> String {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ConvertError.invalid
        }
        if array.isEmpty { throw ConvertError.empty }
        var headers: [String] = []
        for object in array {
            for key in object.keys where !headers.contains(key) {
                headers.append(key)
            }
        }
        headers.sort()
        var lines = [escapeRow(headers)]
        for object in array {
            let cells = headers.map { key -> String in
                cellString(object[key])
            }
            lines.append(escapeRow(cells))
        }
        return lines.joined(separator: "\n")
    }

    static func parseCSV(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.append(character)
                index += 1
                continue
            }
            if character == "\"" && field.isEmpty {
                inQuotes = true
                index += 1
                continue
            }
            if character == "," {
                row.append(field)
                field = ""
                index += 1
                continue
            }
            if character == "\n" || character == "\r" {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) {
                    rows.append(row)
                }
                row = []
                index += 1
                continue
            }
            field.append(character)
            index += 1
        }
        if inQuotes { throw ConvertError.invalid }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func cellString(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull:
            return ""
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        default:
            if let data = try? JSONSerialization.data(withJSONObject: value as Any, options: [.sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return ""
        }
    }

    private static func escapeRow(_ cells: [String]) -> String {
        cells.map { cell in
            if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
                return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return cell
        }.joined(separator: ",")
    }
}

public enum TimeUnit: String, Equatable, Codable, Sendable {
    case seconds
    case milliseconds
}

public enum TimestampCodec {
    public static func date(unix: Double, unit: TimeUnit) -> Date {
        let seconds = unit == .milliseconds ? unix / 1000 : unix
        return Date(timeIntervalSince1970: seconds)
    }

    public static func unix(from date: Date, unit: TimeUnit) -> Double {
        let seconds = date.timeIntervalSince1970
        return unit == .milliseconds ? seconds * 1000 : seconds
    }

    public static func iso8601(_ date: Date, timeZone: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func parseISO(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

public struct SplitMix64: RandomNumberGenerator {
    public var state: UInt64
    public init(seed: UInt64) { self.state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public enum UUIDFactory {
    public static func make(uppercase: Bool = false, using rng: inout some RandomNumberGenerator) -> String {
        var bytes = (0..<16).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [
            hex.prefix(8),
            hex.dropFirst(8).prefix(4),
            hex.dropFirst(12).prefix(4),
            hex.dropFirst(16).prefix(4),
            hex.dropFirst(20)
        ].map(String.init)
        let value = parts.joined(separator: "-")
        return uppercase ? value.uppercased() : value
    }

    public static func isVersion4(_ uuid: String) -> Bool {
        let trimmed = uuid.trimmingCharacters(in: .whitespaces)
        let pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

public struct PasswordOptions: Equatable, Sendable {
    public var length: Int
    public var upper: Bool
    public var lower: Bool
    public var digits: Bool
    public var symbols: Bool
    public var avoidAmbiguous: Bool

    public init(length: Int, upper: Bool, lower: Bool, digits: Bool, symbols: Bool, avoidAmbiguous: Bool) {
        self.length = length
        self.upper = upper
        self.lower = lower
        self.digits = digits
        self.symbols = symbols
        self.avoidAmbiguous = avoidAmbiguous
    }

    public static let `default` = PasswordOptions(length: 20, upper: true, lower: true, digits: true, symbols: true, avoidAmbiguous: true)
}

public enum PasswordGenerator {
    public enum GenerateError: Error, Equatable { case noSets, tooShort }

    private static let ambiguous: Set<Character> = ["0", "O", "o", "1", "l", "I", "|"]

    public static func generate(_ options: PasswordOptions, using rng: inout some RandomNumberGenerator) throws -> String {
        var pools: [[Character]] = []
        if options.upper { pools.append(filter("ABCDEFGHIJKLMNOPQRSTUVWXYZ", options)) }
        if options.lower { pools.append(filter("abcdefghijklmnopqrstuvwxyz", options)) }
        if options.digits { pools.append(filter("0123456789", options)) }
        if options.symbols { pools.append(filter("!@#$%^&*_-+=?", options)) }
        pools = pools.filter { !$0.isEmpty }
        if pools.isEmpty { throw GenerateError.noSets }
        let length = max(0, options.length)
        if length < pools.count { throw GenerateError.tooShort }
        var characters: [Character] = []
        for pool in pools {
            characters.append(pool[Int(rng.next() % UInt64(pool.count))])
        }
        let all = pools.flatMap { $0 }
        while characters.count < length {
            characters.append(all[Int(rng.next() % UInt64(all.count))])
        }
        for i in stride(from: characters.count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            characters.swapAt(i, j)
        }
        return String(characters)
    }

    private static func filter(_ source: String, _ options: PasswordOptions) -> [Character] {
        source.filter { options.avoidAmbiguous ? !ambiguous.contains($0) : true }
    }
}

public enum LoremIpsum {
    public static let words = [
        "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do",
        "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "enim",
        "ad", "minim", "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi", "aliquip",
        "ex", "ea", "commodo", "consequat", "duis", "aute", "irure", "in", "reprehenderit", "voluptate",
        "velit", "esse", "cillum", "eu", "fugiat", "nulla", "pariatur", "excepteur", "sint", "occaecat",
        "cupidatat", "non", "proident", "sunt", "culpa", "qui", "officia", "deserunt", "mollit", "anim",
        "id", "est", "laborum"
    ]

    public static func generate(paragraphs: Int, sentences: Int, wordsPerSentence: Int) -> String {
        let paragraphCount = max(0, paragraphs)
        let sentenceCount = max(1, sentences)
        let wordCount = max(1, wordsPerSentence)
        var cursor = 0
        var blocks: [String] = []
        for _ in 0..<paragraphCount {
            var lines: [String] = []
            for _ in 0..<sentenceCount {
                var piece: [String] = []
                for index in 0..<wordCount {
                    var word = words[cursor % words.count]
                    cursor += 1
                    if index == 0 { word = word.prefix(1).uppercased() + word.dropFirst() }
                    piece.append(word)
                }
                lines.append(piece.joined(separator: " ") + ".")
            }
            blocks.append(lines.joined(separator: " "))
        }
        return blocks.joined(separator: "\n\n")
    }

    public static func wordList(count: Int) -> String {
        guard count > 0 else { return "" }
        return (0..<count).map { words[$0 % words.count] }.joined(separator: " ")
    }
}

public struct UnicodeScalarInfo: Equatable, Sendable {
    public var character: String
    public var hex: String
    public var utf8Hex: String
    public var name: String
    public var category: String

    public init(character: String, hex: String, utf8Hex: String, name: String, category: String) {
        self.character = character
        self.hex = hex
        self.utf8Hex = utf8Hex
        self.name = name
        self.category = category
    }
}

public enum UnicodeInspector {
    public static func inspect(_ text: String) -> [UnicodeScalarInfo] {
        text.unicodeScalars.map { scalar in
            let hex = String(format: "U+%04X", scalar.value)
            let utf8 = Array(String(scalar).utf8).map { String(format: "%02X", $0) }.joined(separator: " ")
            let name = scalar.properties.name ?? scalar.properties.nameAlias ?? "Unnamed"
            return UnicodeScalarInfo(
                character: String(scalar),
                hex: hex,
                utf8Hex: utf8,
                name: name,
                category: categoryName(scalar.properties.generalCategory)
            )
        }
    }

    private static func categoryName(_ category: Unicode.GeneralCategory) -> String {
        switch category {
        case .uppercaseLetter: return "Uppercase letter"
        case .lowercaseLetter: return "Lowercase letter"
        case .titlecaseLetter: return "Titlecase letter"
        case .modifierLetter: return "Modifier letter"
        case .otherLetter: return "Other letter"
        case .decimalNumber: return "Decimal number"
        case .letterNumber: return "Letter number"
        case .otherNumber: return "Other number"
        case .spaceSeparator: return "Space"
        case .lineSeparator: return "Line separator"
        case .paragraphSeparator: return "Paragraph separator"
        case .dashPunctuation: return "Dash"
        case .openPunctuation: return "Open punctuation"
        case .closePunctuation: return "Close punctuation"
        case .connectorPunctuation: return "Connector"
        case .otherPunctuation: return "Punctuation"
        case .mathSymbol: return "Math symbol"
        case .currencySymbol: return "Currency"
        case .modifierSymbol: return "Modifier symbol"
        case .otherSymbol: return "Symbol"
        default: return "Other"
        }
    }
}

public struct RegexHit: Equatable, Sendable {
    public var full: String
    public var groups: [String]

    public init(full: String, groups: [String]) {
        self.full = full
        self.groups = groups
    }
}

public enum RegexTester {
    public enum PatternError: Error, Equatable { case invalid(String) }

    public static func matches(pattern: String, text: String, caseInsensitive: Bool, multiline: Bool) throws -> [RegexHit] {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        if multiline { options.insert(.anchorsMatchLines) }
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw PatternError.invalid(String(describing: error))
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, options: [], range: range).map { match in
            let full = substring(text, match.range(at: 0))
            var groups: [String] = []
            if match.numberOfRanges > 1 {
                for index in 1..<match.numberOfRanges {
                    groups.append(substring(text, match.range(at: index)))
                }
            }
            return RegexHit(full: full, groups: groups)
        }
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard range.location != NSNotFound, let swift = Range(range, in: text) else { return "" }
        return String(text[swift])
    }
}

public enum LineDiff {
    public enum Row: Equatable, Sendable {
        case same(String)
        case added(String)
        case removed(String)
    }

    public static func diff(_ before: String, _ after: String) -> [Row] {
        let left = lines(before)
        let right = lines(after)
        if left.count * right.count > 640_000 {
            return coarse(left, right)
        }
        let n = left.count
        let m = right.count
        var dp = [Int](repeating: 0, count: (n + 1) * (m + 1))
        func at(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    if left[i] == right[j] {
                        dp[at(i, j)] = dp[at(i + 1, j + 1)] + 1
                    } else {
                        dp[at(i, j)] = max(dp[at(i + 1, j)], dp[at(i, j + 1)])
                    }
                }
            }
        }
        var rows: [Row] = []
        var i = 0
        var j = 0
        while i < n && j < m {
            if left[i] == right[j] {
                rows.append(.same(left[i]))
                i += 1
                j += 1
            } else if dp[at(i + 1, j)] >= dp[at(i, j + 1)] {
                rows.append(.removed(left[i]))
                i += 1
            } else {
                rows.append(.added(right[j]))
                j += 1
            }
        }
        while i < n {
            rows.append(.removed(left[i]))
            i += 1
        }
        while j < m {
            rows.append(.added(right[j]))
            j += 1
        }
        return rows
    }

    private static func lines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var parts = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { parts.removeLast() }
        return parts
    }

    private static func coarse(_ left: [String], _ right: [String]) -> [Row] {
        var prefix = 0
        while prefix < left.count && prefix < right.count && left[prefix] == right[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < left.count - prefix && suffix < right.count - prefix && left[left.count - 1 - suffix] == right[right.count - 1 - suffix] {
            suffix += 1
        }
        var rows: [Row] = left.prefix(prefix).map { .same($0) }
        rows.append(contentsOf: left[prefix..<(left.count - suffix)].map { .removed($0) })
        rows.append(contentsOf: right[prefix..<(right.count - suffix)].map { .added($0) })
        rows.append(contentsOf: left.suffix(suffix).map { .same($0) })
        return rows
    }
}

public enum LinkCleaner {
    public static let trackingNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid",
        "mc_cid", "mc_eid", "igshid", "igsh", "yclid", "_ga", "_gl",
        "_hsenc", "_hsmi", "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id",
        "twclid", "ttclid", "li_fat_id", "si", "spm", "fb_action_ids",
        "fb_action_types", "fb_source", "ncid"
    ]

    public static func clean(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme != nil || trimmed.contains("://") || components.host != nil else {
            return trimmed
        }
        if components.scheme == nil, components.host == nil {
            return trimmed
        }
        let items = components.queryItems ?? []
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if name.hasPrefix("utm_") { return false }
            return !trackingNames.contains(name)
        }
        components.queryItems = kept.isEmpty ? nil : kept
        let value = components.string ?? trimmed
        if value.hasSuffix("?") { return String(value.dropLast()) }
        return value
    }
}

public struct CoordinateFormats: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var decimal: String
    public var dms: String
    public var geohash: String

    public init(latitude: Double, longitude: Double, decimal: String, dms: String, geohash: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.decimal = decimal
        self.dms = dms
        self.geohash = geohash
    }
}

public enum Coordinates {
    public enum ParseError: Error, Equatable { case invalid }

    public static func formats(latitude: Double, longitude: Double, geohashPrecision: Int = 9) -> CoordinateFormats {
        let lat = min(90, max(-90, latitude))
        let lon = min(180, max(-180, longitude))
        let decimal = String(format: "%.6f, %.6f", lat, lon)
        let dms = "\(dms(lat, positive: "N", negative: "S")) \(dms(lon, positive: "E", negative: "W"))"
        let hash = Geohash.encode(latitude: lat, longitude: lon, precision: max(1, min(12, geohashPrecision)))
        return CoordinateFormats(latitude: lat, longitude: lon, decimal: decimal, dms: dms, geohash: hash)
    }

    /// Accepts `37.77, -122.42` or a single geohash.
    public static func parse(_ text: String) throws -> (latitude: Double, longitude: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains(",") && !trimmed.contains(" "), Geohash.decodes(trimmed) {
            return Geohash.decode(trimmed)
        }
        let parts = trimmed.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else {
            throw ParseError.invalid
        }
        return (lat, lon)
    }

    private static func dms(_ value: Double, positive: String, negative: String) -> String {
        let hemisphere = value >= 0 ? positive : negative
        let absolute = abs(value)
        let degrees = Int(absolute)
        let minutesFull = (absolute - Double(degrees)) * 60
        let minutes = Int(minutesFull)
        let seconds = (minutesFull - Double(minutes)) * 60
        return String(format: "%d°%d'%0.2f\"%@", degrees, minutes, seconds, hemisphere)
    }
}

public enum Geohash {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    private static let map: [Character: Int] = {
        var result: [Character: Int] = [:]
        for (index, character) in alphabet.enumerated() { result[character] = index }
        return result
    }()

    public static func encode(latitude: Double, longitude: Double, precision: Int = 9) -> String {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bit = 0
        var value = 0
        var even = true
        let length = max(1, precision)
        while hash.count < length {
            if even {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    value |= 1 << (4 - bit)
                    lonRange.0 = mid
                } else {
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    value |= 1 << (4 - bit)
                    latRange.0 = mid
                } else {
                    latRange.1 = mid
                }
            }
            even.toggle()
            if bit < 4 {
                bit += 1
            } else {
                hash.append(alphabet[value])
                bit = 0
                value = 0
            }
        }
        return hash
    }

    public static func decodes(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return !lowered.isEmpty && lowered.allSatisfy { map[$0] != nil }
    }

    public static func decode(_ text: String) -> (latitude: Double, longitude: Double) {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var even = true
        for character in text.lowercased() {
            guard let digit = map[character] else { continue }
            for mask in [16, 8, 4, 2, 1] {
                if even {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if digit & mask != 0 { lonRange.0 = mid } else { lonRange.1 = mid }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if digit & mask != 0 { latRange.0 = mid } else { latRange.1 = mid }
                }
                even.toggle()
            }
        }
        return ((latRange.0 + latRange.1) / 2, (lonRange.0 + lonRange.1) / 2)
    }
}
