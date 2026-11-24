import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Translation

struct SkipSignal: Error {
    var reason: String
}

enum BundleFixture {
    static func copy(name: String, ext: String, to folder: URL) throws -> URL {
        let source = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        guard let source else { throw ToolError(message: "missing bundled \(name).\(ext)") }
        let dest = folder.appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }
}

enum ColorSample {
    static func hex(image: CGImage, x: Int, y: Int) -> String {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return "" }
        let width = image.width
        let height = image.height
        guard x >= 0, y >= 0, x < width, y < height else { return "" }
        let row = image.bytesPerRow
        let offset = y * row + x * 4
        let red = bytes[offset]
        let green = bytes[offset + 1]
        let blue = bytes[offset + 2]
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func swatch(color: (UInt8, UInt8, UInt8), to url: URL) throws {
        let width = 64
        let height = 64
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ToolError(message: "could not draw a color swatch") }
        context.setFillColor(CGColor(red: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255, blue: CGFloat(color.2) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw ToolError(message: "could not draw a color swatch") }
        try ImageFiles.write(image, to: url, type: .png, quality: nil)
    }
}

enum DefaultsLab {
    static let domain = "com.kevinzheng.satchel.selftest"

    static func roundTrip() throws {
        let write = Commands.run("/usr/bin/defaults", ["write", domain, "probe", "-bool", "true"])
        if write.status != 0 { throw ToolError(message: write.output.isEmpty ? "defaults write failed" : write.output) }
        let read = Commands.run("/usr/bin/defaults", ["read", domain, "probe"])
        if !read.output.contains("1") { throw ToolError(message: "defaults did not keep the probe value") }
        let speed = Commands.run("/usr/bin/defaults", ["write", domain, "pointer-speed", "-float", "1.25"])
        if speed.status != 0 { throw ToolError(message: speed.output.isEmpty ? "defaults float write failed" : speed.output) }
        let speedRead = Commands.run("/usr/bin/defaults", ["read", domain, "pointer-speed"])
        if !speedRead.output.contains("1.25") { throw ToolError(message: "defaults did not keep the pointer speed") }
        _ = Commands.run("/usr/bin/defaults", ["delete", domain])
    }
}

enum AppLab {
    static func dummyApp(in folder: URL) throws -> URL {
        let app = folder.appendingPathComponent("SatchelProbe.app", isDirectory: true)
        let macos = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.kevinzheng.satchel.probe</string>
        <key>CFBundleName</key><string>Satchel Probe</string>
        <key>CFBundleExecutable</key><string>probe</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        let executable = macos.appendingPathComponent("probe")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return app
    }

    static func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    static func clearQuarantine(_ url: URL) throws {
        let stamp = Commands.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0083;00000000;Satchel;selftest", url.path])
        if stamp.status != 0 { throw ToolError(message: stamp.output.isEmpty ? "could not set a quarantine flag" : stamp.output) }
        let cleared = Commands.run("/usr/bin/xattr", ["-d", "com.apple.quarantine", url.path])
        if cleared.status != 0 { throw ToolError(message: cleared.output.isEmpty ? "could not clear quarantine" : cleared.output) }
    }
}

enum SpeechFixture {
    static func say(_ text: String, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, text]
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw SkipSignal(reason: "speech synthesis timed out")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
            throw SkipSignal(reason: "speech synthesis is unavailable")
        }
    }
}

enum ScreenGrab {
    static func capture(to folder: URL) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw ToolError(message: "No display.") }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("screenshot-\(Int(Date().timeIntervalSince1970)).png")
        try ImageFiles.write(image, to: url, type: .png, quality: nil)
        return url
    }
}

enum PhotoPDF {
    static func write(to url: URL, pages: Int, width: Int = 1400, height: Int = 900) throws {
        var images: [CGImage] = []
        for index in 0..<pages {
            images.append(try page(index: index, width: width, height: height))
        }
        try PDFJobs.writeImages(images, to: url, pageBox: nil)
    }

    private static func page(index: Int, width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ToolError(message: "could not draw a photo page") }
        var pixel = [UInt8](repeating: 255, count: width * 4)
        for x in 0..<width {
            let wave = UInt8((x * 17 + index * 40) % 220)
            pixel[x * 4] = wave
            pixel[x * 4 + 1] = UInt8((x * 9 + index * 13) % 200)
            pixel[x * 4 + 2] = UInt8(80 + (index * 20) % 140)
            pixel[x * 4 + 3] = 255
        }
        if let data = context.data {
            let rowBytes = context.bytesPerRow
            let base = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
            for y in 0..<height {
                pixel.withUnsafeBytes { raw in
                    base.advanced(by: y * rowBytes).update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: width * 4)
                }
            }
        }
        let line = "Satchel page \(index + 1)" as NSString
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        line.draw(at: NSPoint(x: 48, y: 48), withAttributes: [
            .font: NSFont.systemFont(ofSize: 42, weight: .bold),
            .foregroundColor: NSColor.white
        ])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw ToolError(message: "could not finish a photo page") }
        return image
    }
}

@MainActor
enum TranslateProbe {
    static func tryPhrase() async throws -> String {
        let availability = LanguageAvailability()
        let status = await availability.status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "es"))
        switch status {
        case .installed:
            break
        case .unsupported:
            throw SkipSignal(reason: "translation between English and Spanish is not supported")
        case .supported:
            throw SkipSignal(reason: "no translation model is installed")
        @unknown default:
            throw SkipSignal(reason: "no translation model is installed")
        }
        return try await withCheckedThrowingContinuation { continuation in
            let host = ProbeHost { continuation.resume(with: $0) }
            host.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                host.finish(.failure(SkipSignal(reason: "translation did not finish")))
            }
        }
    }
}

private final class ProbeHost: NSObject {
    let done: (Result<String, Error>) -> Void
    var window: NSWindow?
    var finished = false

    init(done: @escaping (Result<String, Error>) -> Void) {
        self.done = done
    }

    func show() {
        let view = TranslateProbeView { [weak self] result in
            self?.finish(result)
        }
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        self.window = window
    }

    func finish(_ result: Result<String, Error>) {
        guard !finished else { return }
        finished = true
        window?.close()
        done(result)
    }
}

private struct TranslateProbeView: View {
    var done: (Result<String, Error>) -> Void
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .task {
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "es")
                )
            }
            .translationTask(configuration) { session in
                do {
                    let response = try await session.translate("Hello")
                    done(.success(response.targetText))
                } catch {
                    done(.failure(error))
                }
            }
    }
}

@MainActor
enum WebProbe {
    static func pdf(html: String, in folder: URL) async throws -> URL {
        let file = folder.appendingPathComponent("page.html")
        try html.write(to: file, atomically: true, encoding: .utf8)
        let model = WebPDFModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = model.webView
        window.orderFrontRegardless()
        defer { window.close() }
        model.loadFile(file)
        let start = Date()
        while model.webView.isLoading || model.webView.url == nil {
            if Date().timeIntervalSince(start) > 8 {
                throw ToolError(message: "the local page did not load")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let data = try await model.pdf()
        guard data.count > 100 else { throw ToolError(message: "the web page PDF was empty") }
        let output = folder.appendingPathComponent("page.pdf")
        try data.write(to: output)
        return output
    }
}
