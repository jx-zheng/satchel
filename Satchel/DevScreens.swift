import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SatchelCore

struct DevToolScreen: View {
    let id: ToolID
    var body: some View {
        switch id {
        case .jsonFormatter: JSONTool()
        case .base64: Base64Tool()
        case .hashGenerator: HashTool()
        case .uuidGenerator: UUIDTool()
        case .jwtDecoder: JWTTool()
        case .timestamp: TimestampTool()
        case .diffChecker: DiffTool()
        case .regexTester: RegexTool()
        case .cleanLinks: LinksTool()
        case .coordinatePicker: CoordinateTool()
        case .unicodeInspector: UnicodeTool()
        case .loremIpsum: LoremTool()
        case .passwordGenerator: PasswordTool()
        case .csvJSON: CSVTool()
        default:
            if let tool = ToolRegistry.byID[id] { ComingSoonView(tool: tool) }
        }
    }
}

private struct DevBox<Content: View>: View {
    let tool: ToolID
    @ViewBuilder var content: () -> Content
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(tool)) { content() }
    }
}

private struct JSONTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var output = ""
    @State private var errorText = ""
    var body: some View {
        DevBox(tool: .jsonFormatter) {
            editor(.jsonFormatter)
            HStack {
                PrimaryButton(title: "Pretty", enabled: true) { run(pretty: true) }
                PrimaryButton(title: "Minify", enabled: true) { run(pretty: false) }
            }
            result
        }
    }

    private func run(pretty: Bool) {
        do {
            output = try pretty ? JSONFormat.pretty(model.draft(for: .jsonFormatter)) : JSONFormat.minify(model.draft(for: .jsonFormatter))
            errorText = ""
            SatchelLog.toolRun(id: ToolID.jsonFormatter.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
        } catch {
            errorText = "That text is not valid JSON."
            SatchelLog.toolRun(id: ToolID.jsonFormatter.rawValue, inputs: 1, outcome: "failed", seconds: "0s")
        }
    }

    @ViewBuilder private var result: some View { ResultBlock(text: output, error: errorText) }
}

private struct Base64Tool: View {
    @EnvironmentObject private var model: AppModel
    @State private var urlSafe = false
    @State private var output = ""
    @State private var errorText = ""
    var body: some View {
        DevBox(tool: .base64) {
            Toggle("URL-safe", isOn: $urlSafe)
            editor(.base64)
            HStack {
                PrimaryButton(title: "Encode", enabled: true) {
                    output = Base64Codec.encode(model.draft(for: .base64), urlSafe: urlSafe)
                    errorText = ""
                    log(.base64, true)
                }
                PrimaryButton(title: "Decode", enabled: true) {
                    do {
                        output = try Base64Codec.decode(model.draft(for: .base64), urlSafe: urlSafe)
                        errorText = ""
                        log(.base64, true)
                    } catch {
                        errorText = "That is not valid Base64."
                        log(.base64, false)
                    }
                }
            }
            ResultBlock(text: output, error: errorText)
        }
    }
}

private struct HashTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var output = ""
    var body: some View {
        DevBox(tool: .hashGenerator) {
            editor(.hashGenerator)
            PrimaryButton(title: "Hash text", enabled: true) {
                let text = model.draft(for: .hashGenerator)
                output = "SHA-256  \(Digests.sha256Hex(text))\nSHA-1    \(Digests.sha1Hex(text))"
                log(.hashGenerator, true)
            }
            DropZone(prompt: "Or drop a file", types: [.item], multiple: false) { urls in
                guard let url = urls.first, let data = try? Data(contentsOf: url) else { return }
                output = "\(url.lastPathComponent)\nSHA-256  \(Digests.sha256Hex(data))\nSHA-1    \(Digests.sha1Hex(data))"
                log(.hashGenerator, true)
            }
            ResultBlock(text: output, error: "")
        }
    }
}

private struct UUIDTool: View {
    @State private var count = 4
    @State private var upper = false
    @State private var output = ""
    var body: some View {
        DevBox(tool: .uuidGenerator) {
            Stepper("Count: \(count)", value: $count, in: 1...50)
            Toggle("Uppercase", isOn: $upper)
            PrimaryButton(title: "Generate", enabled: true) {
                var rng = SystemRandomNumberGenerator()
                output = (0..<count).map { _ in UUIDFactory.make(uppercase: upper, using: &rng) }.joined(separator: "\n")
                log(.uuidGenerator, true)
            }
            ResultBlock(text: output, error: "")
        }
    }
}

private struct JWTTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var output = ""
    @State private var errorText = ""
    var body: some View {
        DevBox(tool: .jwtDecoder) {
            editor(.jwtDecoder)
            PrimaryButton(title: "Decode", enabled: true) {
                do {
                    let parts = try JWTDecoder.decode(model.draft(for: .jwtDecoder))
                    output = "Header\n\(parts.headerJSON)\n\nPayload\n\(parts.payloadJSON)\n\nThe signature was not checked."
                    errorText = ""
                    log(.jwtDecoder, true)
                } catch {
                    errorText = "That does not look like a JWT."
                    log(.jwtDecoder, false)
                }
            }
            ResultBlock(text: output, error: errorText)
        }
    }
}

private struct TimestampTool: View {
    @State private var unix = ""
    @State private var unit = TimeUnit.seconds
    @State private var output = ""
    var body: some View {
        DevBox(tool: .timestamp) {
            TextField("Unix time", text: $unix)
            Picker("Unit", selection: $unit) {
                Text("Seconds").tag(TimeUnit.seconds)
                Text("Milliseconds").tag(TimeUnit.milliseconds)
            }
            .pickerStyle(.segmented)
            HStack {
                PrimaryButton(title: "To date", enabled: true) {
                    guard let value = Double(unix) else { output = "Enter a number."; return }
                    let date = TimestampCodec.date(unix: value, unit: unit)
                    output = TimestampCodec.iso8601(date)
                    log(.timestamp, true)
                }
                PrimaryButton(title: "Now", enabled: true) {
                    let date = Date()
                    unix = String(format: "%.0f", TimestampCodec.unix(from: date, unit: unit))
                    output = TimestampCodec.iso8601(date)
                    log(.timestamp, true)
                }
            }
            ResultBlock(text: output, error: "")
        }
    }
}

private struct DiffTool: View {
    @State private var left = ""
    @State private var right = ""
    @State private var output = ""
    var body: some View {
        DevBox(tool: .diffChecker) {
            TextEditor(text: $left).frame(minHeight: 100)
            TextEditor(text: $right).frame(minHeight: 100)
            PrimaryButton(title: "Compare", enabled: true) {
                output = LineDiff.diff(left, right).map { row in
                    switch row {
                    case let .same(line): return "  \(line)"
                    case let .added(line): return "+ \(line)"
                    case let .removed(line): return "- \(line)"
                    }
                }.joined(separator: "\n")
                log(.diffChecker, true)
            }
            ResultBlock(text: output, error: "")
        }
    }
}

private struct RegexTool: View {
    @State private var pattern = ""
    @State private var text = ""
    @State private var output = ""
    @State private var errorText = ""
    var body: some View {
        DevBox(tool: .regexTester) {
            TextField("Pattern", text: $pattern)
            TextEditor(text: $text).frame(minHeight: 120)
            PrimaryButton(title: "Find matches", enabled: true) {
                do {
                    let hits = try RegexTester.matches(pattern: pattern, text: text, caseInsensitive: false, multiline: true)
                    output = hits.isEmpty ? "No matches." : hits.map { hit in
                        hit.groups.isEmpty ? hit.full : "\(hit.full)  [\(hit.groups.joined(separator: ", "))]"
                    }.joined(separator: "\n")
                    errorText = ""
                    log(.regexTester, true)
                } catch {
                    errorText = "That pattern is not valid."
                    log(.regexTester, false)
                }
            }
            ResultBlock(text: output, error: errorText)
        }
    }
}

private struct LinksTool: View {
    @State private var text = ""
    @State private var output = ""
    var body: some View {
        DevBox(tool: .cleanLinks) {
            TextEditor(text: $text).frame(minHeight: 80)
            PrimaryButton(title: "Clean", enabled: true) {
                output = text.split(separator: "\n").map { LinkCleaner.clean(String($0)) }.joined(separator: "\n")
                log(.cleanLinks, true)
            }
            ResultBlock(text: output, error: "")
        }
    }
}

private struct CoordinateTool: View {
    @State private var text = "37.77, -122.42"
    @State private var output = ""
    @State private var errorText = ""
    var body: some View {
        DevBox(tool: .coordinatePicker) {
            TextField("Latitude, longitude or a geohash", text: $text)
            PrimaryButton(title: "Convert", enabled: true) {
                do {
                    let parsed = try Coordinates.parse(text)
                    let formats = Coordinates.formats(latitude: parsed.latitude, longitude: parsed.longitude)
                    output = "\(formats.decimal)\n\(formats.dms)\n\(formats.geohash)"
                    errorText = ""
                    log(.coordinatePicker, true)
                } catch {
                    errorText = "Use decimal degrees, like 37.77, -122.42."
                    log(.coordinatePicker, false)
                }
            }
            ResultBlock(text: output, error: errorText)
        }
    }
}

private struct UnicodeTool: View {
    @State private var text = ""
    @State private var output = ""
    var body: some View {
        DevBox(tool: .unicodeInspector) {
            TextField("Characters", text: $text)
            PrimaryButton(title: "Inspect", enabled: true) {
                output = UnicodeInspector.inspect(text).map { row in
                    "\(row.character)  \(row.hex)  \(row.utf8Hex)  \(row.name)  \(row.category)"
                }.joined(separator: "\n")
                log(.unicodeInspector, true)
            }
            ResultBlock(text: output, error: "")
        }
    }
}

private struct LoremTool: View {
    @State private var paragraphs = 2
    @State private var sentences = 3
    @State private var words = 8
    @State private var output = ""
    var body: some View {
        DevBox(tool: .loremIpsum) {
            Stepper("Paragraphs: \(paragraphs)", value: $paragraphs, in: 1...8)
            Stepper("Sentences: \(sentences)", value: $sentences, in: 1...8)
            Stepper("Words: \(words)", value: $words, in: 3...20)
            PrimaryButton(title: "Generate", enabled: true) {
                output = LoremIpsum.generate(paragraphs: paragraphs, sentences: sentences, wordsPerSentence: words)
                log(.loremIpsum, true)
            }
            ResultBlock(text: output, error: "")
        }
    }
}

private struct PasswordTool: View {
    @State private var length = 20
    @State private var upper = true
    @State private var lower = true
    @State private var digits = true
    @State private var symbols = true
    @State private var avoid = true
    @State private var output = ""
    @State private var errorText = ""
    var body: some View {
        DevBox(tool: .passwordGenerator) {
            Stepper("Length: \(length)", value: $length, in: 8...64)
            Toggle("Uppercase", isOn: $upper)
            Toggle("Lowercase", isOn: $lower)
            Toggle("Digits", isOn: $digits)
            Toggle("Symbols", isOn: $symbols)
            Toggle("Skip ambiguous characters", isOn: $avoid)
            PrimaryButton(title: "Generate", enabled: true) {
                var rng = SystemRandomNumberGenerator()
                do {
                    output = try PasswordGenerator.generate(
                        PasswordOptions(length: length, upper: upper, lower: lower, digits: digits, symbols: symbols, avoidAmbiguous: avoid),
                        using: &rng
                    )
                    errorText = ""
                    log(.passwordGenerator, true)
                } catch {
                    errorText = "Pick at least one character set, and a length that fits them."
                    log(.passwordGenerator, false)
                }
            }
            ResultBlock(text: output, error: errorText)
        }
    }
}

private struct CSVTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var output = ""
    @State private var errorText = ""
    var body: some View {
        DevBox(tool: .csvJSON) {
            editor(.csvJSON)
            HStack {
                PrimaryButton(title: "CSV to JSON", enabled: true) {
                    convert { try TabularConvert.csvToJSON(model.draft(for: .csvJSON)) }
                }
                PrimaryButton(title: "JSON to CSV", enabled: true) {
                    convert { try TabularConvert.jsonToCSV(model.draft(for: .csvJSON)) }
                }
            }
            ResultBlock(text: output, error: errorText)
        }
    }

    private func convert(_ body: () throws -> String) {
        do {
            output = try body()
            errorText = ""
            log(.csvJSON, true)
        } catch {
            errorText = "Could not convert that text."
            log(.csvJSON, false)
        }
    }
}

private struct ResultBlock: View {
    var text: String
    var error: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
    }
}

private func editor(_ id: ToolID) -> some View {
    EditorBox(id: id)
}

private struct EditorBox: View {
    @EnvironmentObject private var model: AppModel
    let id: ToolID
    var body: some View {
        TextEditor(text: model.binding(for: id))
            .font(.system(size: 13, design: .monospaced))
            .frame(minHeight: 140)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))
    }
}

private func log(_ id: ToolID, _ ok: Bool) {
    SatchelLog.toolRun(id: id.rawValue, inputs: 1, outcome: ok ? "ok" : "failed", seconds: "0s")
}
