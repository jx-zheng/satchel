import AppKit
import SwiftUI
import Translation
import SatchelCore

struct TextToolScreen: View {
    let id: ToolID
    var body: some View {
        switch id {
        case .wordCounter: WordCounterTool()
        case .caseConverter: CaseConverterTool()
        case .transcribe: TranscribeTool()
        case .extractText: ExtractTextTool()
        case .captureText: CaptureTextTool()
        case .textToSpeech: SpeechTool()
        case .translate: TranslateTool()
        default:
            if let tool = ToolRegistry.byID[id] { ComingSoonView(tool: tool) }
        }
    }
}

private struct WordCounterTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var logged = false
    var body: some View {
        let count = TextTransforms.count(model.draft(for: .wordCounter))
        ToolPage(tool: ToolRegistry.definition(.wordCounter)) {
            TextEditor(text: model.binding(for: .wordCounter))
                .font(.system(size: 14))
                .frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                stat("Words", count.words)
                stat("Characters", count.characters)
                stat("No spaces", count.charactersNoSpaces)
                stat("Sentences", count.sentences)
                stat("Lines", count.lines)
                stat("Reading", count.readingMinutes == 0 ? "—" : "\(count.readingMinutes) min")
            }
        }
        .onChange(of: model.draft(for: .wordCounter)) { _, text in
            guard !logged, !text.isEmpty else { return }
            logged = true
            SatchelLog.toolRun(id: ToolID.wordCounter.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
        }
    }

    private func stat(_ name: String, _ value: Int) -> some View {
        stat(name, "\(value)")
    }

    private func stat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .semibold))
        }
    }
}

private struct CaseConverterTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var style = TextCase.sentence
    var body: some View {
        let source = model.draft(for: .caseConverter)
        let output = TextTransforms.apply(source, style)
        ToolPage(tool: ToolRegistry.definition(.caseConverter)) {
            Picker("Case", selection: $style) {
                ForEach(TextCase.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            TextEditor(text: model.binding(for: .caseConverter))
                .font(.system(size: 14))
                .frame(minHeight: 140)
            Text(output.isEmpty ? "The converted text shows here." : output)
                .font(.system(size: 14, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            PrimaryButton(title: "Copy", enabled: !output.isEmpty) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
                SatchelLog.toolRun(id: ToolID.caseConverter.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
            }
        }
    }
}

private struct TranscribeTool: View {
    @State private var url: URL?
    @State private var format = "txt"
    @State private var text = ""
    @State private var running = false
    @State private var progress = 0.0
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.transcribe)) {
            DropZone(prompt: "Drop audio or video", types: MediaTypes.audio + MediaTypes.movies, multiple: false) { url = $0.first }
            if let url { Text(url.lastPathComponent).font(.system(size: 12)) }
            Picker("Export", selection: $format) {
                Text("Plain text").tag("txt")
                Text("Timestamps").tag("time")
                Text("SRT").tag("srt")
            }
            .pickerStyle(.segmented)
            Text("Recognition stays on this Mac. Long files are split into short pieces. The first run asks for speech recognition permission.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            PrimaryButton(title: running ? "Transcribing…" : "Transcribe", enabled: url != nil && !running) { run() }
            if running { ProgressView(value: progress) }
            if !text.isEmpty {
                Text(text).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
            }
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func run() {
        guard let url else { return }
        running = true
        text = ""
        let chosen = format
        Task {
            do {
                let start = Date()
                let result = try await SpeechJobs.transcribe(url: url) { progress = $0 }
                let body: String
                let ext: String
                switch chosen {
                case "time": body = result.timestamped; ext = "txt"
                case "srt": body = result.srt; ext = "srt"
                default: body = result.plain; ext = "txt"
                }
                text = body
                let output = try Outputs.make(nextTo: url, suffix: "-transcript", ext: ext)
                try body.write(to: output, atomically: true, encoding: .utf8)
                message = "Saved \(output.lastPathComponent)"
                SatchelLog.toolRun(id: ToolID.transcribe.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
            } catch {
                message = error.localizedDescription
                SatchelLog.toolRun(id: ToolID.transcribe.rawValue, inputs: 1, outcome: "failed", seconds: "0s")
            }
            running = false
        }
    }
}

private struct ExtractTextTool: View {
    @State private var text = ""
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.extractText)) {
            DropZone(prompt: "Drop an image or a PDF", types: MediaTypes.images + MediaTypes.pdfs, multiple: false) { urls in
                guard let url = urls.first else { return }
                Task {
                    do {
                        let start = Date()
                        let found: String
                        if url.pathExtension.lowercased() == "pdf" {
                            found = try OCRJobs.text(fromPDF: url) { _ in }
                        } else {
                            found = try OCRJobs.text(from: ImageFiles.load(url))
                        }
                        text = found
                        let output = try Outputs.make(nextTo: url, suffix: "-text", ext: "txt")
                        try found.write(to: output, atomically: true, encoding: .utf8)
                        message = "Saved \(output.lastPathComponent)"
                        SatchelLog.toolRun(id: ToolID.extractText.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                    } catch { message = error.localizedDescription }
                }
            }
            Text(text).textSelection(.enabled)
            Text(message).foregroundStyle(.secondary)
        }
    }
}

private struct CaptureTextTool: View {
    @State private var text = ""
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.captureText)) {
            Text("Read words from the clipboard or from a picture you drop.")
                .foregroundStyle(.secondary)
            PrimaryButton(title: "Read clipboard", enabled: true) { readPasteboard() }
            DropZone(prompt: "Or drop a picture", types: MediaTypes.images, multiple: false) { urls in
                guard let url = urls.first else { return }
                Task { await recognize(url) }
            }
            Text(text).textSelection(.enabled)
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func readPasteboard() {
        let start = Date()
        guard let image = NSImage(pasteboard: .general),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            message = "The clipboard does not have an image."
            return
        }
        do {
            text = try OCRJobs.text(from: cg)
            message = "Read from the clipboard."
            SatchelLog.toolRun(id: ToolID.captureText.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
        } catch { message = error.localizedDescription }
    }

    private func recognize(_ url: URL) async {
        do {
            let start = Date()
            text = try OCRJobs.text(from: ImageFiles.load(url))
            message = "Read \(url.lastPathComponent)."
            SatchelLog.toolRun(id: ToolID.captureText.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
        } catch { message = error.localizedDescription }
    }
}

private struct SpeechTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var language = "en-US"
    @State private var message = ""
    @State private var running = false
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.textToSpeech)) {
            Picker("Voice", selection: $language) {
                Text("English").tag("en-US")
                Text("Spanish").tag("es-ES")
                Text("French").tag("fr-FR")
                Text("German").tag("de-DE")
                Text("Japanese").tag("ja-JP")
                Text("Chinese").tag("zh-CN")
            }
            TextEditor(text: model.binding(for: .textToSpeech))
                .frame(minHeight: 160)
            PrimaryButton(title: running ? "Speaking…" : "Save audio", enabled: !running) {
                let text = model.draft(for: .textToSpeech)
                let language = language
                running = true
                Task {
                    do {
                        let start = Date()
                        let url = try await SpeechJobs.speak(text: text, language: language) { _ in }
                        message = "Saved \(url.lastPathComponent) in Music/Satchel"
                        SatchelLog.toolRun(id: ToolID.textToSpeech.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                    } catch { message = error.localizedDescription }
                    running = false
                }
            }
            Text(message).foregroundStyle(.secondary)
        }
    }
}

private struct TranslateTool: View {
    @EnvironmentObject private var model: AppModel
    @State private var source = "en"
    @State private var target = "es"
    @State private var output = ""
    @State private var message = ""
    @State private var configuration: TranslationSession.Configuration?

    private let languages = ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh", "nl"]

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.translate)) {
            HStack {
                Picker("From", selection: $source) {
                    ForEach(languages, id: \.self) { Text($0).tag($0) }
                }
                Picker("To", selection: $target) {
                    ForEach(languages, id: \.self) { Text($0).tag($0) }
                }
            }
            TextEditor(text: model.binding(for: .translate))
                .frame(minHeight: 140)
            PrimaryButton(title: "Translate", enabled: !model.draft(for: .translate).isEmpty) {
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target)
                )
                configuration?.invalidate()
            }
            Text(output).textSelection(.enabled)
            Text("Translation uses the languages installed on this Mac. Nothing is typed into a website.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
        .translationTask(configuration) { session in
            let text = await MainActor.run { model.draft(for: .translate) }
            let start = Date()
            do {
                let response = try await session.translate(text)
                await MainActor.run {
                    output = response.targetText
                    message = ""
                    SatchelLog.toolRun(id: ToolID.translate.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    SatchelLog.toolRun(id: ToolID.translate.rawValue, inputs: 1, outcome: "failed", seconds: RunLog.stamp(start))
                }
            }
        }
    }
}
