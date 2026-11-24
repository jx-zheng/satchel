import AppKit
import ScreenCaptureKit
import SwiftUI
import SatchelCore

struct ImageToolScreen: View {
    let id: ToolID
    var body: some View {
        switch id {
        case .convertImages: ConvertImagesTool()
        case .compressImages: CompressImagesTool()
        case .resizeImages: ResizeImagesTool()
        case .rotateImages: RotateImagesTool()
        case .removeMetadata: StripMetadataTool()
        case .removeBackground: RemoveBackgroundTool()
        case .blurFaces: BlurFacesTool()
        case .watermark: WatermarkTool()
        case .beautifyScreenshot: BeautifyTool()
        case .redactImage: RedactImageTool()
        case .annotateScreenshot: AnnotateTool()
        case .colorPicker: ColorPickerTool()
        case .screenshot: ScreenshotTool()
        default:
            if let tool = ToolRegistry.byID[id] { ComingSoonView(tool: tool) }
        }
    }
}

private struct ConvertImagesTool: View {
    @State private var format = "jpg"
    var body: some View {
        FileJobView(tool: .convertImages, types: MediaTypes.images, prompt: "Drop pictures", actionTitle: "Convert") {
            Picker("Format", selection: $format) {
                Text("JPEG").tag("jpg")
                Text("PNG").tag("png")
                Text("TIFF").tag("tiff")
                Text("HEIC").tag("heic")
                Text("GIF").tag("gif")
            }
            .pickerStyle(.segmented)
        } perform: { urls, progress in
            try await ImageJobs.convert(urls: urls, ext: format, progress: progress)
        }
    }
}

private struct CompressImagesTool: View {
    @State private var quality = 0.7
    var body: some View {
        FileJobView(tool: .compressImages, types: MediaTypes.images, prompt: "Drop pictures", actionTitle: "Compress", tracksSavings: true) {
            HStack {
                Text("Quality")
                Slider(value: $quality, in: 0.35...0.9)
                Text("\(Int(quality * 100))%")
            }
        } perform: { urls, progress in
            try await ImageJobs.compress(urls: urls, quality: quality, progress: progress)
        }
    }
}

private struct ResizeImagesTool: View {
    @State private var edge = "1600"
    var body: some View {
        FileJobView(tool: .resizeImages, types: MediaTypes.images, prompt: "Drop pictures", actionTitle: "Resize") {
            TextField("Longest side in pixels", text: $edge).frame(width: 180)
        } perform: { urls, progress in
            try await ImageJobs.resize(urls: urls, maxEdge: Int(edge) ?? 1600, progress: progress)
        }
    }
}

private struct RotateImagesTool: View {
    @State private var turns = 1
    @State private var flip = false
    var body: some View {
        FileJobView(tool: .rotateImages, types: MediaTypes.images, prompt: "Drop pictures", actionTitle: "Rotate") {
            Picker("Turn", selection: $turns) {
                Text("90°").tag(1)
                Text("180°").tag(2)
                Text("270°").tag(3)
            }
            .pickerStyle(.segmented)
            Toggle("Flip horizontally", isOn: $flip)
        } perform: { urls, progress in
            try await ImageJobs.rotate(urls: urls, quarterTurns: turns, flip: flip, progress: progress)
        }
    }
}

private struct StripMetadataTool: View {
    var body: some View {
        FileJobView(tool: .removeMetadata, types: MediaTypes.images, prompt: "Drop pictures", actionTitle: "Strip details") {
            Text("Location, camera, and date fields are left out of the new file.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } perform: { urls, progress in
            try await ImageJobs.stripMetadata(urls: urls, progress: progress)
        }
    }
}

private struct RemoveBackgroundTool: View {
    @State private var choice = 0
    @State private var crop = true
    var body: some View {
        FileJobView(tool: .removeBackground, types: MediaTypes.images, prompt: "Drop a photo", actionTitle: "Remove background") {
            Picker("Background", selection: $choice) {
                Text("Clear").tag(0)
                Text("White").tag(1)
                Text("Black").tag(2)
            }
            .pickerStyle(.segmented)
            Toggle("Crop to the subject", isOn: $crop)
        } perform: { urls, progress in
            let background: ImageJobs.BackgroundChoice = choice == 1 ? .white : (choice == 2 ? .color(.black) : .clear)
            return try await ImageJobs.removeBackground(urls: urls, background: background, crop: crop, progress: progress)
        }
    }
}

private struct BlurFacesTool: View {
    @State private var style = ImageJobs.FaceStyle.blur
    var body: some View {
        FileJobView(tool: .blurFaces, types: MediaTypes.images, prompt: "Drop photos", actionTitle: "Cover faces") {
            Picker("Style", selection: $style) {
                ForEach(ImageJobs.FaceStyle.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
        } perform: { urls, progress in
            try await ImageJobs.blurFaces(urls: urls, style: style, progress: progress)
        }
    }
}

private struct WatermarkTool: View {
    @State private var text = "Draft"
    var body: some View {
        FileJobView(tool: .watermark, types: MediaTypes.images, prompt: "Drop pictures", actionTitle: "Stamp text") {
            TextField("Watermark", text: $text)
        } perform: { urls, progress in
            try await ImageJobs.watermark(urls: urls, text: text, progress: progress)
        }
    }
}

private struct BeautifyTool: View {
    @State private var url: URL?
    @State private var padding = 64.0
    @State private var radius = 24.0
    @State private var shadow = true
    @State private var aspect = "16:9"
    @State private var message = ""
    @State private var output: URL?
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.beautifyScreenshot)) {
            DropZone(prompt: "Drop a screenshot", types: MediaTypes.images, multiple: false) { url = $0.first }
            HStack {
                Text("Padding")
                Slider(value: $padding, in: 0...160)
            }
            HStack {
                Text("Corner radius")
                Slider(value: $radius, in: 0...64)
            }
            Toggle("Shadow", isOn: $shadow)
            Picker("Frame", selection: $aspect) {
                Text("Free").tag("free")
                Text("16:9").tag("16:9")
                Text("4:5").tag("4:5")
                Text("1:1").tag("1:1")
            }
            .pickerStyle(.segmented)
            PrimaryButton(title: "Save framed PNG", enabled: url != nil) { run() }
            Text(message).foregroundStyle(.secondary)
            if let output { Button("Reveal in Finder") { Outputs.reveal(output) } }
        }
    }

    private func run() {
        guard let url else { return }
        let ratio: CGSize? = {
            switch aspect {
            case "16:9": return CGSize(width: 16, height: 9)
            case "4:5": return CGSize(width: 4, height: 5)
            case "1:1": return CGSize(width: 1, height: 1)
            default: return nil
            }
        }()
        do {
            let start = Date()
            let made = try ImageJobs.beautify(url: url, padding: padding, radius: radius, shadow: shadow, aspect: ratio, background: .init(calibratedWhite: 0.94, alpha: 1))
            output = made
            message = "Saved \(made.lastPathComponent)"
            SatchelLog.toolRun(id: ToolID.beautifyScreenshot.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
        } catch {
            message = error.localizedDescription
            SatchelLog.toolRun(id: ToolID.beautifyScreenshot.rawValue, inputs: 1, outcome: "failed", seconds: "0s")
        }
    }
}

private struct RedactImageTool: View {
    @State private var url: URL?
    @State private var image: NSImage?
    @State private var rects: [CGRect] = []
    @State private var message = ""

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.redactImage)) {
            DropZone(prompt: "Drop a picture", types: MediaTypes.images, multiple: false) { urls in
                url = urls.first
                if let url, let loaded = NSImage(contentsOf: url) { image = loaded }
                rects = []
            }
            if let image {
                GeometryReader { proxy in
                    let fitted = fit(image.size, in: proxy.size)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image).resizable().frame(width: fitted.width, height: fitted.height)
                        ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                            Rectangle().fill(Color.black)
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 2).onEnded { value in
                        let rect = CGRect(
                            x: min(value.startLocation.x, value.location.x),
                            y: min(value.startLocation.y, value.location.y),
                            width: abs(value.location.x - value.startLocation.x),
                            height: abs(value.location.y - value.startLocation.y)
                        )
                        if rect.width > 4, rect.height > 4 { rects.append(rect) }
                    })
                }
                .frame(height: 320)
                .background(Color.black.opacity(0.05))
            }
            PrimaryButton(title: "Save covered copy", enabled: url != nil && !rects.isEmpty) { save() }
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func fit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        let scale = min(bounds.width / max(size.width, 1), 320 / max(size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func save() {
        guard let url, let image else { return }
        let start = Date()
        do {
            let cg = try ImageFiles.load(url)
            guard let context = CGContext(
                data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height)))
            context.setFillColor(NSColor.black.cgColor)
            let viewHeight: CGFloat = 320
            let scale = CGFloat(cg.height) / max(image.size.height * min(1, viewHeight / image.size.height), 1)
            let display = fit(image.size, in: CGSize(width: 800, height: 320))
            let sx = CGFloat(cg.width) / max(display.width, 1)
            let sy = CGFloat(cg.height) / max(display.height, 1)
            for rect in rects {
                let flipped = CGRect(x: rect.minX * sx, y: CGFloat(cg.height) - (rect.minY + rect.height) * sy, width: rect.width * sx, height: rect.height * sy)
                context.fill(flipped)
            }
            guard let out = context.makeImage() else { return }
            let output = try Outputs.make(nextTo: url, suffix: "-redacted", ext: "png")
            try ImageFiles.write(out, to: output, type: .png, quality: nil)
            message = "Saved \(output.lastPathComponent)"
            SatchelLog.toolRun(id: ToolID.redactImage.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
            _ = viewHeight
            _ = scale
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct AnnotateTool: View {
    @State private var url: URL?
    @State private var note = "Note"
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.annotateScreenshot)) {
            DropZone(prompt: "Drop an image", types: MediaTypes.images, multiple: false) { url = $0.first }
            TextField("Caption", text: $note)
            PrimaryButton(title: "Save with caption", enabled: url != nil) { save() }
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let url else { return }
        let caption = note
        Task {
            do {
                let start = Date()
                let made = try await ImageJobs.watermark(urls: [url], text: caption) { _ in }
                message = "Saved \(made.first?.lastPathComponent ?? "the image")"
                SatchelLog.toolRun(id: ToolID.annotateScreenshot.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

private struct ColorPickerTool: View {
    @State private var color = NSColor.systemBlue
    @State private var hex = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.colorPicker)) {
            Text("Sample any pixel on the screen. The value stays on this Mac.")
                .foregroundStyle(.secondary)
            PrimaryButton(title: "Pick a color", enabled: true) {
                NSColorSampler().show { picked in
                    guard let picked else { return }
                    color = picked
                    hex = hexString(picked)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hex, forType: .string)
                    SatchelLog.toolRun(id: ToolID.colorPicker.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
                }
            }
            if !hex.isEmpty {
                HStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: color)).frame(width: 48, height: 48)
                    Text(hex).font(.system(size: 20, weight: .semibold, design: .monospaced))
                    Text("Copied").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func hexString(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}

private struct ScreenshotTool: View {
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.screenshot)) {
            Text("Captures the main display. macOS asks for screen recording permission the first time.")
                .foregroundStyle(.secondary)
            PrimaryButton(title: "Capture display", enabled: true) {
                Task { await capture() }
            }
            Text(message)
        }
    }

    private func capture() async {
        let start = Date()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw ToolError(message: "No display.") }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let folder = try Outputs.directory(in: .desktopDirectory, subfolder: "Satchel")
            let url = folder.appendingPathComponent("Screenshot-\(Int(Date().timeIntervalSince1970)).png")
            try ImageFiles.write(image, to: url, type: .png, quality: nil)
            message = "Saved \(url.lastPathComponent)"
            Outputs.reveal(url)
            SatchelLog.toolRun(id: ToolID.screenshot.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
        } catch {
            message = error.localizedDescription
            SatchelLog.toolRun(id: ToolID.screenshot.rawValue, inputs: 1, outcome: "failed", seconds: RunLog.stamp(start))
        }
    }
}
