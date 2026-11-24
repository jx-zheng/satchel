import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
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
        report["coldLaunchSeconds"] = Date().timeIntervalSince(Launch.booted)
        report["launchToFirstFrameSeconds"] = Date().timeIntervalSince(Launch.booted)
        let model = AppModel(persists: false)
        let host = NSHostingView(rootView: RootView().environmentObject(model).frame(width: 1440, height: 900))
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 400_000_000)
        report["idleRSS"] = MemoryFootprint.residentBytes()
        let stalls = StallWatch()
        stalls.start()
        var tabs: [[String: Any]] = []
        let categories: [ToolCategory?] = [nil] + ToolCategory.allCases.map { Optional($0) }
        for category in categories {
            model.category = category
            model.openTool = nil
            model.query = ""
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 80_000_000)
            tabs.append([
                "tab": category?.rawValue ?? "all",
                "rss": MemoryFootprint.residentBytes()
            ])
        }
        stalls.stop()
        report["tabs"] = tabs
        report["afterTabsRSS"] = MemoryFootprint.residentBytes()
        report["maxMainThreadGapSeconds"] = stalls.maxGap
        var tools: [[String: Any]] = []
        do {
            let clip = folder.appendingPathComponent("perf-clip.mov")
            let videoStarted = Date()
            try await PerfMedia.video(to: clip)
            tools.append(try await time("compress-video") {
                _ = try await MediaJobs.compress(urls: [clip], quality: 0, progress: { _ in })
            })
            let image = folder.appendingPathComponent("perf-photo.jpg")
            try PerfMedia.photo(to: image, width: 4000, height: 3000)
            tools.append(try await time("compress-image") {
                _ = try await ImageJobs.compress(urls: [image], quality: 0.6, progress: { _ in })
            })
            let pdf = folder.appendingPathComponent("perf-pages.pdf")
            try PhotoPDF.write(to: pdf, pages: 20, width: 900, height: 600)
            tools.append(try await time("compress-pdf") {
                _ = try PDFJobs.compress(url: pdf, quality: 0.5, progress: { _ in })
            })
            tools.append(try await time("json") {
                _ = try JSONFormat.pretty("{\"b\":1,\"a\":true}")
            })
        } catch {
            report["fixtureError"] = error.localizedDescription
        }
        report["tools"] = tools
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

    private static func time(_ name: String, _ body: () async throws -> Void) async throws -> [String: Any] {
        let start = Date()
        try await body()
        return [
            "tool": name,
            "seconds": Date().timeIntervalSince(start),
            "rss": MemoryFootprint.residentBytes()
        ]
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
            video.requestMediaDataWhenReady(on: queue) {
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
                    writer.finishWriting {
                        if writer.status == .completed { gate.resume(continuation) }
                        else { gate.fail(continuation, ToolError(message: writer.error?.localizedDescription ?? "perf clip failed")) }
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
