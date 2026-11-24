import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import SatchelCore

struct DocToolScreen: View {
    let id: ToolID
    var body: some View {
        switch id {
        case .mergePDFs: MergePDFTool()
        case .splitPDF: PageSpecTool(tool: .splitPDF, title: "Split", allowsPerPage: true)
        case .deletePages: PageSpecTool(tool: .deletePages, title: "Delete pages", allowsPerPage: false)
        case .extractPages: PageSpecTool(tool: .extractPages, title: "Extract pages", allowsPerPage: false)
        case .organizePDF: OrganizePDFTool()
        case .imagesToPDF: ImagesToPDFTool()
        case .pdfToImages: PDFToImagesTool()
        case .cropPDF: CropPDFTool()
        case .compressPDF: CompressPDFTool()
        case .addPassword: PasswordPDFTool(adding: true)
        case .removePassword: PasswordPDFTool(adding: false)
        case .fillForms: FillFormsTool()
        case .signPDF: SignPDFTool()
        case .redactPDF: RedactPDFTool()
        case .searchablePDF: SearchablePDFTool()
        case .scanDocument: ScanTool()
        case .wordToPDF: WordPDFTool()
        case .markdownToPDF: MarkdownPDFTool()
        case .webPageToPDF: WebPDFTool()
        case .pdfToWord: PDFToWordTool()
        case .convertDocuments: ConvertDocumentsTool()
        case .powerpointToPDF: PowerPointPDFTool()
        case .excelToPDF: ExcelPDFTool()
        default:
            if let tool = ToolRegistry.byID[id] { ComingSoonView(tool: tool) }
        }
    }
}

private struct MergePDFTool: View {
    var body: some View {
        FileJobView(tool: .mergePDFs, types: MediaTypes.pdfs, prompt: "Drop PDFs in order", actionTitle: "Merge") {
            EmptyView()
        } perform: { urls, progress in
            try PDFJobs.merge(urls: urls, progress: progress)
        }
    }
}

private struct PageSpecTool: View {
    var tool: ToolID
    var title: String
    var allowsPerPage: Bool
    @State private var spec = "1-3"
    @State private var perPage = false
    var body: some View {
        FileJobView(tool: tool, types: MediaTypes.pdfs, prompt: "Drop a PDF", actionTitle: title, multiple: false) {
            if allowsPerPage { Toggle("One file per page", isOn: $perPage) }
            if !perPage {
                TextField("Pages, such as 1-3, 5", text: $spec)
            }
        } perform: { urls, progress in
            guard let url = urls.first else { return [] }
            switch tool {
            case .deletePages:
                return try PDFJobs.deletePages(url: url, spec: spec)
            case .extractPages:
                return try PDFJobs.extract(url: url, spec: spec)
            default:
                return try PDFJobs.split(url: url, spec: spec, perPage: perPage, progress: progress)
            }
        }
    }
}

private struct OrganizePDFTool: View {
    @State private var url: URL?
    @State private var order: [Int] = []
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.organizePDF)) {
            DropZone(prompt: "Drop a PDF", types: MediaTypes.pdfs, multiple: false) { urls in
                url = urls.first
                if let url, let doc = PDFDocument(url: url) {
                    order = Array(1...max(doc.pageCount, 0))
                }
            }
            ForEach(Array(order.enumerated()), id: \.offset) { index, page in
                HStack {
                    Text("Page \(page)")
                    Spacer()
                    Button("Up") { swap(index, -1) }.disabled(index == 0)
                    Button("Down") { swap(index, 1) }.disabled(index == order.count - 1)
                }
            }
            PrimaryButton(title: "Save new order", enabled: url != nil && order.count > 1) {
                guard let url else { return }
                do {
                    let start = Date()
                    let made = try PDFJobs.organize(url: url, order: order)
                    message = "Saved \(made.first?.lastPathComponent ?? "")"
                    SatchelLog.toolRun(id: ToolID.organizePDF.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                } catch { message = error.localizedDescription }
            }
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func swap(_ index: Int, _ delta: Int) {
        let next = index + delta
        guard order.indices.contains(next) else { return }
        order.swapAt(index, next)
    }
}

private struct ImagesToPDFTool: View {
    var body: some View {
        FileJobView(tool: .imagesToPDF, types: MediaTypes.images, prompt: "Drop images", actionTitle: "Make PDF") {
            EmptyView()
        } perform: { urls, progress in
            try PDFJobs.imagesToPDF(urls: urls, progress: progress)
        }
    }
}

private struct PDFToImagesTool: View {
    @State private var format = "png"
    var body: some View {
        FileJobView(tool: .pdfToImages, types: MediaTypes.pdfs, prompt: "Drop a PDF", actionTitle: "Export pages", multiple: false) {
            Picker("Format", selection: $format) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpg")
            }
            .pickerStyle(.segmented)
        } perform: { urls, progress in
            guard let url = urls.first else { return [] }
            return try PDFJobs.pdfToImages(url: url, ext: format, progress: progress)
        }
    }
}

private struct CropPDFTool: View {
    @State private var margin = "36"
    var body: some View {
        FileJobView(tool: .cropPDF, types: MediaTypes.pdfs, prompt: "Drop a PDF", actionTitle: "Crop", multiple: false) {
            TextField("Margin in points", text: $margin).frame(width: 160)
        } perform: { urls, _ in
            guard let url = urls.first else { return [] }
            return try PDFJobs.crop(url: url, margin: CGFloat(Double(margin) ?? 36))
        }
    }
}

private struct CompressPDFTool: View {
    @State private var quality = 0.55
    var body: some View {
        FileJobView(tool: .compressPDF, types: MediaTypes.pdfs, prompt: "Drop a PDF", actionTitle: "Compress", multiple: false, tracksSavings: true) {
            HStack {
                Text("Image quality")
                Slider(value: $quality, in: 0.3...0.85)
            }
        } perform: { urls, progress in
            guard let url = urls.first else { return [] }
            return try PDFJobs.compress(url: url, quality: quality, progress: progress)
        }
    }
}

private struct PasswordPDFTool: View {
    var adding: Bool
    @State private var current = ""
    @State private var password = ""
    var body: some View {
        FileJobView(tool: adding ? .addPassword : .removePassword, types: MediaTypes.pdfs, prompt: "Drop a PDF", actionTitle: adding ? "Lock copy" : "Save unlocked copy", multiple: false) {
            if adding || true {
                SecureField(adding ? "Current password, if any" : "Password", text: adding ? $current : $password)
            }
            if adding { SecureField("New password", text: $password) }
        } perform: { urls, _ in
            guard let url = urls.first else { return [] }
            if adding { return try PDFJobs.addPassword(url: url, current: current, password: password) }
            return try PDFJobs.removePassword(url: url, password: password)
        }
    }
}

private struct FillFormsTool: View {
    @State private var url: URL?
    @State private var password = ""
    @State private var lines: [PDFJobs.FormLine] = []
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.fillForms)) {
            DropZone(prompt: "Drop a PDF with form fields", types: MediaTypes.pdfs, multiple: false) { url = $0.first }
            SecureField("Password, if the file is locked", text: $password)
            PrimaryButton(title: "Find fields", enabled: url != nil) { load() }
            ForEach($lines) { $line in
                HStack {
                    Text(line.name).frame(width: 160, alignment: .leading)
                    TextField("Value", text: $line.value)
                }
            }
            if lines.isEmpty {
                Text("Flat scans without real form fields are not turned into fields here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            PrimaryButton(title: "Save flattened copy", enabled: !lines.isEmpty) { save() }
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard let url else { return }
        do {
            lines = try PDFJobs.formFields(url: url, password: password)
            message = lines.isEmpty ? "No text fields were found." : "\(lines.count) fields"
        } catch { message = error.localizedDescription }
    }

    private func save() {
        guard let url else { return }
        var values: [String: String] = [:]
        for line in lines { values[line.name] = line.value }
        do {
            let start = Date()
            let made = try PDFJobs.fill(url: url, password: password, values: values)
            message = "Saved \(made.first?.lastPathComponent ?? "")"
            SatchelLog.toolRun(id: ToolID.fillForms.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
        } catch { message = error.localizedDescription }
    }
}

private struct SignPDFTool: View {
    @State private var url: URL?
    @State private var pageCount = 1
    @State private var page = 1
    @State private var lines: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var message = ""

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.signPDF)) {
            DropZone(prompt: "Drop a PDF", types: MediaTypes.pdfs, multiple: false) { urls in
                url = urls.first
                if let url, let doc = PDFDocument(url: url) { pageCount = max(1, doc.pageCount) }
            }
            Stepper("Page \(page)", value: $page, in: 1...max(1, pageCount))
            Text("Draw your signature")
                .font(.system(size: 12, weight: .semibold))
            Canvas { context, _ in
                let ink = GraphicsContext.Shading.color(.black)
                for line in lines + [current] {
                    var path = Path()
                    guard let first = line.first else { continue }
                    path.move(to: first)
                    for point in line.dropFirst() { path.addLine(to: point) }
                    context.stroke(path, with: ink, lineWidth: 2.2)
                }
            }
            .frame(height: 140)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    current.append(value.location)
                }
                .onEnded { _ in
                    if current.count > 1 { lines.append(current) }
                    current = []
                })
            HStack {
                Button("Clear") { lines = []; current = [] }
                PrimaryButton(title: "Place and save", enabled: url != nil && !lines.isEmpty) { save() }
            }
            Text("The signature is drawn onto the lower-left of the chosen page and flattened into the file.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let url else { return }
        let image = NSImage(size: NSSize(width: 360, height: 140))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 360, height: 140).fill()
        let path = NSBezierPath()
        path.lineWidth = 3
        for line in lines {
            guard let first = line.first else { continue }
            path.move(to: CGPoint(x: first.x, y: 140 - first.y))
            for point in line.dropFirst() {
                path.line(to: CGPoint(x: point.x, y: 140 - point.y))
            }
        }
        NSColor.black.setStroke()
        path.stroke()
        image.unlockFocus()
        do {
            let start = Date()
            let made = try PDFJobs.sign(url: url, signature: image, pageIndex: page - 1, placement: CGRect(x: 72, y: 72, width: 180, height: 70))
            message = "Saved \(made.first?.lastPathComponent ?? "")"
            SatchelLog.toolRun(id: ToolID.signPDF.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
        } catch { message = error.localizedDescription }
    }
}

private struct RedactPDFTool: View {
    @State private var url: URL?
    @State private var word = ""
    @State private var message = ""
    @State private var running = false
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.redactPDF)) {
            DropZone(prompt: "Drop a PDF", types: MediaTypes.pdfs, multiple: false) { url = $0.first }
            TextField("Word or phrase to black out", text: $word)
            Text("Each match is painted over, then the page is rebuilt from the picture so the words are not still in the file. Metadata from the original is not copied.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            PrimaryButton(title: running ? "Working…" : "Redact", enabled: url != nil && !word.isEmpty && !running) {
                guard let url else { return }
                running = true
                let term = word
                Task {
                    do {
                        let start = Date()
                        let made = try PDFJobs.redact(url: url, word: term, extra: [:]) { _ in }
                        message = "Saved \(made.first?.lastPathComponent ?? "")"
                        SatchelLog.toolRun(id: ToolID.redactPDF.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                    } catch { message = error.localizedDescription }
                    running = false
                }
            }
            Text(message).foregroundStyle(.secondary)
        }
        .onAppear {
            guard DemoSession.enabled, DemoSession.take(.redactPDF), let file = DemoSession.files[.redactPDF]?.first else { return }
            url = file
            word = "secret"
            running = true
            Task {
                do {
                    let made = try PDFJobs.redact(url: file, word: "secret", extra: [:]) { _ in }
                    message = "Saved \(made.first?.lastPathComponent ?? "")"
                } catch { message = error.localizedDescription }
                running = false
            }
        }
    }
}

private struct SearchablePDFTool: View {
    var body: some View {
        FileJobView(tool: .searchablePDF, types: MediaTypes.pdfs, prompt: "Drop a scanned PDF", actionTitle: "Make searchable", multiple: false) {
            Text("Text recognition runs on this Mac. The new file has a hidden text layer.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } perform: { urls, progress in
            guard let url = urls.first else { return [] }
            return try PDFJobs.searchable(url: url, progress: progress)
        }
    }
}

private struct ScanTool: View {
    var body: some View {
        FileJobView(tool: .scanDocument, types: MediaTypes.images, prompt: "Drop photos of pages", actionTitle: "Make a scan") {
            Text("Pages are straightened when a page outline is found, then saved as a PDF.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } perform: { urls, progress in
            try await ImageJobs.scan(urls: urls, progress: progress)
        }
    }
}

private struct WordPDFTool: View {
    var body: some View {
        FileJobView(tool: .wordToPDF, types: [UTType(filenameExtension: "docx") ?? .data, .rtf, .plainText, .html], prompt: "Drop a Word, RTF, HTML, or text file", actionTitle: "Make PDF", multiple: false) {
            Text("Drawn with Core Text into a PDF. Complex Word layouts are simplified. Nothing is sent off this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } perform: { urls, _ in
            guard let url = urls.first else { return [] }
            return [try await PDFJobs.wordToPDF(url: url)]
        }
    }
}

private struct MarkdownPDFTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.markdownToPDF)) {
            TextEditor(text: model.binding(for: .markdownToPDF))
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))
            PrimaryButton(title: "Save PDF", enabled: !model.draft(for: .markdownToPDF).isEmpty) {
                let draft = model.draft(for: .markdownToPDF)
                Task {
                    do {
                        let start = Date()
                        let folder = try Outputs.directory(in: .downloadsDirectory, subfolder: "Satchel")
                        let stub = folder.appendingPathComponent("notes.md")
                        let output = try await PDFJobs.markdown(draft, nextTo: stub)
                        message = "Saved \(output.lastPathComponent) in Downloads/Satchel"
                        SatchelLog.toolRun(id: ToolID.markdownToPDF.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                    } catch { message = error.localizedDescription }
                }
            }
            Text(message).foregroundStyle(.secondary)
        }
        .onAppear {
            guard DemoSession.enabled, DemoSession.take(.markdownToPDF) else { return }
            let draft = model.draft(for: .markdownToPDF)
            guard !draft.isEmpty else { return }
            Task {
                do {
                    let folder = try Outputs.directory(in: .downloadsDirectory, subfolder: "Satchel")
                    let stub = folder.appendingPathComponent("notes.md")
                    let output = try await PDFJobs.markdown(draft, nextTo: stub)
                    message = "Saved \(output.lastPathComponent) in Downloads/Satchel"
                } catch {
                    message = error.localizedDescription
                }
            }
        }
    }
}

private struct WebPDFTool: View {
    @StateObject private var model = WebPDFModel()
    @State private var address = "https://"
    @State private var message = ""

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.webPageToPDF)) {
            TextField("Web address or leave blank and drop HTML below", text: $address)
            DropZone(prompt: "Or drop an HTML file", types: [.html], multiple: false) { urls in
                if let url = urls.first { model.loadFile(url) }
            }
            WebPreview(model: model)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                PrimaryButton(title: "Load", enabled: address.contains(".")) { model.load(address: address) }
                PrimaryButton(title: model.busy ? "Saving…" : "Save PDF", enabled: !model.busy) {
                    Task {
                        do {
                            let start = Date()
                            let data = try await model.pdf()
                            let folder = try Outputs.directory(in: .downloadsDirectory, subfolder: "Satchel")
                            let url = folder.appendingPathComponent("Page-\(Int(Date().timeIntervalSince1970)).pdf")
                            try data.write(to: url)
                            message = "Saved \(url.lastPathComponent)"
                            Outputs.reveal(url)
                            SatchelLog.toolRun(id: ToolID.webPageToPDF.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            }
            Text("A web address is loaded so it can be printed. A local HTML file never leaves this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
    }
}

private struct WebPreview: View {
    @Environment(\.satchelSnapshot) private var snapshot
    let model: WebPDFModel

    var body: some View {
        if snapshot {
            Color(nsColor: .textBackgroundColor)
        } else {
            HiddenWeb(webView: model.webView)
        }
    }
}

private struct HiddenWeb: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

final class WebPDFModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var busy = false
    private var continuation: CheckedContinuation<Data, Error>?
    private var storage: WKWebView?

    var webView: WKWebView {
        if let storage { return storage }
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200), configuration: configuration)
        view.navigationDelegate = self
        storage = view
        return view
    }

    func load(address: String) {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return }
        webView.load(URLRequest(url: url))
    }

    func loadFile(_ url: URL) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func pdf() async throws -> Data {
        busy = true
        defer { busy = false }
        if webView.url == nil && webView.title == nil {
            throw ToolError(message: "Load a page or drop an HTML file first.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                switch result {
                case let .success(data): continuation.resume(returning: data)
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
}
