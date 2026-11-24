import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import SatchelCore
import SwiftUI

struct PerfDriver: View {
    let directory: String

    var body: some View {
        Color.clear
            .frame(width: 4, height: 4)
            .task {
                let code = await PerfRun.run(directory: directory)
                exit(Int32(code))
            }
    }
}

enum PerfRun {
    @MainActor
    static func run(directory: String) async -> Int {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report: [String: Any] = [:]
        let launches = LaunchMeasurer.samples()
        report["launchSamples"] = launches
        report["firstLaunchSeconds"] = launches.first ?? -1
        let cold = launches.dropFirst().sorted()
        let median = cold.isEmpty ? -1 : cold[cold.count / 2]
        report["coldLaunchMedianSeconds"] = median
        report["coldLaunchSeconds"] = median
        report["launchToFirstFrameSeconds"] = median
        let model = AppModel(persists: false)
        let host = NSHostingView(rootView: RootView().environmentObject(model).frame(width: 1440, height: 900))
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 600_000_000)
        let categories: [ToolCategory?] = [nil] + ToolCategory.allCases.map { Optional($0) }
        for category in categories {
            model.category = category
            model.openTool = nil
            model.query = ""
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        model.category = nil
        model.openTool = nil
        model.query = ""
        try? await Task.sleep(nanoseconds: 200_000_000)
        report["idleRSS"] = MemoryFootprint.residentBytes()
        let stalls = StallWatch()
        stalls.start()
        var tabs: [[String: Any]] = []
        for category in categories {
            model.category = category
            model.openTool = nil
            model.query = ""
            try? await Task.sleep(nanoseconds: 160_000_000)
            tabs.append([
                "tab": category?.rawValue ?? "all",
                "rss": MemoryFootprint.residentBytes()
            ])
        }
        stalls.stop()
        report["tabs"] = tabs
        report["afterTabsRSS"] = MemoryFootprint.residentBytes()
        report["maxMainThreadGapSeconds"] = stalls.maxGap
        if let data = try? Data(contentsOf: folder.appendingPathComponent("tool-times.json")),
           let recorded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            report["tools"] = recorded
            let ranked = recorded.sorted { lhs, rhs in
                (lhs["seconds"] as? Double ?? 0) > (rhs["seconds"] as? Double ?? 0)
            }
            report["slowest"] = Array(ranked.prefix(10))
        } else {
            report["fixtureError"] = "missing tool times"
        }
        do {
            let clip = folder.appendingPathComponent("perf-clip.mov")
            try await PerfMedia.video(to: clip)
            WorkRelease.drain()
            _ = try await MediaJobs.compress(urls: [clip], quality: 0, progress: { _ in })
            WorkRelease.drain()
            let image = folder.appendingPathComponent("perf-photo.jpg")
            try PerfMedia.photo(to: image, width: 4000, height: 3000)
            WorkRelease.drain()
            _ = try await ImageJobs.compress(urls: [image], quality: 0.6, progress: { _ in })
            WorkRelease.drain()
            let pdf = folder.appendingPathComponent("perf-pages.pdf")
            try PhotoPDF.write(to: pdf, pages: 20, width: 900, height: 600)
            WorkRelease.drain()
            _ = try PDFJobs.compress(url: pdf, quality: 0.5, progress: { _ in })
            WorkRelease.drain()
            _ = try JSONFormat.pretty("{\"b\":1,\"a\":true}")
            for url in [clip, image, pdf] {
                try? FileManager.default.removeItem(at: url)
            }
            WorkRelease.drain()
        } catch {
            report["fixtureError"] = error.localizedDescription
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        WorkRelease.drain()
        report["finalRSS"] = MemoryFootprint.residentBytes()
        window.close()
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("perf.json"))
        }
        let flag = folder.appendingPathComponent("leak.done")
        let deadline = Date().addingTimeInterval(25)
        while !FileManager.default.fileExists(atPath: flag.path), Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return report["fixtureError"] == nil ? 0 : 1
    }

}

enum WorkRelease {
    static func drain() {
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.memoryCapacity = 0
        malloc_zone_pressure_relief(malloc_default_zone(), 0)
    }
}

enum ColdWindow {
    private static var delegate: ColdWindowDelegate?

    static func run() {
        let app = NSApplication.shared
        let delegate = ColdWindowDelegate()
        self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

private final class ColdWindowDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(persists: false)
        self.model = model
        let host = NSHostingView(rootView: RootView().environmentObject(model))
        let frame = NSRect(x: 80, y: 80, width: 1100, height: 720)
        host.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.contentView = host
        window.title = "Satchel"
        window.orderFrontRegardless()
        self.window = window
    }
}

enum LaunchMeasurer {
    static func samples() -> [Double] {
        guard let exe = Bundle.main.executableURL else { return [] }
        var recorded: [Double] = []
        for _ in 0..<6 {
            let process = Process()
            process.executableURL = exe
            process.arguments = ["--cold-window"]
            let start = Date()
            do {
                try process.run()
            } catch {
                recorded.append(-1)
                continue
            }
            let pid = process.processIdentifier
            let appeared = waitForWindow(pid: pid, timeout: 20)
            let elapsed = Date().timeIntervalSince(start)
            recorded.append(appeared ? elapsed : -1)
            if process.isRunning {
                process.terminate()
                usleep(150_000)
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
            process.waitUntilExit()
            usleep(200_000)
        }
        return recorded
    }

    private static func waitForWindow(pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if windowIsOnScreen(pid: pid) { return true }
            usleep(10_000)
        }
        return false
    }

    private static func windowIsOnScreen(pid: pid_t) -> Bool {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        for item in list {
            guard let owner = item[kCGWindowOwnerPID as String] as? Int, owner == Int(pid) else { continue }
            let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            if width > 200, height > 200 { return true }
        }
        return false
    }
}

final class StallWatch {
    private(set) var maxGap = 0.0
    private var timer: Timer?
    private var last = Date()

    func start() {
        last = Date()
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            let gap = now.timeIntervalSince(self.last)
            if gap > self.maxGap { self.maxGap = gap }
            self.last = now
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

enum MemoryFootprint {
    static func residentBytes() -> Int {
        let result = Commands.run("/bin/ps", ["-o", "rss=", "-p", "\(ProcessInfo.processInfo.processIdentifier)"])
        let kilobytes = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return kilobytes * 1024
    }
}

enum PerfMedia {
    static func photo(to url: URL, width: Int, height: Int) throws {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ToolError(message: "could not draw the perf photo") }
        context.setFillColor(NSColor(calibratedRed: 0.2, green: 0.45, blue: 0.7, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw ToolError(message: "could not finish the perf photo") }
        try ImageFiles.write(image, to: url, type: .jpeg, quality: 0.9)
    }

    static func video(to url: URL) async throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000]
        ])
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080
        ])
        guard writer.canAdd(video) else { throw ToolError(message: "perf writer rejected video") }
        writer.add(video)
        guard writer.startWriting() else { throw ToolError(message: writer.error?.localizedDescription ?? "perf writer did not start") }
        writer.startSession(atSourceTime: .zero)
        let frames = 300
        let queue = DispatchQueue(label: "satchel.perf.video")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            let cursor = ClipWriteState()
            video.requestMediaDataWhenReady(on: queue) { [weak video, weak writer, weak adaptor] in
                guard let video, let writer, let adaptor else { return }
                while video.isReadyForMoreMediaData {
                    guard let index = cursor.bumpFrame(limit: frames) else { break }
                    autoreleasepool {
                        guard let buffer = solidFrame() else { return }
                        let time = CMTime(value: CMTimeValue(index), timescale: 10)
                        _ = adaptor.append(buffer, withPresentationTime: time)
                    }
                }
                if cursor.filled(frames), !cursor.videoDone {
                    cursor.videoDone = true
                    video.markAsFinished()
                    writer.finishWriting { [weak writer] in
                        if writer?.status == .completed { gate.resume(continuation) }
                        else { gate.fail(continuation, ToolError(message: writer?.error?.localizedDescription ?? "perf clip failed")) }
                    }
                }
            }
            queue.asyncAfter(deadline: .now() + 60) {
                gate.fail(continuation, ToolError(message: "perf clip timed out"))
            }
        }
    }

    private static func solidFrame() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 1920, 1080, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 40, CVPixelBufferGetBytesPerRow(buffer) * 1080)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
