import AppKit
import CoreText
import Foundation
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum OfficeDocs {
    static let powerpointNote = "Each slide’s words are drawn onto a page. Pictures, animation, and the original layout are not reproduced. A Quick Look preview is added when macOS can make one."
    static let excelNote = "The first sheet is a table of stored cell values. Charts, formulas, and formatting are left out."
    static let wordNote = "Paragraphs are kept. Headers, text boxes, and complex layout are not."
    static let convertNote = "Text is converted between plain text, RTF, HTML, and Word. Images and scripts are not preserved."

    static func pdfToWord(url: URL) throws -> URL {
        let document = try PDFJobs.open(url)
        var paragraphs: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) {
                let text = page.string ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { paragraphs.append(trimmed) }
            }
        }
        if paragraphs.isEmpty { throw ToolError(message: "That PDF has no extractable text.") }
        return try DocxPackage.write(paragraphs: paragraphs, nextTo: url, suffix: "-word")
    }

    static func convert(url: URL, ext: String) throws -> URL {
        let target = ext.lowercased()
        let source = try loadAttributed(url)
        let output = try Outputs.make(nextTo: url, suffix: "-converted", ext: target)
        switch target {
        case "txt", "text":
            try source.string.write(to: output, atomically: true, encoding: .utf8)
        case "docx":
            if let data = try? source.data(from: NSRange(location: 0, length: source.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]) {
                try data.write(to: output)
            } else {
                let fallback = try DocxPackage.write(paragraphs: source.string.components(separatedBy: "\n"), nextTo: url, suffix: "-converted")
                if fallback != output {
                    if FileManager.default.fileExists(atPath: output.path) { try? FileManager.default.removeItem(at: output) }
                    try FileManager.default.moveItem(at: fallback, to: output)
                }
            }
        default:
            let type = documentType(target)
            let data = try source.data(from: NSRange(location: 0, length: max(source.length, 0)), documentAttributes: [.documentType: type])
            try data.write(to: output)
        }
        return output
    }

    @MainActor
    static func powerpoint(url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let slides = try SlideText.slides(in: url)
        var images: [CGImage] = []
        if let preview = try? await quickLook(url) {
            images.append(preview)
        }
        progress(0.4)
        let output = try Outputs.make(nextTo: url, suffix: "-slides", ext: "pdf")
        try renderSlides(slides, preview: images.first, to: output)
        progress(1)
        return output
    }

    @MainActor
    static func excel(url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let table = try SheetTable.parse(url)
        progress(0.3)
        let html = SheetTable.html(table)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let rendered = try await WebProbe.pdf(html: html, in: temp)
        let output = try Outputs.make(nextTo: url, suffix: "-sheet", ext: "pdf")
        try FileManager.default.copyItem(at: rendered, to: output)
        progress(1)
        return output
    }

    static func makeWorkbook(cells: [[String]], to url: URL) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var strings: [String] = []
        func index(of value: String) -> Int {
            if let found = strings.firstIndex(of: value) { return found }
            strings.append(value)
            return strings.count - 1
        }
        var rows: [String] = []
        for (rowIndex, row) in cells.enumerated() {
            var cellsXML: [String] = []
            for (column, value) in row.enumerated() {
                let ref = "\(columnName(column))\(rowIndex + 1)"
                if let number = Double(value), value.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
                    cellsXML.append("<c r=\"\(ref)\"><v>\(value)</v></c>")
                } else {
                    let shared = index(of: value)
                    cellsXML.append("<c r=\"\(ref)\" t=\"s\"><v>\(shared)</v></c>")
                }
            }
            rows.append("<row r=\"\(rowIndex + 1)\">\(cellsXML.joined())</row>")
        }
        let sharedXML = strings.map { "<si><t>\(xml($0))</t></si>" }.joined()
        try writePackage(folder, files: [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
            </Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
            </Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
            </workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
            </Relationships>
            """,
            "xl/sharedStrings.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(strings.count)" uniqueCount="\(strings.count)">\(sharedXML)</sst>
            """,
            "xl/worksheets/sheet1.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows.joined())</sheetData></worksheet>
            """
        ])
        try ZipPack.zip(contentsOf: folder, to: url)
    }

    static func makeSlides(lines: [String], to url: URL) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var slideOverrides: [String] = []
        var rels: [String] = []
        var files: [String: String] = [:]
        for (index, line) in lines.enumerated() {
            let number = index + 1
            slideOverrides.append("<Override PartName=\"/ppt/slides/slide\(number).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>")
            rels.append("<Relationship Id=\"rId\(number)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(number).xml\"/>")
            files["ppt/slides/slide\(number).xml"] = """
            <?xml version="1.0" encoding="UTF-8"?>
            <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
            <p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>\(xml(line))</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld>
            </p:sld>
            """
        }
        files["[Content_Types].xml"] = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
        \(slideOverrides.joined())
        </Types>
        """
        files["_rels/.rels"] = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
        </Relationships>
        """
        files["ppt/presentation.xml"] = """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <p:sldIdLst>\(lines.enumerated().map { "<p:sldId id=\"\($0.offset + 256)\" r:id=\"rId\($0.offset + 1)\"/>" }.joined())</p:sldIdLst>
        </p:presentation>
        """
        files["ppt/_rels/presentation.xml.rels"] = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels.joined())</Relationships>
        """
        try writePackage(folder, files: files)
        try ZipPack.zip(contentsOf: folder, to: url)
    }

    private static func loadAttributed(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        if ext == "docx" {
            if let loaded = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil),
               !loaded.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return loaded
            }
            return NSAttributedString(string: try DocxPackage.plainText(url))
        }
        if ext == "txt" || ext == "text" || ext.isEmpty {
            let text = try String(contentsOf: url, encoding: .utf8)
            return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        }
        return try NSAttributedString(url: url, options: [.documentType: documentType(ext)], documentAttributes: nil)
    }

    private static func documentType(_ ext: String) -> NSAttributedString.DocumentType {
        switch ext {
        case "rtf": return .rtf
        case "rtfd": return .rtfd
        case "html", "htm": return .html
        case "doc": return .docFormat
        case "docx": return .officeOpenXML
        default: return .plain
        }
    }

    private static func renderSlides(_ slides: [String], preview: CGImage?, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 720, height: 540)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw ToolError(message: "Could not write the slide PDF.")
        }
        if let preview {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
            let fitted = aspectFit(CGSize(width: preview.width, height: preview.height), in: box.insetBy(dx: 24, dy: 24))
            context.draw(preview, in: fitted)
            context.endPDFPage()
        }
        let pages = slides.isEmpty ? ["This deck had no readable slide text."] : slides
        for slide in pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
            let note = NSAttributedString(string: slide + "\n\n" + powerpointNote, attributes: [
                .font: NSFont.systemFont(ofSize: 22),
                .foregroundColor: NSColor.black
            ])
            draw(note, in: box.insetBy(dx: 48, dy: 48), context: context, page: box)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func draw(_ text: NSAttributedString, in rect: CGRect, context: CGContext, page: CGRect) {
        context.saveGState()
        context.translateBy(x: 0, y: page.height)
        context.scaleBy(x: 1, y: -1)
        let flipped = CGRect(x: rect.minX, y: page.height - rect.maxY, width: rect.width, height: rect.height)
        let path = CGPath(rect: flipped, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / max(size.width, 1), bounds.height / max(size.height, 1))
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    private static func quickLook(_ url: URL) async throws -> CGImage {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 1280, height: 720), scale: 2, representationTypes: .all)
        return try await withCheckedThrowingContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                if let image = representation?.cgImage {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? ToolError(message: "Quick Look made no preview."))
                }
            }
        }
    }

    private static func columnName(_ index: Int) -> String {
        var value = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(65 + (value % 26))!) + name
            value = value / 26 - 1
        } while value >= 0
        return name
    }

    private static func writePackage(_ folder: URL, files: [String: String]) throws {
        for (path, contents) in files {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum DocxPackage {
    static func write(paragraphs: [String], nextTo: URL, suffix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let body = paragraphs.map { "<w:p><w:r><w:t xml:space=\"preserve\">\(OfficeDocs.xml($0))</w:t></w:r></w:p>" }.joined()
        let files = [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>
            """,
            "word/document.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)</w:body></w:document>
            """
        ]
        for (path, contents) in files {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        let output = try Outputs.make(nextTo: nextTo, suffix: suffix, ext: "docx")
        try ZipPack.zip(contentsOf: folder, to: output)
        return output
    }

    static func plainText(_ url: URL) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Commands.run("/usr/bin/ditto", ["-xk", url.path, folder.path])
        guard result.status == 0 else { throw ToolError(message: "Could not read that Word file.") }
        let xml = try String(contentsOf: folder.appendingPathComponent("word/document.xml"), encoding: .utf8)
        return plain(xml)
    }

    private static func plain(_ xml: String) -> String {
        var text = xml.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SlideText {
    static func slides(in url: URL) throws -> [String] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Commands.run("/usr/bin/ditto", ["-xk", url.path, folder.path])
        guard result.status == 0 else { throw ToolError(message: "Could not read that presentation.") }
        let slides = folder.appendingPathComponent("ppt/slides")
        let files = ((try? FileManager.default.contentsOfDirectory(at: slides, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("slide") && $0.pathExtension == "xml" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return files.compactMap { url in
            guard let xml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let texts = matches(xml, pattern: "<a:t[^>]*>([^<]*)</a:t>")
            let joined = texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }
    }

    private static func matches(_ text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let slice = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[slice])
        }
    }
}

enum SheetTable {
    static func parse(_ url: URL) throws -> [[String]] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = Commands.run("/usr/bin/ditto", ["-xk", url.path, folder.path])
        guard result.status == 0 else { throw ToolError(message: "Could not read that spreadsheet.") }
        let shared = (try? String(contentsOf: folder.appendingPathComponent("xl/sharedStrings.xml"), encoding: .utf8)) ?? ""
        let strings = SlideTextMatches.sharedStrings(shared)
        let sheetURL = folder.appendingPathComponent("xl/worksheets/sheet1.xml")
        guard let sheet = try? String(contentsOf: sheetURL, encoding: .utf8) else {
            throw ToolError(message: "That spreadsheet has no first sheet.")
        }
        var rows: [[String]] = []
        let rowPattern = "<row\\b[^>]*>(.*?)</row>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(sheet.startIndex..<sheet.endIndex, in: sheet)
        for match in rowRegex.matches(in: sheet, range: range) {
            guard let slice = Range(match.range(at: 1), in: sheet) else { continue }
            let rowXML = String(sheet[slice])
            var values: [String] = []
            let cellPattern = "<c\\b([^>]*)>(.*?)</c>"
            guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { continue }
            let cellRange = NSRange(rowXML.startIndex..<rowXML.endIndex, in: rowXML)
            for cell in cellRegex.matches(in: rowXML, range: cellRange) {
                guard let attrRange = Range(cell.range(at: 1), in: rowXML),
                      let bodyRange = Range(cell.range(at: 2), in: rowXML) else { continue }
                let attrs = String(rowXML[attrRange])
                let body = String(rowXML[bodyRange])
                if attrs.contains("t=\"s\"") {
                    let index = Int(value(body)) ?? -1
                    values.append(strings.indices.contains(index) ? strings[index] : "")
                } else if let inline = inlineText(body) {
                    values.append(inline)
                } else {
                    values.append(value(body))
                }
            }
            if !values.isEmpty { rows.append(values) }
        }
        if rows.isEmpty { throw ToolError(message: "That sheet has no cells.") }
        return rows
    }

    static func html(_ rows: [[String]]) -> String {
        let body = rows.map { row in
            "<tr>" + row.map { "<td>\(OfficeDocs.xml($0))</td>" }.joined() + "</tr>"
        }.joined()
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
        body { font: 13px -apple-system, sans-serif; margin: 36px; color: #1d1d1f; }
        table { border-collapse: collapse; }
        td { border: 1px solid #d2d2d7; padding: 6px 10px; }
        p { color: #6e6e73; }
        </style></head>
        <body><table>\(body)</table><p>\(OfficeDocs.excelNote)</p></body></html>
        """
    }

    private static func value(_ xml: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<v>([^<]*)</v>") else { return "" }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, range: range), let slice = Range(match.range(at: 1), in: xml) else { return "" }
        return String(xml[slice])
    }

    private static func inlineText(_ xml: String) -> String? {
        guard xml.contains("<t") else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "<t[^>]*>([^<]*)</t>") else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let parts = regex.matches(in: xml, range: range).compactMap { match -> String? in
            guard let slice = Range(match.range(at: 1), in: xml) else { return nil }
            return String(xml[slice])
        }
        let joined = parts.joined()
        return joined.isEmpty ? nil : joined
    }
}

private enum SlideTextMatches {
    static func sharedStrings(_ xml: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<si\\b[^>]*>(.*?)</si>", options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, range: range).map { match in
            guard let slice = Range(match.range(at: 1), in: xml) else { return "" }
            let body = String(xml[slice])
            guard let textRegex = try? NSRegularExpression(pattern: "<t[^>]*>([^<]*)</t>") else { return "" }
            let textRange = NSRange(body.startIndex..<body.endIndex, in: body)
            return textRegex.matches(in: body, range: textRange).compactMap { item -> String? in
                guard let part = Range(item.range(at: 1), in: body) else { return nil }
                return String(body[part])
            }.joined()
        }
    }
}

enum ZipPack {
    static func zip(contentsOf folder: URL, to dest: URL) throws {
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard !children.isEmpty else { throw ToolError(message: "Could not package an empty document.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.currentDirectoryURL = folder
        process.arguments = ["-c", "-k", "--norsrc"] + children + [dest.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: dest.path) else {
            throw ToolError(message: "Could not package the document.")
        }
    }
}

enum MarkdownHTML {
    static func page(_ markdown: String) -> String {
        let body: String
        if let parsed = try? AttributedString(markdown: markdown) {
            let rendered = NSAttributedString(parsed)
            if rendered.length > 0,
               let data = try? rendered.data(from: NSRange(location: 0, length: rendered.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
               var html = String(data: data, encoding: .utf8) {
                let note = "<p style=\"color:#6e6e73;font:12px -apple-system\">Reading copy made on this Mac. It is not a word-processor layout.</p>"
                if html.contains("</body>") {
                    html = html.replacingOccurrences(of: "</body>", with: note + "</body>")
                } else {
                    html += note
                }
                return html
            }
            body = "<p>\(OfficeDocs.xml(NSAttributedString(parsed).string))</p>"
        } else {
            body = markdown
                .components(separatedBy: "\n\n")
                .map { "<p>\(OfficeDocs.xml($0))</p>" }
                .joined()
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>body { font: 16px -apple-system, sans-serif; margin: 48px; line-height: 1.45; color: #1d1d1f; }</style>
        </head><body>\(body)
        <p style="color:#6e6e73;font-size:12px">Reading copy made on this Mac. It is not a word-processor layout.</p>
        </body></html>
        """
    }
}
