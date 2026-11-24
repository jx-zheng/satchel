import SwiftUI
import SatchelCore

struct ToolArt: View {
    let tool: ToolDefinition
    var compact = false

    var body: some View {
        PreviewTile {
            ToolScene(id: tool.id)
                .scaleEffect(compact ? 0.82 : 1, anchor: .center)
        }
    }
}

private struct PreviewTile<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.20) : Color(white: 0.945))
            content()
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum Ink {
    static let accent = Color(red: 0.23, green: 0.48, blue: 0.95)
    static let good = Color(red: 0.18, green: 0.62, blue: 0.42)
}

private struct FileChip: View {
    var title: String
    var detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11, weight: .semibold))
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

private struct MiniPill: View {
    var text: String
    var tint: Color = Ink.good
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}

private struct MiniArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct GaugeMark: View {
    var value: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 6)
            Circle()
                .trim(from: 0.15, to: 0.72)
                .stroke(Ink.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(90))
            Text(value).font(.system(size: 11, weight: .bold))
        }
        .frame(width: 64, height: 64)
    }
}

private struct FilmstripMark: View {
    var handles: Bool = false
    var body: some View {
        HStack(spacing: 3) {
            if handles { Capsule().fill(Ink.accent).frame(width: 4, height: 28) }
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 22, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08)).padding(3))
            }
            if handles { Capsule().fill(Ink.accent).frame(width: 4, height: 28) }
        }
    }
}

private struct WaveformMark: View {
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<18, id: \.self) { index in
                let height = 8 + (index * 7 % 22)
                Capsule()
                    .fill(index == 8 || index == 9 ? Ink.accent : Color.primary.opacity(0.28))
                    .frame(width: 3, height: CGFloat(height))
            }
        }
        .frame(height: 36)
    }
}

private struct PageStackMark: View {
    var badge: String? = nil
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.10)).frame(width: 36, height: 46).offset(x: 8, y: -6)
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.16)).frame(width: 36, height: 46).offset(x: 4, y: -3)
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)).frame(width: 40, height: 50)
                .overlay(
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(0..<4, id: \.self) { _ in
                            Capsule().fill(Color.primary.opacity(0.25)).frame(height: 3)
                        }
                    }
                    .padding(6)
                )
            if let badge {
                MiniPill(text: badge, tint: Ink.accent).offset(x: 10, y: -8)
            }
        }
        .frame(width: 70, height: 60)
    }
}

private struct BarRows: View {
    var rows: [(String, CGFloat)]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Text(row.0).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Ink.accent.opacity(0.85)).frame(width: proxy.size.width * row.1)
                    }
                    .frame(height: 6)
                }
            }
        }
    }
}

private struct ToggleRows: View {
    var labels: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                HStack {
                    Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Capsule()
                        .fill(index == 0 ? Ink.accent : Color.primary.opacity(0.12))
                        .frame(width: 22, height: 12)
                        .overlay(alignment: index == 0 ? .trailing : .leading) {
                            Circle().fill(.white).frame(width: 8, height: 8).padding(2)
                        }
                }
            }
        }
    }
}

private struct CodeSnippet: View {
    var lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(line.contains("{") || line.contains("\"") ? Ink.accent : Color.primary.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QRGlyph: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 1)
                            .fill((row + column) % 2 == 0 || row == 0 || column == 0 ? Color.primary.opacity(0.75) : Color.clear)
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

private struct BatteryMark: View {
    var percent: String
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.35), lineWidth: 1.5).frame(width: 46, height: 22)
                RoundedRectangle(cornerRadius: 2).fill(Ink.good).frame(width: 28, height: 14).padding(.leading, 3)
                RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.35)).frame(width: 3, height: 8).offset(x: 26)
            }
            Text(percent).font(.system(size: 13, weight: .bold))
        }
    }
}

private struct KeyValues: View {
    var rows: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0).font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).font(.system(size: 9, weight: .semibold))
                }
            }
        }
    }
}

private struct CupTimer: View {
    var time: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.primary.opacity(0.45))
            Text(time).font(.system(size: 16, weight: .bold, design: .rounded))
        }
    }
}

private struct ToolScene: View {
    let id: ToolID

    var body: some View {
        switch id {
        case .downloadVideo: chips("MP4", "1080p", "MOV", "Best")
        case .burnSubtitles: HStack { FilmstripMark(); MiniPill(text: "SRT", tint: Ink.accent) }
        case .changeSpeed: GaugeMark(value: "2×")
        case .extractFrames: FilmstripMark()
        case .recordScreen: HStack { RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2)).frame(width: 70, height: 46); MiniPill(text: "REC", tint: .red) }
        case .compressVideo: HStack(spacing: 6) { FileChip(title: "MOV", detail: "1.4 GB"); MiniArrow(); FileChip(title: "MP4", detail: "180 MB"); MiniPill(text: "-87%") }
        case .convertVideo: HStack(spacing: 6) { FileChip(title: "MOV", detail: "2.4 GB"); MiniArrow(); FileChip(title: "MP4", detail: "Web ready") }
        case .resizeVideo: HStack { FileChip(title: "1920", detail: "wide"); MiniArrow(); FileChip(title: "1280", detail: "wide") }
        case .cropRotateVideo: HStack { FilmstripMark(handles: true); Image(systemName: "crop").foregroundStyle(Ink.accent) }
        case .mediaInfo: KeyValues(rows: [("Duration", "0:42"), ("Size", "1920×800"), ("FPS", "60")])
        case .trimVideo: FilmstripMark(handles: true)
        case .mergeVideos: FilmstripMark()
        case .muteVideo: HStack { FilmstripMark(); Image(systemName: "speaker.slash.fill").foregroundStyle(.secondary) }
        case .replaceAudio: HStack { FilmstripMark(); WaveformMark().frame(width: 70) }
        case .videoToGIF: HStack { FilmstripMark(); MiniPill(text: "GIF", tint: Ink.accent) }
        case .cleanAudio: WaveformMark()
        case .recordAudio: HStack { Image(systemName: "mic.fill").foregroundStyle(Ink.accent); WaveformMark() }
        case .trimAudio: HStack { WaveformMark(); Capsule().fill(Ink.accent).frame(width: 36, height: 4) }
        case .extractAudio: HStack { FilmstripMark(); MiniArrow(); WaveformMark().frame(width: 60) }
        case .convertAudio: chips("M4A", "AAC", "WAV", "PCM")
        case .screenshot: RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2)).frame(width: 88, height: 56).overlay(Image(systemName: "camera.viewfinder").foregroundStyle(Ink.accent))
        case .blurFaces: HStack(spacing: 8) { Circle().fill(Color.primary.opacity(0.15)).frame(width: 28).blur(radius: 1); Circle().fill(Ink.accent.opacity(0.35)).frame(width: 28).blur(radius: 3) }
        case .beautifyScreenshot: RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)).frame(width: 100, height: 64).overlay(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.12)).padding(10).shadow(radius: 3))
        case .removeBackground: HStack { Circle().fill(Ink.accent.opacity(0.8)).frame(width: 28); RoundedRectangle(cornerRadius: 4).stroke(style: StrokeStyle(lineWidth: 1, dash: [3])).frame(width: 36, height: 36) }
        case .convertImages: chips("HEIC", "photo", "PNG", "flat")
        case .compressImages: HStack { FileChip(title: "JPEG", detail: "4.2 MB"); MiniArrow(); MiniPill(text: "-62%") }
        case .resizeImages: HStack { FileChip(title: "4000", detail: "px"); MiniArrow(); FileChip(title: "1600", detail: "px") }
        case .rotateImages: Image(systemName: "rotate.right").font(.system(size: 28)).foregroundStyle(Ink.accent)
        case .removeMetadata: KeyValues(rows: [("GPS", "removed"), ("Camera", "removed"), ("Date", "removed")])
        case .colorPicker: HStack(spacing: 8) { Circle().fill(Ink.accent).frame(width: 28); Text("#3B7AF2").font(.system(size: 13, weight: .bold, design: .monospaced)) }
        case .redactImage: ZStack { RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).frame(width: 90, height: 56); Rectangle().fill(Color.primary.opacity(0.8)).frame(width: 36, height: 12) }
        case .annotateScreenshot: HStack { RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2)).frame(width: 70, height: 48); Image(systemName: "pencil.tip").foregroundStyle(Ink.accent) }
        case .watermark: Text("DRAFT").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.primary.opacity(0.35)).rotationEffect(.degrees(-12))
        case .scanDocument: PageStackMark(badge: "PDF")
        case .redactPDF: PageStackMark(badge: "cut")
        case .fillForms: KeyValues(rows: [("Name", "Ada"), ("Date", "filled")])
        case .searchablePDF: HStack { PageStackMark(); Image(systemName: "text.viewfinder").foregroundStyle(Ink.accent) }
        case .pdfToWord: HStack { PageStackMark(); MiniArrow(); FileChip(title: "DOC", detail: "edit") }
        case .signPDF: HStack { PageStackMark(); Text("Ada").font(.system(size: 16, weight: .medium, design: .serif)).italic().foregroundStyle(Ink.accent) }
        case .mergePDFs: HStack(spacing: -8) { PageStackMark(); PageStackMark() }
        case .splitPDF: HStack { PageStackMark(); MiniArrow(); PageStackMark() }
        case .organizePDF: PageStackMark(badge: "1·3·2")
        case .deletePages: PageStackMark(badge: "−2")
        case .extractPages: PageStackMark(badge: "p.4")
        case .imagesToPDF: HStack { Image(systemName: "photo").foregroundStyle(.secondary); MiniArrow(); PageStackMark() }
        case .cropPDF: PageStackMark(badge: "trim")
        case .compressPDF: HStack { PageStackMark(); MiniPill(text: "-40%") }
        case .addPassword: HStack { PageStackMark(); Image(systemName: "lock.fill").foregroundStyle(Ink.accent) }
        case .removePassword: HStack { PageStackMark(); Image(systemName: "lock.open.fill").foregroundStyle(.secondary) }
        case .pdfToImages: HStack { PageStackMark(); MiniArrow(); Image(systemName: "photo.on.rectangle").foregroundStyle(Ink.accent) }
        case .convertDocuments: chips("DOC", "file", "PDF", "page")
        case .wordToPDF: HStack { FileChip(title: "DOCX", detail: "notes"); MiniArrow(); PageStackMark() }
        case .powerpointToPDF: HStack { FileChip(title: "PPT", detail: "slides"); MiniArrow(); PageStackMark() }
        case .excelToPDF: HStack { FileChip(title: "XLS", detail: "sheet"); MiniArrow(); PageStackMark() }
        case .webPageToPDF: HStack { Image(systemName: "globe").foregroundStyle(Ink.accent); MiniArrow(); PageStackMark() }
        case .markdownToPDF: HStack { CodeSnippet(lines: ["# Notes", "- item"]); MiniArrow(); PageStackMark() }
        case .transcribe: HStack { WaveformMark().frame(width: 70); CodeSnippet(lines: ["0:01 hello", "0:04 there"]) }
        case .summarize: CodeSnippet(lines: ["Long note…", "→ three lines"])
        case .extractText: HStack { Image(systemName: "text.viewfinder").foregroundStyle(Ink.accent); CodeSnippet(lines: ["HELLO", "page 2"]) }
        case .captureText: HStack { Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary); CodeSnippet(lines: ["pasted", "text"]) }
        case .translate: HStack { CodeSnippet(lines: ["Hello"]); MiniArrow(); CodeSnippet(lines: ["Hola"]) }
        case .textToSpeech: HStack { CodeSnippet(lines: ["Say this"]); Image(systemName: "speaker.wave.2.fill").foregroundStyle(Ink.accent) }
        case .askDocument: HStack { PageStackMark(); CodeSnippet(lines: ["Q: when?", "A: page 2"]) }
        case .wordCounter: KeyValues(rows: [("Words", "128"), ("Lines", "12"), ("Read", "1 min")])
        case .caseConverter: CodeSnippet(lines: ["hello world", "helloWorld"])
        case .qrCode: QRGlyph()
        case .batchRename: VStack(alignment: .leading, spacing: 4) { Text("IMG_2044.jpg").font(.system(size: 9)).foregroundStyle(.secondary); Text("trip-01.jpg").font(.system(size: 11, weight: .semibold)) }
        case .findDuplicates: VStack(alignment: .leading, spacing: 3) { FileChip(title: "a.png", detail: "same"); FileChip(title: "a copy.png", detail: "same") }
        case .zipUnzip: HStack { FileChip(title: "ZIP", detail: "archive"); MiniArrow(); FileChip(title: "files", detail: "unpacked") }
        case .organizeDownloads: BarRows(rows: [("Images", 0.7), ("Docs", 0.4), ("Video", 0.55)])
        case .networkSpeed: GaugeMark(value: "148")
        case .clipboardHistory: VStack(alignment: .leading, spacing: 4) { Text("copied line").font(.system(size: 10)); Text("older line").font(.system(size: 10)).foregroundStyle(.secondary) }
        case .storageExplorer: BarRows(rows: [("Xcode", 0.82), ("Caches", 0.46), ("Logs", 0.22)])
        case .wifiPassword: HStack { QRGlyph(); CodeSnippet(lines: ["Home", "••••"]) }
        case .diskSpeed: KeyValues(rows: [("Write", "920 MB/s"), ("Read", "1.4 GB/s")])
        case .batteryHealth: VStack(alignment: .leading, spacing: 6) { BatteryMark(percent: "86%"); KeyValues(rows: [("Cycles", "412"), ("Power", "30 W")]) }
        case .keepAwake: CupTimer(time: "0:59:42")
        case .uninstallApp: HStack { FileChip(title: "App", detail: "trash"); Image(systemName: "trash").foregroundStyle(.secondary) }
        case .presentationMode: ToggleRows(labels: ["Desktop", "Dock", "Awake"])
        case .cleanKeyboard: HStack { Image(systemName: "keyboard").font(.system(size: 26)).foregroundStyle(.secondary); MiniPill(text: "paused", tint: Ink.accent) }
        case .deadPixel:
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    let colors: [Color] = [.black, .white, .red, .green, .blue]
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colors[index])
                        .frame(width: 14, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.15)))
                }
            }
        case .ejectDisks: HStack { Image(systemName: "eject.fill").foregroundStyle(Ink.accent); FileChip(title: "USB", detail: "eject") }
        case .loginItems: ToggleRows(labels: ["Helper", "Agent", "Updater"])
        case .fixDamaged: HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); MiniPill(text: "cleared", tint: Ink.good) }
        case .resetPermissions: ToggleRows(labels: ["Mic", "Camera"])
        case .hiddenSettings: ToggleRows(labels: ["Hidden", "Path bar"])
        case .displayControl: HStack { Image(systemName: "display").font(.system(size: 26)).foregroundStyle(.secondary); BarRows(rows: [("Bright", 0.6)]) }
        case .mouseFixes: HStack { Image(systemName: "computermouse.fill").foregroundStyle(.secondary); KeyValues(rows: [("Scroll", "natural"), ("Speed", "1.5")]) }
        case .jsonFormatter: CodeSnippet(lines: ["{", "  \"a\": 2", "}"])
        case .base64: CodeSnippet(lines: ["hi", "aGk="])
        case .hashGenerator: CodeSnippet(lines: ["SHA-256", "ba7816…"])
        case .uuidGenerator: CodeSnippet(lines: ["4F2A…-…", "version 4"])
        case .jwtDecoder: CodeSnippet(lines: ["eyJhbG…", "sub: satchel"])
        case .timestamp: CodeSnippet(lines: ["1700000000", "2023-11-14"])
        case .diffChecker: CodeSnippet(lines: ["- old line", "+ new line"])
        case .regexTester: CodeSnippet(lines: ["id=(\\d+)", "match 4, 12"])
        case .cleanLinks: CodeSnippet(lines: ["?utm_source", "id=3 kept"])
        case .coordinatePicker: CodeSnippet(lines: ["37.77, -122", "37°46' N"])
        case .unicodeInspector: CodeSnippet(lines: ["A", "U+0041"])
        case .loremIpsum: CodeSnippet(lines: ["Lorem ipsum", "dolor sit"])
        case .passwordGenerator: CodeSnippet(lines: ["••••••••", "20 chars"])
        case .csvJSON: CodeSnippet(lines: ["name,qty", "[{name}]"])
        }
    }

    private func chips(_ a: String, _ ad: String, _ b: String, _ bd: String) -> some View {
        HStack(spacing: 6) { FileChip(title: a, detail: ad); MiniArrow(); FileChip(title: b, detail: bd) }
    }
}
