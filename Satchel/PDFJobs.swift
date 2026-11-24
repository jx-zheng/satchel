import AppKit
import PDFKit
import Vision
import CoreGraphics
import CoreText
import UniformTypeIdentifiers
import SatchelCore

enum PDFJobs {
    static func open(_ url: URL, password: String = "") throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw ToolError(message: "Could not open \(url.lastPathComponent).")
        }
        if document.isLocked {
            guard document.unlock(withPassword: password) else {
                throw ToolError(message: "That PDF is locked. Type the password that opens it.")
            }
        }
        guard document.pageCount > 0 else { throw ToolError(message: "That PDF has no pages.") }
        return document
    }

    static func merge(urls: [URL], progress: @escaping (Double) -> Void) throws -> [URL] {
        guard urls.count >= 2 else { throw ToolError(message: "Drop at least two PDFs.") }
        let combined = PDFDocument()
        for (index, url) in urls.enumerated() {
            let document = try open(url)
            for pageIndex in 0..<document.pageCount {
                if let page = document.page(at: pageIndex) {
                    combined.insert(page, at: combined.pageCount)
                }
            }
            progress(Double(index + 1) / Double(urls.count))
        }
        let output = try Outputs.make(nextTo: urls[0], suffix: "-merged", ext: "pdf")
        guard combined.write(to: output) else { throw ToolError(message: "Could not write the merged PDF.") }
        return [output]
    }

    static func split(url: URL, spec: String, perPage: Bool, progress: @escaping (Double) -> Void) throws -> [URL] {
        let document = try open(url)
        if perPage {
            var outputs: [URL] = []
            for index in 0..<document.pageCount {
                let piece = PDFDocument()
                if let page = document.page(at: index) { piece.insert(page, at: 0) }
                let output = try Outputs.make(nextTo: url, suffix: "-p\(index + 1)", ext: "pdf")
                guard piece.write(to: output) else { throw ToolError(message: "Could not write a page.") }
                outputs.append(output)
                progress(Double(index + 1) / Double(document.pageCount))
            }
            return outputs
        }
        let pages = try PageList.parse(spec.isEmpty ? "all" : spec, count: document.pageCount)
        let piece = PDFDocument()
        for number in pages {
            if let page = document.page(at: number - 1) { piece.insert(page, at: piece.pageCount) }
        }
        let output = try Outputs.make(nextTo: url, suffix: "-pages", ext: "pdf")
        guard piece.write(to: output) else { throw ToolError(message: "Could not write the PDF.") }
        progress(1)
        return [output]
    }

    static func deletePages(url: URL, spec: String) throws -> [URL] {
        let document = try open(url)
        let dropping = Set(try PageList.parse(spec, count: document.pageCount))
        let kept = PDFDocument()
        for index in 0..<document.pageCount where !dropping.contains(index + 1) {
            if let page = document.page(at: index) { kept.insert(page, at: kept.pageCount) }
        }
        guard kept.pageCount > 0 else { throw ToolError(message: "That would remove every page.") }
        let output = try Outputs.make(nextTo: url, suffix: "-edited", ext: "pdf")
        guard kept.write(to: output) else { throw ToolError(message: "Could not write the PDF.") }
        return [output]
    }

    static func extract(url: URL, spec: String) throws -> [URL] {
        try split(url: url, spec: spec, perPage: false, progress: { _ in })
    }

    static func organize(url: URL, order: [Int]) throws -> [URL] {
        let document = try open(url)
        let sequence = try PageList.permutation(order, count: document.pageCount)
        let next = PDFDocument()
        for number in sequence {
            if let page = document.page(at: number - 1) { next.insert(page, at: next.pageCount) }
        }
        let output = try Outputs.make(nextTo: url, suffix: "-ordered", ext: "pdf")
        guard next.write(to: output) else { throw ToolError(message: "Could not write the PDF.") }
        return [output]
    }

    static func imagesToPDF(urls: [URL], progress: @escaping (Double) -> Void) throws -> [URL] {
        guard !urls.isEmpty else { throw ToolError(message: "Drop at least one image.") }
        var images: [CGImage] = []
        for (index, url) in urls.enumerated() {
            images.append(try ImageFiles.load(url))
            progress(Double(index + 1) / Double(urls.count))
        }
        let output = try Outputs.make(nextTo: urls[0], suffix: "-pages", ext: "pdf")
        try writeImages(images, to: output, pageBox: nil)
        return [output]
    }

    static func pdfToImages(url: URL, ext: String, progress: @escaping (Double) -> Void) throws -> [URL] {
        let document = try open(url)
        let folder = try Outputs.folder(nextTo: url, nameSuffix: "-pages")
        let type = ImageFiles.type(for: ext)
        var outputs: [URL] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = render(page, scale: 2) else { continue }
            let file = folder.appendingPathComponent(String(format: "page-%03d.%@", index + 1, ext))
            try ImageFiles.write(image, to: file, type: type, quality: type == .jpeg ? 0.9 : nil)
            outputs.append(file)
            progress(Double(index + 1) / Double(document.pageCount))
        }
        return [folder]
    }

    static func crop(url: URL, margin: CGFloat) throws -> [URL] {
        let document = try open(url)
        let next = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = render(page, scale: 2) else { continue }
            let inset = max(0, margin) * 2
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            let rect = CGRect(x: inset, y: inset, width: max(2, width - inset * 2), height: max(2, height - inset * 2))
            guard let cropped = image.cropping(to: rect) else { continue }
            if let pdfPage = PDFPage(image: NSImage(cgImage: cropped, size: NSSize(width: CGFloat(cropped.width), height: CGFloat(cropped.height)))) {
                next.insert(pdfPage, at: next.pageCount)
            }
        }
        let output = try Outputs.make(nextTo: url, suffix: "-cropped", ext: "pdf")
        guard next.write(to: output) else { throw ToolError(message: "Could not write the cropped PDF.") }
        return [output]
    }

    static func compress(url: URL, quality: Double, progress: @escaping (Double) -> Void) throws -> [URL] {
        let originalBytes = FileSize.bytes(url)
        let document = try open(url)
        let clamped = min(0.82, max(0.35, quality))
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ToolError(message: "Could not start a smaller PDF.")
        }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ToolError(message: "Could not start a smaller PDF.")
        }
        let count = max(1, document.pageCount)
        let pixelCap: CGFloat = clamped < 0.5 ? 1100 : (clamped < 0.7 ? 1500 : 1900)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let longSide = max(bounds.width, bounds.height)
            let scale = min(1, pixelCap / max(longSide, 1))
            context.beginPDFPage(Self.pageInfo(bounds))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(bounds)
            if let image = render(page, scale: scale),
               let jpeg = jpegData(image, quality: clamped),
               let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
               let compressed = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                context.draw(compressed, in: bounds)
            } else {
                page.draw(with: .mediaBox, to: context)
            }
            context.endPDFPage()
            progress(Double(index + 1) / Double(count))
        }
        context.closePDF()
        if Int64(data.length) >= originalBytes {
            throw ToolError(message: "This PDF is already as small as it can be. The original was left unchanged.")
        }
        let output = try Outputs.make(nextTo: url, suffix: "-smaller", ext: "pdf")
        try (data as Data).write(to: output)
        return [output]
    }

    static func writeForm(to url: URL) throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ToolError(message: "Could not start the form PDF.")
        }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        guard let document = PDFDocument(data: data as Data), let page = document.page(at: 0) else {
            throw ToolError(message: "Could not open the form PDF.")
        }
        let field = PDFAnnotation(bounds: CGRect(x: 72, y: 700, width: 240, height: 22), forType: .widget, withProperties: nil)
        field.widgetFieldType = .text
        field.fieldName = "Name"
        field.widgetStringValue = ""
        page.addAnnotation(field)
        guard document.write(to: url) else { throw ToolError(message: "Could not write the form PDF.") }
    }

    static func addPassword(url: URL, current: String, password: String) throws -> [URL] {
        guard password.count >= 4 else { throw ToolError(message: "Use a password of at least 4 characters.") }
        let document = try open(url, password: current)
        let output = try Outputs.make(nextTo: url, suffix: "-locked", ext: "pdf")
        let options: [PDFDocumentWriteOption: Any] = [
            PDFDocumentWriteOption.userPasswordOption: password,
            PDFDocumentWriteOption.ownerPasswordOption: password
        ]
        guard document.write(to: output, withOptions: options) else {
            throw ToolError(message: "Could not write the locked PDF.")
        }
        return [output]
    }

    static func removePassword(url: URL, password: String) throws -> [URL] {
        let document = try open(url, password: password)
        let output = try Outputs.make(nextTo: url, suffix: "-unlocked", ext: "pdf")
        guard document.write(to: output) else { throw ToolError(message: "Could not write the unlocked PDF.") }
        return [output]
    }

    struct FormLine: Identifiable {
        var id: String
        var name: String
        var page: Int
        var value: String
    }

    static func formFields(url: URL, password: String) throws -> [FormLine] {
        let document = try open(url, password: password)
        var lines: [FormLine] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.widgetFieldType == .text {
                let name = annotation.fieldName ?? "Field \(lines.count + 1)"
                lines.append(FormLine(id: "\(index)-\(name)-\(lines.count)", name: name, page: index, value: annotation.widgetStringValue ?? ""))
            }
        }
        return lines
    }

    static func fill(url: URL, password: String, values: [String: String]) throws -> [URL] {
        let document = try open(url, password: password)
        var filled = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.widgetFieldType == .text {
                guard let name = annotation.fieldName, let value = values[name] else { continue }
                annotation.widgetStringValue = value
                filled += 1
            }
        }
        guard filled > 0 else { throw ToolError(message: "This PDF has no text fields to fill.") }
        var images: [CGImage] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let image = render(page, scale: 2) {
                images.append(image)
            }
        }
        let output = try Outputs.make(nextTo: url, suffix: "-filled", ext: "pdf")
        try writeImages(images, to: output, pageBox: nil)
        return [output]
    }

    static func sign(url: URL, signature: NSImage, pageIndex: Int, placement: CGRect) throws -> [URL] {
        let document = try open(url)
        guard let page = document.page(at: pageIndex) else { throw ToolError(message: "That page is missing.") }
        guard let rendered = render(page, scale: 2) else { throw ToolError(message: "Could not draw the page.") }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let image = try ImageJobsDrawing.composite(base: rendered, signature: signature, pdfRect: placement, pageBounds: bounds, scale: scale)
        let outputDocument = PDFDocument()
        for index in 0..<document.pageCount {
            if index == pageIndex {
                if let pdfPage = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))) {
                    outputDocument.insert(pdfPage, at: outputDocument.pageCount)
                }
            } else if let existing = document.page(at: index) {
                outputDocument.insert(existing, at: outputDocument.pageCount)
            }
        }
        let output = try Outputs.make(nextTo: url, suffix: "-signed", ext: "pdf")
        guard outputDocument.write(to: output) else { throw ToolError(message: "Could not write the signed PDF.") }
        return [output]
    }

    static func redact(url: URL, word: String, extra: [Int: [CGRect]], progress: @escaping (Double) -> Void) throws -> [URL] {
        let document = try open(url)
        var boxes = extra
        let needle = word.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            let selections = document.findString(needle, withOptions: [.caseInsensitive])
            for selection in selections {
                for page in selection.pages {
                    guard let index = document.index(for: page) as Int? else { continue }
                    boxes[index, default: []].append(selection.bounds(for: page))
                }
            }
        }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ToolError(message: "Could not start the redacted PDF.")
        }
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw ToolError(message: "Could not start the redacted PDF.")
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            context.beginPDFPage(Self.pageInfo(bounds))
            context.setFillColor(NSColor.white.cgColor)
            context.fill(bounds)
            if let image = render(page, scale: 2) {
                context.draw(image, in: bounds)
            }
            context.setFillColor(NSColor.black.cgColor)
            for rect in boxes[index] ?? [] {
                context.fill(rect)
            }
            context.endPDFPage()
            progress(Double(index + 1) / Double(document.pageCount))
        }
        context.closePDF()
        let output = try Outputs.make(nextTo: url, suffix: "-redacted", ext: "pdf")
        try (data as Data).write(to: output)
        return [output]
    }

    static func searchable(url: URL, progress: @escaping (Double) -> Void) throws -> [URL] {
        let document = try open(url)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ToolError(message: "Could not start a searchable PDF.")
        }
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw ToolError(message: "Could not start a searchable PDF.")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let image = render(page, scale: 2) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            context.beginPDFPage(Self.pageInfo(bounds))
            context.draw(image, in: bounds)
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try? handler.perform([request])
            context.saveGState()
            context.setTextDrawingMode(.invisible)
            for observation in request.results ?? [] {
                guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { continue }
                let normalized = observation.boundingBox
                let rect = CGRect(
                    x: bounds.minX + normalized.minX * bounds.width,
                    y: bounds.minY + normalized.minY * bounds.height,
                    width: normalized.width * bounds.width,
                    height: normalized.height * bounds.height
                )
                let font = CTFontCreateWithName("Helvetica" as CFString, max(6, rect.height * 0.8), nil)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
                context.textMatrix = .identity
                context.textPosition = CGPoint(x: rect.minX, y: rect.minY)
                CTLineDraw(line, context)
            }
            context.restoreGState()
            context.endPDFPage()
            progress(Double(index + 1) / Double(document.pageCount))
        }
        context.closePDF()
        let output = try Outputs.make(nextTo: url, suffix: "-searchable", ext: "pdf")
        try (data as Data).write(to: output)
        return [output]
    }

    static func markdown(_ text: String, nextTo: URL?) async throws -> URL {
        let html = MarkdownHTML.page(text)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let rendered = try await WebProbe.pdf(html: html, in: temp)
        let output: URL
        if let nextTo {
            output = try Outputs.make(nextTo: nextTo, suffix: "-notes", ext: "pdf")
        } else {
            let folder = try Outputs.directory(in: .downloadsDirectory, subfolder: "Satchel")
            output = folder.appendingPathComponent("Notes.pdf")
            if FileManager.default.fileExists(atPath: output.path) {
                try FileManager.default.removeItem(at: output)
            }
        }
        try FileManager.default.copyItem(at: rendered, to: output)
        return output
    }

    static func wordToPDF(url: URL) async throws -> URL {
        let attributed: NSAttributedString
        let ext = url.pathExtension.lowercased()
        if ext == "docx" {
            let plain = try docxText(url)
            attributed = NSAttributedString(string: plain, attributes: [
                .font: NSFont.systemFont(ofSize: 12)
            ])
        } else {
            let type: NSAttributedString.DocumentType
            switch ext {
            case "rtf": type = .rtf
            case "html", "htm": type = .html
            default: type = .plain
            }
            attributed = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        }
        let output = try Outputs.make(nextTo: url, suffix: "-print", ext: "pdf")
        try renderCoreText(attributed, to: output)
        return output
    }

    static func writeImages(_ images: [CGImage], to url: URL, pageBox: CGSize?) throws {
        let document = PDFDocument()
        for image in images {
            let size = NSSize(width: CGFloat(image.width), height: CGFloat(image.height))
            if let page = PDFPage(image: NSImage(cgImage: image, size: size)) {
                document.insert(page, at: document.pageCount)
            }
        }
        guard document.pageCount > 0, document.write(to: url) else {
            throw ToolError(message: "Could not write the PDF.")
        }
    }

    private static func pageInfo(_ bounds: CGRect) -> CFDictionary {
        let data = withUnsafeBytes(of: bounds) { Data($0) } as CFData
        let info: [CFString: CFData] = [kCGPDFContextMediaBox: data]
        return info as CFDictionary
    }

    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    private static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func renderCoreText(_ text: NSAttributedString, to url: URL) throws {
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &media, nil) else {
            throw ToolError(message: "Could not write the PDF.")
        }
        let margin: CGFloat = 54
        let framesetter = CTFramesetterCreateWithAttributedString(text.length == 0 ? NSAttributedString(string: " ") : text)
        var index = 0
        var guardPages = 0
        let length = max((text.length == 0 ? 1 : text.length), 1)
        while index < length && guardPages < 80 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(media)
            context.saveGState()
            context.translateBy(x: 0, y: media.height)
            context.scaleBy(x: 1, y: -1)
            let textRect = CGRect(x: margin, y: margin, width: media.width - margin * 2, height: media.height - margin * 2)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: index, length: 0), path, nil)
            CTFrameDraw(frame, context)
            context.restoreGState()
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guardPages += 1
            if visible.length <= 0 { break }
            index += visible.length
        }
        context.closePDF()
    }

    private static func docxText(_ url: URL) throws -> String {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let result = Commands.run("/usr/bin/ditto", ["-xk", url.path, temp.path])
        guard result.status == 0 else { throw ToolError(message: "Could not read that Word file.") }
        let xmlURL = temp.appendingPathComponent("word/document.xml")
        guard let xml = try? String(contentsOf: xmlURL, encoding: .utf8) else {
            throw ToolError(message: "That Word file has no document text.")
        }
        var text = xml.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "<w:tab/>", with: "\t")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ToolError(message: "That Word file has no readable text.") }
        return trimmed
    }
}

enum ImageJobsDrawing {
    static func composite(base: CGImage, signature: NSImage, pdfRect: CGRect, pageBounds: CGRect, scale: CGFloat) throws -> CGImage {
        let width = base.width
        let height = base.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ToolError(message: "Could not draw the signature.") }
        context.draw(base, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let signatureImage = signature.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ToolError(message: "Draw a signature first.")
        }
        let dest = CGRect(
            x: pdfRect.minX * scale,
            y: pdfRect.minY * scale,
            width: pdfRect.width * scale,
            height: pdfRect.height * scale
        )
        context.draw(signatureImage, in: dest)
        guard let image = context.makeImage() else { throw ToolError(message: "Could not finish the signed page.") }
        return image
    }
}

enum MarkdownRender {
    static func attributed(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let font: NSFont
            let text: String
            if trimmed.hasPrefix("### ") {
                font = NSFont.systemFont(ofSize: 15, weight: .semibold)
                text = String(trimmed.dropFirst(4))
            } else if trimmed.hasPrefix("## ") {
                font = NSFont.systemFont(ofSize: 18, weight: .bold)
                text = String(trimmed.dropFirst(3))
            } else if trimmed.hasPrefix("# ") {
                font = NSFont.systemFont(ofSize: 22, weight: .bold)
                text = String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                font = NSFont.systemFont(ofSize: 12)
                text = "• " + trimmed.dropFirst(2)
            } else {
                font = NSFont.systemFont(ofSize: 12)
                text = inline(trimmed)
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 8
            result.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]))
        }
        if result.length == 0 {
            result.append(NSAttributedString(string: " "))
        }
        return result
    }

    private static func inline(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}

enum OCRJobs {
    static func text(from image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n")
        guard !joined.isEmpty else { throw ToolError(message: "No text was found.") }
        return joined
    }

    static func text(fromPDF url: URL, progress: @escaping (Double) -> Void) throws -> String {
        let document = try PDFJobs.open(url)
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let image = PDFJobs.render(page, scale: 2) {
                if let text = try? text(from: image) {
                    pages.append(text)
                }
            }
            progress(Double(index + 1) / Double(document.pageCount))
        }
        let joined = pages.joined(separator: "\n\n")
        guard !joined.isEmpty else { throw ToolError(message: "No text was found.") }
        return joined
    }
}
