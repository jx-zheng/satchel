import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SatchelCore

struct DownloadVideoTool: View {
    @State private var link = ""
    @State private var allowPageTool = true
    @State private var running = false
    @State private var progress = 0.0
    @State private var message = ""
    @State private var output: URL?
    @State private var failed = false

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.downloadVideo)) {
            Text(VideoDownload.rights)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.accent.opacity(0.08)))
            TextField("https://…", text: $link)
                .textFieldStyle(.roundedBorder)
            Toggle("Use yt-dlp for a page, if you installed it", isOn: $allowPageTool)
            Text(VideoDownload.ytdlpBinary() == nil
                 ? "yt-dlp is not installed. Direct files and HLS playlists still download."
                 : "yt-dlp was found on this Mac and will be used only for page links.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: running ? "Downloading…" : "Download", enabled: link.contains("://") && !running) {
                run()
            }
            if running {
                ProgressView(value: progress).progressViewStyle(.linear)
            }
            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(failed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let output {
                ResultTray(urls: [output], heading: "Saved in Downloads/Satchel")
            }
        }
    }

    private func run() {
        running = true
        failed = false
        message = ""
        output = nil
        progress = 0
        let current = link
        let pages = allowPageTool
        Task {
            do {
                let folder = try Outputs.directory(in: .downloadsDirectory, subfolder: "Satchel")
                let saved = try await VideoDownload.save(urlString: current, directory: folder, allowPageTool: pages) { value in
                    progress = value
                }
                output = saved
                message = "Saved \(saved.lastPathComponent)."
            } catch {
                failed = true
                message = error.localizedDescription
            }
            running = false
        }
    }
}

struct BurnSubtitlesTool: View {
    @State private var video: URL?
    @State private var srt: URL?
    @State private var running = false
    @State private var progress = 0.0
    @State private var message = ""
    @State private var output: URL?

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.burnSubtitles)) {
            DropZone(prompt: "Drop a video", types: MediaTypes.movies, multiple: false) { video = $0.first; output = nil; message = "" }
            if let video {
                Text(video.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
            }
            DropZone(prompt: "Drop an SRT file", types: [UTType(filenameExtension: "srt") ?? .plainText], multiple: false) { srt = $0.first; output = nil; message = "" }
            if let srt {
                Text(srt.lastPathComponent).font(.callout).lineLimit(1)
            }
            Text("Captions are drawn onto a copy. The original video is left alone. No external converter is used.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: running ? "Burning…" : "Burn in", enabled: video != nil && srt != nil && !running) {
                run()
            }
            if running { ProgressView(value: progress).progressViewStyle(.linear) }
            if !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(output == nil ? Color.red : Color.secondary)
            }
            if let output { ResultTray(urls: [output]) }
        }
        .onAppear {
            guard DemoSession.enabled, DemoSession.take(.burnSubtitles),
                  let files = DemoSession.files[.burnSubtitles], files.count >= 2 else { return }
            video = files[0]
            srt = files[1]
            run()
        }
    }

    private func run() {
        guard let video, let srt else { return }
        running = true
        message = ""
        output = nil
        Task {
            do {
                let made = try await SubtitleBurn.burn(video: video, srt: srt) { progress = $0 }
                output = made
                message = "Saved \(made.lastPathComponent)."
            } catch {
                message = error.localizedDescription
            }
            running = false
        }
    }
}

struct CleanAudioTool: View {
    var body: some View {
        FileJobView(tool: .cleanAudio, types: MediaTypes.audio, prompt: "Drop a voice recording", actionTitle: "Clean", multiple: false) {
            Text("Steady hiss is reduced on this Mac. The cleaned copy is a mono WAV, and the original is kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } perform: { urls, progress in
            try await AudioCleanup.clean(urls: urls, progress: progress)
        }
    }
}

struct PDFToWordTool: View {
    var body: some View {
        FileJobView(tool: .pdfToWord, types: MediaTypes.pdfs, prompt: "Drop a PDF", actionTitle: "Make Word", multiple: false) {
            Text(OfficeDocs.wordNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } perform: { urls, _ in
            guard let url = urls.first else { return [] }
            return [try OfficeDocs.pdfToWord(url: url)]
        }
    }
}

struct ConvertDocumentsTool: View {
    @State private var format = "docx"
    var body: some View {
        FileJobView(tool: .convertDocuments, types: [.plainText, .rtf, .html, UTType(filenameExtension: "docx") ?? .data], prompt: "Drop a text, RTF, HTML, or Word file", actionTitle: "Convert", multiple: false) {
            Picker("Save as", selection: $format) {
                Text("Word").tag("docx")
                Text("RTF").tag("rtf")
                Text("HTML").tag("html")
                Text("Plain text").tag("txt")
            }
            .pickerStyle(.segmented)
            Text(OfficeDocs.convertNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } perform: { urls, _ in
            guard let url = urls.first else { return [] }
            return [try OfficeDocs.convert(url: url, ext: format)]
        }
    }
}

struct PowerPointPDFTool: View {
    var body: some View {
        FileJobView(tool: .powerpointToPDF, types: [UTType(filenameExtension: "pptx") ?? .data], prompt: "Drop a PowerPoint file", actionTitle: "Make PDF", multiple: false) {
            Text(OfficeDocs.powerpointNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } perform: { urls, progress in
            guard let url = urls.first else { return [] }
            return [try await OfficeDocs.powerpoint(url: url, progress: progress)]
        }
    }
}

struct ExcelPDFTool: View {
    var body: some View {
        FileJobView(tool: .excelToPDF, types: [UTType(filenameExtension: "xlsx") ?? .data], prompt: "Drop an Excel file", actionTitle: "Make PDF", multiple: false) {
            Text(OfficeDocs.excelNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } perform: { urls, progress in
            guard let url = urls.first else { return [] }
            return [try await OfficeDocs.excel(url: url, progress: progress)]
        }
    }
}

struct SummarizeTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var summary = ""
    @State private var running = false

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.summarize)) {
            TextEditor(text: model.binding(for: .summarize))
                .font(.body)
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))
            Text("Apple Intelligence is used when it is turned on. Otherwise Satchel keeps the most repeated sentences. Nothing is uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: running ? "Summarizing…" : "Summarize", enabled: !model.draft(for: .summarize).isEmpty && !running) {
                run()
            }
            if running { ProgressView().controlSize(.small) }
            if !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary, forType: .string)
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            guard DemoSession.enabled, DemoSession.take(.summarize), !model.draft(for: .summarize).isEmpty else { return }
            run()
        }
    }

    private func run() {
        let text = model.draft(for: .summarize)
        running = true
        Task {
            summary = await Summaries.make(text)
            running = false
        }
    }
}

struct AskDocumentTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var question = ""
    @State private var answer = ""
    @State private var running = false

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.askDocument)) {
            Text("Document")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: model.binding(for: .askDocument))
                .font(.body)
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))
            TextField("Question", text: $question)
                .textFieldStyle(.roundedBorder)
            Text("The answer comes from this document on your Mac. A passage is chosen by overlap, or by the on-device model when it is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: running ? "Looking…" : "Ask", enabled: !question.isEmpty && !model.draft(for: .askDocument).isEmpty && !running) {
                run()
            }
            if !answer.isEmpty {
                Text(answer)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func run() {
        let document = model.draft(for: .askDocument)
        let asked = question
        running = true
        Task {
            answer = await DocumentQA.answer(question: asked, document: document)
            running = false
        }
    }
}

struct DisplayControlTool: View {
    @State private var lines: [DisplayModeLine] = []
    @State private var brightness: Float?
    @State private var original: Float?
    @State private var slider: Double = 0.5
    @State private var message = "Reading this display…"
    @State private var changed = false

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.displayControl)) {
            Text("Modes are listed so you can see what the Mac reports. Resolution stays in System Settings, so a click here cannot blank the screen. Brightness changes only when the display exposes a control, and Restore puts the previous value back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if lines.isEmpty {
                Text(message).font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { line in
                        HStack {
                            Text(line.text)
                                .font(.body)
                                .lineLimit(1)
                            Spacer()
                            if line.current {
                                Text("Current")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            }
            if brightness != nil {
                HStack {
                    Text("Brightness")
                    Slider(value: $slider, in: 0...1)
                }
                HStack {
                    PrimaryButton(title: "Apply", enabled: true) { apply() }
                    Button("Restore") { restore() }
                        .buttonStyle(.borderless)
                        .disabled(!changed)
                }
            } else if !lines.isEmpty {
                Text("This display did not expose a brightness control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !message.isEmpty, !lines.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { refresh() }
        .onDisappear { restore() }
    }

    private func refresh() {
        do {
            let reading = try DisplayDesk.read()
            lines = reading.modes
            brightness = reading.brightness
            if let brightness {
                slider = Double(brightness)
                if original == nil { original = brightness }
            }
            message = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply() {
        do {
            if original == nil { original = brightness }
            try DisplayDesk.setBrightness(Float(slider))
            changed = true
            message = "Brightness updated."
            refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() {
        guard changed, let original else { return }
        try? DisplayDesk.setBrightness(original)
        changed = false
        slider = Double(original)
    }
}
