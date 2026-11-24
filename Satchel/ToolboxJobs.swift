import AppKit
import AVFoundation
import AVFAudio
import CoreMedia
import CoreText
import Darwin
import Foundation
import IOKit
import NaturalLanguage
import PDFKit
import QuickLookThumbnailing
import SatchelCore

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Subtitles

enum SubtitleBurn {
    struct Cue {
        var start: Double
        var end: Double
        var text: String
    }

    static func parseSRT(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.first(where: { $0.contains("-->") }) else { continue }
            let parts = timing.components(separatedBy: "-->")
            guard parts.count >= 2 else { continue }
            let start = timestamp(parts[0])
            let end = timestamp(parts[1])
            let body = lines.drop { !$0.contains("-->") }.dropFirst().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty, end > start {
                cues.append(Cue(start: start, end: end, text: body))
            }
        }
        return cues
    }

    static func burn(video: URL, srt: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let cues = parseSRT(try String(contentsOf: srt, encoding: .utf8))
        guard !cues.isEmpty else { throw ToolError(message: "That subtitle file has no cues.") }
        let asset = AVURLAsset(url: video)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw ToolError(message: "That video has no picture track.")
        }
        let natural = try await sourceVideo.load(.naturalSize)
        let preferred = try await sourceVideo.load(.preferredTransform)
        let oriented = ClipGeometry.oriented(natural: natural, preferred: preferred)
        let size = ClipGeometry.even(oriented.size)
        let output = try Outputs.make(nextTo: video, suffix: "-subtitled", ext: "mp4")
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let trackOutput = AVAssetReaderTrackOutput(track: sourceVideo, outputSettings: settings)
        trackOutput.alwaysCopiesSampleData = true
        guard reader.canAdd(trackOutput) else { throw ToolError(message: "Could not read the video frames.") }
        reader.add(trackOutput)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw ToolError(message: "Could not prepare the subtitled video.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw ToolError(message: writer.error?.localizedDescription ?? "Could not start the subtitled export.")
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            throw ToolError(message: reader.error?.localizedDescription ?? "Could not read the video.")
        }
        progress(0.05)
        var frames = 0
        while let sample = trackOutput.copyNextSampleBuffer() {
            guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            if let cue = cues.first(where: { time >= $0.start && time <= $0.end }) {
                stamp(cue.text, on: image)
            }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            if !input.append(sample) {
                throw ToolError(message: writer.error?.localizedDescription ?? "Could not write a subtitled frame.")
            }
            frames += 1
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        progress(1)
        guard frames > 0, writer.status == .completed else {
            throw ToolError(message: writer.error?.localizedDescription ?? "The subtitled export did not finish.")
        }
        return output
    }

    private static func stamp(_ text: String, on buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: row,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info
        ) else { return }
        let barHeight = max(48, CGFloat(height) * 0.30)
        let bar = CGRect(x: 0, y: 12, width: CGFloat(width), height: barHeight)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bar)
        let fontSize = max(28, CGFloat(height) * 0.16)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.black
        ]))
        context.textPosition = CGPoint(x: 12, y: bar.midY - fontSize * 0.35)
        CTLineDraw(line, context)
    }

    private static func timestamp(_ raw: String) -> Double {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let bits = cleaned.split(separator: ":").map { Double($0) ?? 0 }
        if bits.count == 3 { return bits[0] * 3600 + bits[1] * 60 + bits[2] }
        if bits.count == 2 { return bits[0] * 60 + bits[1] }
        return bits.first ?? 0
    }
}

// MARK: - Audio cleanup

enum AudioCleanup {
    static func clean(urls: [URL], progress: @escaping (Double) -> Void) async throws -> [URL] {
        guard let url = urls.first else { throw ToolError(message: "Drop an audio file first.") }
        let samples = try await readSamples(url)
        guard samples.count > 256 else { throw ToolError(message: "That audio file is too short to clean.") }
        progress(0.2)
        let cleaned = denoise(samples: samples, sampleRate: 44_100)
        progress(0.8)
        let output = try Outputs.make(nextTo: url, suffix: "-clean", ext: "wav")
        try writeWAV(cleaned, to: output, sampleRate: 44_100)
        progress(1)
        return [output]
    }

    static func assertLouderSignal() throws {
        try fftRoundtrip()
        let rate = 44_100
        let total = rate * 2
        var rng = LCG(state: 0xC0FFEE)
        var clean = [Float](repeating: 0, count: total)
        var noisy = [Float](repeating: 0, count: total)
        let prefix = rate / 4
        for index in 0..<total {
            let noise = rng.next() * 0.12
            let time = Float(index) / Float(rate)
            let tone: Float = index < prefix ? 0 : 0.5 * sin(2 * .pi * 440 * time)
            clean[index] = tone
            noisy[index] = tone + noise
        }
        let before = snr(reference: clean, observed: noisy, from: prefix + rate / 20)
        let afterSamples = denoise(samples: noisy, sampleRate: Double(rate))
        let after = snr(reference: clean, observed: afterSamples, from: prefix + rate / 20)
        if !(after > before + 0.8) {
            throw ToolError(message: String(format: "snr %.2f dB did not improve (now %.2f dB)", before, after))
        }
    }

    static func writeTestTone(to url: URL) throws {
        let rate = 44_100
        let total = rate
        var rng = LCG(state: 99)
        var samples = [Float](repeating: 0, count: total)
        for index in 0..<total {
            let tone = 0.4 * sin(2 * .pi * 440 * Float(index) / Float(rate))
            samples[index] = tone + rng.next() * 0.08
        }
        try writeWAV(samples, to: url, sampleRate: rate)
    }

    static func denoise(samples: [Float], sampleRate: Double) -> [Float] {
        let n = 1024
        guard samples.count > n * 2 else { return samples }
        let prefix = min(samples.count / 2, max(n, Int(sampleRate * 0.25)))
        var noise = [Float](repeating: 0, count: n)
        var noiseFrames = 0
        var start = 0
        while start + n <= prefix {
            let spec = SpectralFFT.forward(Array(samples[start..<(start + n)]))
            for index in 0..<min(n, spec.count) {
                noise[index] += spec[index].0 * spec[index].0 + spec[index].1 * spec[index].1
            }
            noiseFrames += 1
            start += n
        }
        guard noiseFrames > 0 else { return samples }
        for index in 0..<n { noise[index] /= Float(noiseFrames) }
        var output = samples
        start = 0
        while start + n <= samples.count {
            var spec = SpectralFFT.forward(Array(samples[start..<(start + n)]))
            for index in 0..<spec.count {
                let power = spec[index].0 * spec[index].0 + spec[index].1 * spec[index].1
                let gain = min(1, sqrt(max(0, power - noise[min(index, n - 1)]) / max(power, 1e-8)))
                spec[index].0 *= gain
                spec[index].1 *= gain
            }
            let back = SpectralFFT.inverse(spec)
            for index in 0..<min(n, back.count) {
                output[start + index] = back[index]
            }
            start += n
        }
        return output
    }

    static func snr(reference: [Float], observed: [Float], from start: Int) -> Double {
        let end = min(reference.count, observed.count)
        guard start < end else { return 0 }
        var signal = 0.0
        var error = 0.0
        for index in start..<end {
            let value = Double(reference[index])
            let delta = Double(observed[index]) - value
            signal += value * value
            error += delta * delta
        }
        return 10 * log10(max(signal, 1e-12) / max(error, 1e-12))
    }

    private static func fftRoundtrip() throws {
        let tone = (0..<64).map { sin(2 * .pi * Float($0) / 64) }
        let back = SpectralFFT.inverse(SpectralFFT.forward(tone))
        let error = zip(tone, back).map { abs($0 - $1) }.max() ?? 1
        if error > 0.02 {
            throw ToolError(message: "fft roundtrip error \(error)")
        }
    }

    private static func readSamples(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ToolError(message: "That file has no audio track.")
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw ToolError(message: "Could not read that audio.") }
        reader.add(output)
        guard reader.startReading() else {
            throw ToolError(message: reader.error?.localizedDescription ?? "Could not read that audio.")
        }
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var total = 0
            var pointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &total, dataPointerOut: &pointer)
            if status == kCMBlockBufferNoErr, let pointer, total > 0 {
                let count = total / MemoryLayout<Float>.size
                pointer.withMemoryRebound(to: Float.self, capacity: count) { floatPointer in
                    samples.append(contentsOf: UnsafeBufferPointer(start: floatPointer, count: count))
                }
            }
        }
        if reader.status == .failed {
            throw ToolError(message: reader.error?.localizedDescription ?? "Could not finish reading the audio.")
        }
        guard !samples.isEmpty else { throw ToolError(message: "That audio file had no samples.") }
        return samples
    }

    static func writeWAV(_ samples: [Float], to url: URL, sampleRate: Int) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var pcm = [Int16](repeating: 0, count: samples.count)
        for index in 0..<samples.count {
            let clipped = max(-1, min(1, samples[index]))
            pcm[index] = Int16(clipped * 32_000)
        }
        let dataSize = pcm.count * 2
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.append(contentsOf: le32(UInt32(36 + dataSize)))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20])
        data.append(contentsOf: le32(16))
        data.append(contentsOf: le16(1))
        data.append(contentsOf: le16(1))
        data.append(contentsOf: le32(UInt32(sampleRate)))
        data.append(contentsOf: le32(UInt32(sampleRate * 2)))
        data.append(contentsOf: le16(2))
        data.append(contentsOf: le16(16))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        data.append(contentsOf: le32(UInt32(dataSize)))
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url)
    }

    private static func hann(_ n: Int) -> [Float] {
        (0..<n).map { index in
            0.5 - 0.5 * cos(2 * .pi * Float(index) / Float(n))
        }
    }

    private static func frameStarts(count: Int, n: Int, hop: Int) -> [Int] {
        guard count >= n else { return [] }
        return Array(stride(from: 0, through: count - n, by: hop))
    }

    private static func rms(_ samples: [Float], _ start: Int, _ end: Int) -> Float {
        let lower = max(0, start)
        let upper = min(samples.count, end)
        guard upper > lower else { return 0 }
        var total: Float = 0
        for index in lower..<upper { total += samples[index] * samples[index] }
        return sqrt(total / Float(upper - lower))
    }

    private static func averagePower(_ samples: [Float], window: [Float], n: Int, frames: [Int]) -> [Float]? {
        guard !frames.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: n)
        for start in frames where start + n <= samples.count {
            var frame = Array(samples[start..<(start + n)])
            for index in 0..<n { frame[index] *= window[index] }
            let spec = SpectralFFT.forward(frame)
            for index in 0..<min(n, spec.count) {
                sum[index] += spec[index].0 * spec[index].0 + spec[index].1 * spec[index].1
            }
        }
        let scale = Float(frames.count)
        return sum.map { $0 / scale }
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
    }

    private static func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
    }
}

private struct LCG {
    var state: UInt64
    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        let unit = Float(state >> 40) / Float(1 << 24)
        return unit * 2 - 1
    }
}

private enum SpectralFFT {
    static func forward(_ input: [Float]) -> [(Float, Float)] {
        var real = input
        var imag = [Float](repeating: 0, count: input.count)
        transform(&real, &imag, invert: false)
        return zip(real, imag).map { ($0, $1) }
    }

    static func inverse(_ spectrum: [(Float, Float)]) -> [Float] {
        var real = spectrum.map(\.0)
        var imag = spectrum.map(\.1)
        transform(&real, &imag, invert: true)
        let scale = 1 / Float(max(spectrum.count, 1))
        return real.map { $0 * scale }
    }

    private static func transform(_ real: inout [Float], _ imag: inout [Float], invert: Bool) {
        let n = real.count
        guard n > 1, n & (n - 1) == 0 else { return }
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                real.swapAt(i, j)
                imag.swapAt(i, j)
            }
        }
        var length = 2
        while length <= n {
            let angle = (invert ? 2 : -2) * Float.pi / Float(length)
            let wlenRe = cos(angle)
            let wlenIm = sin(angle)
            var i = 0
            while i < n {
                var wRe: Float = 1
                var wIm: Float = 0
                for k in 0..<(length / 2) {
                    let uRe = real[i + k]
                    let uIm = imag[i + k]
                    let vIndex = i + k + length / 2
                    let vRe = real[vIndex] * wRe - imag[vIndex] * wIm
                    let vIm = real[vIndex] * wIm + imag[vIndex] * wRe
                    real[i + k] = uRe + vRe
                    imag[i + k] = uIm + vIm
                    real[vIndex] = uRe - vRe
                    imag[vIndex] = uIm - vIm
                    let nextRe = wRe * wlenRe - wIm * wlenIm
                    wIm = wRe * wlenIm + wIm * wlenRe
                    wRe = nextRe
                }
                i += length
            }
            length <<= 1
        }
    }
}

// MARK: - Download

enum VideoDownload {
    static let rights = "Only save a video you have the right to keep. Satchel does not include yt-dlp or ffmpeg. A direct file or HLS playlist is downloaded on this Mac. A page link is handed to yt-dlp only when you installed that program yourself."

    /// AVAssetDownloadURLSession is not part of the native macOS SDK, so playlists are fetched with URLSession.
    static func save(urlString: String, directory: URL, allowPageTool: Bool, progress: @escaping (Double) -> Void) async throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else {
            throw ToolError(message: "Enter a full http or https link.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        progress(0.05)
        if url.pathExtension.lowercased() == "m3u8" {
            return try await playlist(url, directory: directory, progress: progress)
        }
        if isDirectMedia(url) || !allowPageTool {
            return try await file(url, directory: directory, progress: progress)
        }
        if let binary = ytdlpBinary() {
            return try runYTDLP(binary, url: url, directory: directory)
        }
        if isDirectMedia(url) {
            return try await file(url, directory: directory, progress: progress)
        }
        throw ToolError(message: "That link is not a direct video or playlist. Install yt-dlp yourself if you have the rights to save it. Satchel does not include yt-dlp or ffmpeg.")
    }

    static func ytdlpBinary() -> String? {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        let which = Commands.run("/usr/bin/which", ["yt-dlp"])
        let path = which.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if which.status == 0, path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func isDirectMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "m4a", "mp3", "webm", "mkv", "ts", "m3u8"].contains(ext)
    }

    private static func file(_ url: URL, directory: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let (downloaded, response) = try await session().download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError(message: "The server did not return the video.")
        }
        let name = url.lastPathComponent.isEmpty ? "Video.mp4" : url.lastPathComponent
        let output = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try FileManager.default.copyItem(at: downloaded, to: output)
        progress(1)
        return output
    }

    private static func playlist(_ url: URL, directory: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let (data, response) = try await session().data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw ToolError(message: "Could not read that playlist.")
        }
        let segments = text.split(separator: "\n").compactMap { line -> URL? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
            return URL(string: trimmed, relativeTo: url)?.absoluteURL
        }
        guard !segments.isEmpty else { throw ToolError(message: "That playlist has no segments.") }
        var joined = Data()
        for (index, segment) in segments.enumerated() {
            let (part, partResponse) = try await session().data(from: segment)
            guard let http = partResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ToolError(message: "A playlist segment did not download.")
            }
            joined.append(part)
            progress(Double(index + 1) / Double(segments.count))
        }
        let name = segments[0].lastPathComponent.isEmpty ? "stream.mp4" : segments[0].lastPathComponent
        let output = directory.appendingPathComponent(name)
        try joined.write(to: output)
        return output
    }

    private static func runYTDLP(_ binary: String, url: URL, directory: URL) throws -> URL {
        let template = directory.appendingPathComponent("video.%(ext)s").path
        let result = Commands.run(binary, ["--no-playlist", "--no-mtime", "-o", template, url.absoluteString])
        guard result.status == 0 else {
            throw ToolError(message: result.output.isEmpty ? "yt-dlp could not save that link." : result.output)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let output = files.first else { throw ToolError(message: "yt-dlp did not write a file.") }
        return output
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }
}

enum LoopbackServer {
    final class Token: @unchecked Sendable {
        var running = true
    }

    static func start(_ files: [String: Data]) throws -> (port: UInt16, stop: () -> Void) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { throw ToolError(message: "Could not open a local port.") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 {
            close(fd)
            throw ToolError(message: "Could not bind a local port.")
        }
        listen(fd, 16)
        var stored = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &stored) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        if named != 0 {
            close(fd)
            throw ToolError(message: "Could not read the local port.")
        }
        let port = UInt16(bigEndian: stored.sin_port)
        let token = Token()
        Thread.detachNewThread {
            serve(fd: fd, token: token, files: files)
        }
        return (port, {
            token.running = false
            close(fd)
        })
    }

    private static func serve(fd: Int32, token: Token, files: [String: Data]) {
        while token.running {
            var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&item, 1, 200) <= 0 { continue }
            let client = accept(fd, nil, nil)
            if client < 0 { continue }
            var buffer = [UInt8](repeating: 0, count: 2048)
            let count = read(client, &buffer, buffer.count)
            let request = count > 0 ? String(decoding: buffer.prefix(count), as: UTF8.self) : ""
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let key = path.split(separator: "?").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "/")) } ?? ""
            let body = files[key]
            var bytes: Data
            if let body {
                var header = "HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
                if key.hasSuffix("m3u8") {
                    header += "Content-Type: application/vnd.apple.mpegurl\r\n"
                } else {
                    header += "Content-Type: application/octet-stream\r\n"
                }
                header += "\r\n"
                bytes = Data(header.utf8) + body
            } else {
                bytes = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            }
            bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var sent = 0
                while sent < raw.count {
                    let wrote = write(client, base.advanced(by: sent), raw.count - sent)
                    if wrote <= 0 { break }
                    sent += wrote
                }
            }
            close(client)
        }
    }
}

// MARK: - Display

struct DisplayModeLine: Identifiable {
    var id: String
    var text: String
    var current: Bool
    var width: Int
    var height: Int
}

struct DisplayReading {
    var modes: [DisplayModeLine]
    var brightness: Float?
}

enum DisplayDesk {
    static func read() throws -> DisplayReading {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        if count == 0 { throw SkipSignal(reason: "no display is attached") }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        var lines: [DisplayModeLine] = []
        for id in ids.prefix(Int(count)) {
            let current = CGDisplayCopyDisplayMode(id)
            let modes = Self.modes(on: id)
            let listed = modes.isEmpty ? (current.map { [$0] } ?? []) : modes
            for mode in listed {
                let width = Int(mode.width)
                let height = Int(mode.height)
                let refresh = mode.refreshRate
                let active = current?.width == mode.width && current?.height == mode.height && abs((current?.refreshRate ?? 0) - refresh) < 0.5
                let label = refresh > 1 ? "\(width)×\(height) at \(Int(refresh.rounded())) Hz" : "\(width)×\(height)"
                lines.append(DisplayModeLine(id: "\(id)-\(width)-\(height)-\(refresh)", text: label, current: active, width: width, height: height))
            }
        }
        if lines.isEmpty { throw ToolError(message: "This Mac did not report a display mode.") }
        return DisplayReading(modes: lines, brightness: brightnessService().flatMap { BrightnessLink.read($0) })
    }

    static func setBrightness(_ value: Float) throws {
        guard let service = brightnessService() else {
            throw ToolError(message: "This Mac did not expose a brightness control.")
        }
        let clamped = max(0, min(1, value))
        guard BrightnessLink.write(service, clamped) else {
            throw ToolError(message: "Brightness could not be changed.")
        }
    }

    private static func modes(on id: CGDirectDisplayID) -> [CGDisplayMode] {
        guard let array = CGDisplayCopyAllDisplayModes(id, nil) else { return [] }
        return (0..<CFArrayGetCount(array)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { return nil }
            return Unmanaged<CGDisplayMode>.fromOpaque(pointer).takeUnretainedValue()
        }
    }

    private static func brightnessService() -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        if service == 0 { return nil }
        return service
    }
}

private enum BrightnessLink {
    private typealias Getter = @convention(c) (UInt32, UInt32, CFString, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (UInt32, UInt32, CFString, Float) -> Int32

    static func read(_ service: io_service_t) -> Float? {
        defer { IOObjectRelease(service) }
        guard let getter = symbol("IODisplayGetFloatParameter", as: Getter.self) else { return nil }
        var value: Float = 0
        let status = getter(service, 0, "brightness" as CFString, &value)
        return status == 0 ? value : nil
    }

    static func write(_ service: io_service_t, _ value: Float) -> Bool {
        defer { IOObjectRelease(service) }
        guard let setter = symbol("IODisplaySetFloatParameter", as: Setter.self) else { return false }
        return setter(service, 0, "brightness" as CFString, value) == 0
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: type)
    }
}

// MARK: - Language

enum Summaries {
    static func make(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let generated = await OnDeviceLanguage.summarize(trimmed) {
            return generated
        }
        return extractive(trimmed)
    }

    static func extractive(_ text: String) -> String {
        let sentences = sentences(in: text)
        guard sentences.count > 1 else { return text }
        var counts: [String: Int] = [:]
        for sentence in sentences {
            for word in tokens(sentence) where !stopwords.contains(word) && word.count > 2 {
                counts[word, default: 0] += 1
            }
        }
        let ranked = sentences.enumerated().map { index, sentence -> (Int, Int, String) in
            let score = tokens(sentence).reduce(0) { $0 + (counts[$1] ?? 0) }
            return (score, -index, sentence)
        }.sorted { lhs, rhs in
            if lhs.0 == rhs.0 { return lhs.1 > rhs.1 }
            return lhs.0 > rhs.0
        }
        let keep = max(1, min(3, sentences.count / 2))
        let chosen = Set(ranked.prefix(keep).map(\.2))
        let ordered = sentences.filter { chosen.contains($0) }
        let summary = ordered.joined(separator: " ")
        return summary.isEmpty ? sentences[0] : summary
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "that", "with", "this", "from", "are", "was", "were", "have", "has",
        "but", "not", "you", "your", "into", "about", "they", "their", "a", "an", "of", "to", "in", "on"
    ]

    static func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result.isEmpty ? [text] : result
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

enum DocumentQA {
    static func answer(question: String, document: String) async -> String {
        let passage = bestPassage(question: question, document: document)
        if let generated = await OnDeviceLanguage.answer(question: question, passage: passage, document: document) {
            return generated
        }
        if passage.isEmpty { return "Nothing in the document matched that question." }
        return passage
    }

    static func bestPassage(question: String, document: String) -> String {
        let passages = Summaries.sentences(in: document)
        guard !passages.isEmpty else { return "" }
        if let embedding = NLEmbedding.sentenceEmbedding(for: .english),
           let query = embedding.vector(for: question) {
            var best = passages[0]
            var bestScore = -Double.greatestFiniteMagnitude
            for passage in passages {
                guard let vector = embedding.vector(for: passage) else { continue }
                let score = cosine(query, vector)
                if score > bestScore {
                    bestScore = score
                    best = passage
                }
            }
            if bestScore > 0.2 { return best }
        }
        let wanted = Set(Summaries.tokens(question)).subtracting(Summaries.tokens("what is the a an"))
        var best = passages[0]
        var bestScore = -1
        for passage in passages {
            let score = Set(Summaries.tokens(passage)).intersection(wanted).count
            if score > bestScore {
                bestScore = score
                best = passage
            }
        }
        return best
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var dot = 0.0
        var left = 0.0
        var right = 0.0
        for index in 0..<count {
            dot += a[index] * b[index]
            left += a[index] * a[index]
            right += b[index] * b[index]
        }
        return dot / max(1e-9, sqrt(left) * sqrt(right))
    }
}

private enum OnDeviceLanguage {
    static func summarize(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await AppleLanguage.summarize(text)
        }
        #endif
        return nil
    }

    static func answer(question: String, passage: String, document: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await AppleLanguage.answer(question: question, document: document)
        }
        #endif
        _ = passage
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum AppleLanguage {
    static func summarize(_ text: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let session = LanguageModelSession(instructions: "Summarize the notes in a few sentences. Keep names and numbers. Do not add facts.")
        do {
            let response = try await session.respond(to: String(text.prefix(12_000)))
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        } catch {
            return nil
        }
    }

    static func answer(question: String, document: String) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let session = LanguageModelSession(instructions: "Answer only from the document. If it does not say, say so. Quote the useful sentence.")
        do {
            let prompt = "Document:\n\(document.prefix(12_000))\n\nQuestion: \(question)"
            let response = try await session.respond(to: prompt)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        } catch {
            return nil
        }
    }
}
#endif
