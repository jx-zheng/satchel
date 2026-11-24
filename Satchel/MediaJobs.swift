import AVFoundation
import AVFAudio
import AudioToolbox
import CoreMedia
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import SatchelCore

enum MediaExport {
    static func export(
        asset: AVAsset,
        output: URL,
        fileType: AVFileType,
        preset: String,
        timeRange: CMTimeRange? = nil,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        progress: @escaping (Double) -> Void
    ) async throws {
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        let reader = try AVAssetReader(asset: asset)
        if let timeRange, CMTimeGetSeconds(timeRange.duration) > 0 {
            reader.timeRange = timeRange
        }
        let writer = try AVAssetWriter(outputURL: output, fileType: fileType)
        let audioOnly = fileType == .m4a || preset == AVAssetExportPresetAppleM4A
        let passthrough = preset == AVAssetExportPresetPassthrough && videoComposition == nil && audioMix == nil && !audioOnly
        let pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]
        if passthrough {
            pairs = try await copiedPairs(asset: asset, reader: reader, writer: writer)
        } else if audioOnly {
            pairs = try await soundPairs(asset: asset, reader: reader, writer: writer, mix: audioMix)
        } else {
            pairs = try await encodedPairs(
                asset: asset,
                reader: reader,
                writer: writer,
                preset: preset,
                videoComposition: videoComposition,
                audioMix: audioMix
            )
        }
        guard !pairs.isEmpty else { throw ToolError(message: "This file can’t be exported with the chosen settings.") }
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard reader.startReading() else {
            throw ToolError(message: reader.error?.localizedDescription ?? "Could not read that file.")
        }
        guard writer.startWriting() else {
            throw ToolError(message: writer.error?.localizedDescription ?? "Could not start writing the file.")
        }
        let start = reader.timeRange.start
        writer.startSession(atSourceTime: start.isValid && !start.isIndefinite ? start : .zero)
        try await ExportPump(reader: reader, writer: writer, pairs: pairs, duration: duration, progress: progress).run()
        progress(1)
    }

    private static func copiedPairs(asset: AVAsset, reader: AVAssetReader, writer: AVAssetWriter) async throws -> [(AVAssetReaderOutput, AVAssetWriterInput)] {
        var pairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = []
        for media in [AVMediaType.video, AVMediaType.audio] {
            guard let track = try await asset.loadTracks(withMediaType: media).first else { continue }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = true
            let input = AVAssetWriterInput(mediaType: media, outputSettings: nil)
            input.expectsMediaDataInRealTime = false
            if media == .video {
                input.transform = try await track.load(.preferredTransform)
            }
            guard reader.canAdd(output), writer.canAdd(input) else {
                throw ToolError(message: "This file can’t be copied without re-encoding.")
            }
            reader.add(output)
            writer.add(input)
            pairs.append((output, input))
        }
        return pairs
    }

    private static func soundPairs(asset: AVAsset, reader: AVAssetReader, writer: AVAssetWriter, mix: AVAudioMix?) async throws -> [(AVAssetReaderOutput, AVAssetWriterInput)] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw ToolError(message: "That file has no audio track.") }
        let channels = await channelCount(track)
        let output = mixedAudio(tracks: tracks, fallback: track, settings: pcmSettings(channels: channels), mix: mix)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings(channels: channels))
        input.expectsMediaDataInRealTime = false
        guard reader.canAdd(output), writer.canAdd(input) else {
            throw ToolError(message: "This file can’t be exported as audio.")
        }
        reader.add(output)
        writer.add(input)
        return [(output, input)]
    }

    private static func encodedPairs(
        asset: AVAsset,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        preset: String,
        videoComposition: AVVideoComposition?,
        audioMix: AVAudioMix?
    ) async throws -> [(AVAssetReaderOutput, AVAssetWriterInput)] {
        var pairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = []
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let track = videoTracks.first {
            let size = try await pictureSize(track: track, composition: videoComposition)
            let pixels: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            let output: AVAssetReaderOutput
            if let videoComposition {
                let composed = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: pixels)
                composed.videoComposition = videoComposition
                composed.alwaysCopiesSampleData = true
                output = composed
            } else {
                let direct = AVAssetReaderTrackOutput(track: track, outputSettings: pixels)
                direct.alwaysCopiesSampleData = true
                output = direct
            }
            let hevc = preset == AVAssetExportPresetHEVC1920x1080
            var compression: [String: Any] = [AVVideoAverageBitRateKey: bitrate(for: preset)]
            if !hevc { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: compression
            ])
            input.expectsMediaDataInRealTime = false
            if videoComposition == nil {
                input.transform = try await track.load(.preferredTransform)
            }
            guard reader.canAdd(output), writer.canAdd(input) else {
                throw ToolError(message: "This video can’t be re-encoded with the chosen settings.")
            }
            reader.add(output)
            writer.add(input)
            pairs.append((output, input))
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let track = audioTracks.first {
            let channels = await channelCount(track)
            let output = mixedAudio(tracks: audioTracks, fallback: track, settings: pcmSettings(channels: channels), mix: audioMix)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings(channels: channels))
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else {
                throw ToolError(message: "This audio can’t be re-encoded with the chosen settings.")
            }
            reader.add(output)
            writer.add(input)
            pairs.append((output, input))
        }
        return pairs
    }

    private static func mixedAudio(tracks: [AVAssetTrack], fallback: AVAssetTrack, settings: [String: Any], mix: AVAudioMix?) -> AVAssetReaderOutput {
        if let mix {
            let mixed = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
            mixed.audioMix = mix
            mixed.alwaysCopiesSampleData = true
            return mixed
        }
        let direct = AVAssetReaderTrackOutput(track: fallback, outputSettings: settings)
        direct.alwaysCopiesSampleData = true
        return direct
    }

    private static func pictureSize(track: AVAssetTrack, composition: AVVideoComposition?) async throws -> CGSize {
        if let composition, composition.renderSize.width >= 2, composition.renderSize.height >= 2 {
            return ClipGeometry.even(composition.renderSize)
        }
        let natural = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        return ClipGeometry.even(ClipGeometry.oriented(natural: natural, preferred: preferred).size)
    }

    private static func channelCount(_ track: AVAssetTrack) async -> Int {
        guard let format = (try? await track.load(.formatDescriptions))?.first,
              let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return 2 }
        return pointer.pointee.mChannelsPerFrame <= 1 ? 1 : 2
    }

    private static func pcmSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private static func aacSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 128_000
        ]
    }

    private static func bitrate(for preset: String) -> Int {
        switch preset {
        case AVAssetExportPresetLowQuality: return 700_000
        case AVAssetExportPreset640x480: return 1_200_000
        case AVAssetExportPresetMediumQuality: return 2_500_000
        case AVAssetExportPreset1280x720: return 5_000_000
        case AVAssetExportPreset1920x1080: return 8_000_000
        case AVAssetExportPresetHEVC1920x1080: return 6_000_000
        default: return 4_000_000
        }
    }

    static func fileType(for ext: String) -> AVFileType {
        switch ext.lowercased() {
        case "mov": return .mov
        case "m4v": return .m4v
        case "m4a": return .m4a
        default: return .mp4
        }
    }
}

private final class ExportPump: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]
    let duration: Double
    let progress: (Double) -> Void
    let queue = DispatchQueue(label: "satchel.export")
    let lock = NSLock()
    let gate = ResumeGate()
    var remaining = 0
    var armed = false
    var failed = false
    var finishing = false
    var continuation: CheckedContinuation<Void, Error>?

    init(reader: AVAssetReader, writer: AVAssetWriter, pairs: [(AVAssetReaderOutput, AVAssetWriterInput)], duration: Double, progress: @escaping (Double) -> Void) {
        self.reader = reader
        self.writer = writer
        self.pairs = pairs
        self.duration = duration
        self.progress = progress
    }

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            queue.async { [weak self] in
                self?.pull()
            }
        }
    }

    private func pull() {
        var open = pairs
        let started = Date()
        var lastSample = started
        while !open.isEmpty {
            lock.lock()
            let stop = failed
            lock.unlock()
            if stop { return }
            if reader.status == .failed {
                fail(reader.error ?? ToolError(message: "Could not read the media."))
                return
            }
            var wrote = false
            var index = 0
            while index < open.count {
                let output = open[index].0
                let input = open[index].1
                if !input.isReadyForMoreMediaData {
                    index += 1
                    continue
                }
                wrote = true
                lastSample = Date()
                if let sample = output.copyNextSampleBuffer() {
                    if !input.append(sample) {
                        fail(writer.error ?? ToolError(message: "Could not write the media."))
                        return
                    }
                    if duration > 0 {
                        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                        if time.isFinite {
                            let fraction = min(0.99, max(0, time / duration))
                            DispatchQueue.main.async { [weak self] in self?.progress(fraction) }
                        }
                    }
                    index += 1
                } else {
                    input.markAsFinished()
                    open.remove(at: index)
                }
            }
            if open.isEmpty { break }
            if !wrote {
                let quiet = Date().timeIntervalSince(lastSample)
                if quiet > 12 || Date().timeIntervalSince(started) > 12 && lastSample == started {
                    fail(ToolError(message: "Export stalled."))
                    return
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        lock.lock()
        let stop = failed
        if !stop { finishing = true }
        lock.unlock()
        if !stop { complete() }
    }

    private func complete() {
        writer.finishWriting { [weak self] in
            guard let self, let continuation = self.continuation else { return }
            if self.writer.status == .completed {
                self.gate.resume(continuation)
            } else {
                self.gate.fail(continuation, ToolError(message: self.writer.error?.localizedDescription ?? "Could not finish the file."))
            }
        }
    }

    private func fail(_ error: Error) {
        lock.lock()
        if failed {
            lock.unlock()
            return
        }
        failed = true
        lock.unlock()
        reader.cancelReading()
        guard let continuation else { return }
        gate.fail(continuation, error)
    }
}

enum ClipGeometry {
    static func oriented(natural: CGSize, preferred: CGAffineTransform) -> (size: CGSize, transform: CGAffineTransform) {
        let rect = CGRect(origin: .zero, size: natural).applying(preferred)
        let size = CGSize(width: abs(rect.width), height: abs(rect.height))
        let fix = CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
        return (size, preferred.concatenating(fix))
    }

    static func rotate(transform: CGAffineTransform, size: CGSize, quarterTurns: Int) -> (CGAffineTransform, CGSize) {
        var t = transform
        var current = size
        let turns = ((quarterTurns % 4) + 4) % 4
        for _ in 0..<turns {
            let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
            let rotated = CGRect(origin: .zero, size: current).applying(rotation)
            let fix = CGAffineTransform(translationX: -rotated.minX, y: -rotated.minY)
            t = t.concatenating(rotation).concatenating(fix)
            current = CGSize(width: abs(rotated.width), height: abs(rotated.height))
        }
        return (t, current)
    }

    static func inset(_ fraction: CGFloat, transform: CGAffineTransform, size: CGSize) -> (CGAffineTransform, CGSize) {
        let amount = min(0.45, max(0, fraction))
        let dx = size.width * amount
        let dy = size.height * amount
        let next = CGSize(width: max(2, size.width - dx * 2), height: max(2, size.height - dy * 2))
        let shifted = transform.concatenating(CGAffineTransform(translationX: -dx, y: -dy))
        return (shifted, next)
    }

    static func fit(_ transform: CGAffineTransform, size: CGSize, into target: CGSize) -> CGAffineTransform {
        let scale = min(target.width / max(size.width, 1), target.height / max(size.height, 1))
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        let dx = (target.width - scaled.width) / 2
        let dy = (target.height - scaled.height) / 2
        return transform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    static func even(_ size: CGSize) -> CGSize {
        CGSize(width: max(2, floor(size.width / 2) * 2), height: max(2, floor(size.height / 2) * 2))
    }
}

enum MediaJobs {
    static func compress(urls: [URL], quality: Int, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let presets: [String]
        switch quality {
        case 0:
            presets = [AVAssetExportPreset640x480, AVAssetExportPresetMediumQuality, AVAssetExportPresetLowQuality]
        case 2:
            presets = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1920x1080, AVAssetExportPresetHighestQuality]
        default:
            presets = [AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality, AVAssetExportPresetHighestQuality]
        }
        return try await exportEach(urls, suffix: "-compressed", ext: "mp4", presets: presets, progress: progress)
    }

    static func convert(urls: [URL], ext: String, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let allowed = ["mp4", "mov", "m4v"]
        guard allowed.contains(ext.lowercased()) else {
            throw ToolError(message: "WebM needs a converter this app does not bundle. Choose MP4, MOV, or M4V.")
        }
        return try await exportEach(
            urls,
            suffix: "-converted",
            ext: ext,
            presets: [AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080, AVAssetExportPresetPassthrough],
            progress: progress
        )
    }

    static func trim(urls: [URL], start: Double, end: Double, progress: @escaping (Double) -> Void) async throws -> [URL] {
        return try await map(urls, progress: progress) { url, report in
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            let startClamped = min(max(0, start), max(0, seconds - 0.05))
            let endClamped = end <= 0 ? seconds : min(max(startClamped + 0.05, end), seconds)
            let range = CMTimeRange(
                start: CMTime(seconds: startClamped, preferredTimescale: 600),
                end: CMTime(seconds: endClamped, preferredTimescale: 600)
            )
            let output = try Outputs.make(nextTo: url, suffix: "-trimmed", ext: url.pathExtension.isEmpty ? "mov" : url.pathExtension)
            try await exportTrying(
                asset: asset,
                output: output,
                fileType: MediaExport.fileType(for: output.pathExtension),
                presets: [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality],
                timeRange: range,
                progress: report
            )
            return output
        }
    }

    static func mute(urls: [URL], progress: @escaping (Double) -> Void) async throws -> [URL] {
        return try await map(urls, progress: progress) { url, report in
            let built = try await composition(url: url, mute: true)
            let output = try Outputs.make(nextTo: url, suffix: "-silent", ext: "mp4")
            try await exportBuilt(built, output: output, ext: "mp4", progress: report)
            return output
        }
    }

    static func changeSpeed(urls: [URL], rate: Double, preservePitch: Bool, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let safe = min(4, max(0.25, rate))
        return try await map(urls, progress: progress) { url, report in
            let built = try await composition(url: url, rate: safe, preservePitch: preservePitch)
            let output = try Outputs.make(nextTo: url, suffix: "-speed", ext: "mp4")
            try await exportBuilt(built, output: output, ext: "mp4", progress: report)
            return output
        }
    }

    static func resize(urls: [URL], width: Int, height: Int, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let target = ClipGeometry.even(CGSize(width: CGFloat(max(2, width)), height: CGFloat(max(2, height))))
        return try await map(urls, progress: progress) { url, report in
            let built = try await composition(url: url, outputSize: target)
            let output = try Outputs.make(nextTo: url, suffix: "-resized", ext: "mp4")
            try await exportBuilt(built, output: output, ext: "mp4", progress: report)
            return output
        }
    }

    static func cropRotate(
        urls: [URL],
        quarterTurns: Int,
        inset: Double,
        flipHorizontal: Bool,
        progress: @escaping (Double) -> Void
    ) async throws -> [URL] {
        return try await map(urls, progress: progress) { url, report in
            let built = try await composition(
                url: url,
                quarterTurns: quarterTurns,
                inset: inset,
                flipHorizontal: flipHorizontal
            )
            let output = try Outputs.make(nextTo: url, suffix: "-framed", ext: "mp4")
            try await exportBuilt(built, output: output, ext: "mp4", progress: report)
            return output
        }
    }

    static func merge(urls: [URL], progress: @escaping (Double) -> Void) async throws -> [URL] {
        guard urls.count >= 2 else { throw ToolError(message: "Drop at least two videos.") }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ToolError(message: "Could not start a combined movie.")
        }
        var cursor = CMTime.zero
        var render = CGSize(width: 1280, height: 720)
        let instruction = AVMutableVideoCompositionInstruction()
        var layers: [AVMutableVideoCompositionLayerInstruction] = []
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        for (index, url) in urls.enumerated() {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)
            if let source = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(range, of: source, at: cursor)
                let natural = try await source.load(.naturalSize)
                let preferred = try await source.load(.preferredTransform)
                let oriented = ClipGeometry.oriented(natural: natural, preferred: preferred)
                if index == 0 { render = ClipGeometry.even(oriented.size) }
                let fitted = ClipGeometry.fit(oriented.transform, size: oriented.size, into: render)
                layer.setTransform(fitted, at: cursor)
            }
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
            progress(Double(index + 1) / Double(urls.count + 1))
        }
        instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
        layers.append(layer)
        instruction.layerInstructions = layers
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = render
        let output = try Outputs.make(nextTo: urls[0], suffix: "-merged", ext: "mp4")
        try await MediaExport.export(
            asset: composition,
            output: output,
            fileType: .mp4,
            preset: AVAssetExportPresetHighestQuality,
            videoComposition: videoComposition,
            progress: { value in progress(0.5 + value * 0.5) }
        )
        return [output]
    }

    static func replaceAudio(video: URL, audio: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        let videoDuration = try await videoAsset.load(.duration)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw ToolError(message: "That video has no picture track.")
        }
        guard let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ToolError(message: "That audio file has no sound track.")
        }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ToolError(message: "Could not build the combined file.")
        }
        let range = CMTimeRange(start: .zero, duration: videoDuration)
        try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)
        let audioDuration = try await audioAsset.load(.duration)
        let audioRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(audioDuration, videoDuration))
        try audioTrack.insertTimeRange(audioRange, of: sourceAudio, at: .zero)
        let natural = try await sourceVideo.load(.naturalSize)
        let preferred = try await sourceVideo.load(.preferredTransform)
        let oriented = ClipGeometry.oriented(natural: natural, preferred: preferred)
        let size = ClipGeometry.even(oriented.size)
        let videoComposition = makeVideoComposition(track: videoTrack, transform: oriented.transform, size: size, duration: videoDuration)
        let output = try Outputs.make(nextTo: video, suffix: "-audio", ext: "mp4")
        try await MediaExport.export(
            asset: composition,
            output: output,
            fileType: .mp4,
            preset: AVAssetExportPresetHighestQuality,
            videoComposition: videoComposition,
            progress: progress
        )
        return [output]
    }

    static func extractAudio(urls: [URL], progress: @escaping (Double) -> Void) async throws -> [URL] {
        return try await map(urls, progress: progress) { url, report in
            let asset = AVURLAsset(url: url)
            let output = try Outputs.make(nextTo: url, suffix: "-audio", ext: "m4a")
            try await MediaExport.export(
                asset: asset,
                output: output,
                fileType: .m4a,
                preset: AVAssetExportPresetAppleM4A,
                progress: report
            )
            return output
        }
    }

    static func convertAudio(urls: [URL], ext: String, progress: @escaping (Double) -> Void) async throws -> [URL] {
        return try await map(urls, progress: progress) { url, report in
            let output = try Outputs.make(nextTo: url, suffix: "-converted", ext: ext)
            if ext.lowercased() == "m4a" {
                try await MediaExport.export(
                    asset: AVURLAsset(url: url),
                    output: output,
                    fileType: .m4a,
                    preset: AVAssetExportPresetAppleM4A,
                    progress: report
                )
            } else {
                try await writePCM(url: url, output: output, progress: report)
            }
            return output
        }
    }

    static func trimAudio(urls: [URL], start: Double, end: Double, progress: @escaping (Double) -> Void) async throws -> [URL] {
        return try await map(urls, progress: progress) { url, report in
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(try await asset.load(.duration))
            let startClamped = min(max(0, start), max(0, duration - 0.05))
            let endClamped = end <= 0 ? duration : min(max(startClamped + 0.05, end), duration)
            let range = CMTimeRange(
                start: CMTime(seconds: startClamped, preferredTimescale: 600),
                end: CMTime(seconds: endClamped, preferredTimescale: 600)
            )
            let output = try Outputs.make(nextTo: url, suffix: "-trimmed", ext: "m4a")
            try await MediaExport.export(
                asset: asset,
                output: output,
                fileType: .m4a,
                preset: AVAssetExportPresetAppleM4A,
                timeRange: range,
                progress: report
            )
            return output
        }
    }

    static func frames(url: URL, every seconds: Double, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration > 0 else { throw ToolError(message: "That video has no duration.") }
        let step = max(0.1, seconds)
        let folder = try Outputs.folder(nextTo: url, nameSuffix: "-frames")
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        var outputs: [URL] = []
        var time = 0.0
        var index = 1
        let total = max(1, Int(duration / step))
        while time < duration && index <= 300 {
            let sample = CMTime(seconds: time, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: sample)
            let file = folder.appendingPathComponent(String(format: "frame-%03d.png", index))
            try ImageFiles.write(image, to: file, type: .png, quality: nil)
            outputs.append(file)
            progress(Double(index) / Double(total))
            time += step
            index += 1
        }
        return outputs.isEmpty ? [folder] : [folder]
    }

    static func gif(url: URL, fps: Double, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = min(8, CMTimeGetSeconds(try await asset.load(.duration)))
        guard duration > 0 else { throw ToolError(message: "That video has no duration.") }
        let rate = min(15, max(4, fps))
        let count = max(2, min(48, Int(duration * rate)))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        var images: [CGImage] = []
        for index in 0..<count {
            let sample = CMTime(seconds: duration * Double(index) / Double(count), preferredTimescale: 600)
            let (image, _) = try await generator.image(at: sample)
            images.append(image)
            progress(Double(index) / Double(count))
        }
        let output = try Outputs.make(nextTo: url, suffix: "-animation", ext: "gif")
        try ImageFiles.writeGIF(images, delay: 1.0 / rate, to: output)
        return [output]
    }

    static func info(url: URL) async throws -> [MediaRow] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        var rows = [
            MediaRow(label: "File", value: url.lastPathComponent),
            MediaRow(label: "Duration", value: String(format: "%.2f s", seconds)),
            MediaRow(label: "Size", value: ByteFormat.string(bytes: FileSize.bytes(url)))
        ]
        if let video = try await asset.loadTracks(withMediaType: .video).first {
            let natural = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            let size = ClipGeometry.oriented(natural: natural, preferred: transform).size
            let fps = try await video.load(.nominalFrameRate)
            rows.append(MediaRow(label: "Dimensions", value: "\(Int(size.width)) × \(Int(size.height))"))
            rows.append(MediaRow(label: "Frame rate", value: String(format: "%.2f fps", fps)))
            if let format = (try await video.load(.formatDescriptions)).first {
                rows.append(MediaRow(label: "Video codec", value: fourCC(CMFormatDescriptionGetMediaSubType(format))))
            }
        }
        if let audio = try await asset.loadTracks(withMediaType: .audio).first {
            if let format = (try await audio.load(.formatDescriptions)).first {
                rows.append(MediaRow(label: "Audio codec", value: fourCC(CMFormatDescriptionGetMediaSubType(format))))
            }
            let rate = try await audio.load(.naturalTimeScale)
            rows.append(MediaRow(label: "Audio timescale", value: "\(rate)"))
        }
        if seconds > 0 {
            let bits = Double(FileSize.bytes(url)) * 8 / seconds
            rows.append(MediaRow(label: "Average bitrate", value: String(format: "%.0f kbps", bits / 1000)))
        }
        return rows
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        let text = String(bytes: bytes, encoding: .ascii) ?? String(code)
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func exportEach(
        _ urls: [URL],
        suffix: String,
        ext: String,
        presets: [String],
        progress: @escaping (Double) -> Void
    ) async throws -> [URL] {
        return try await map(urls, progress: progress) { url, report in
            let output = try Outputs.make(nextTo: url, suffix: suffix, ext: ext)
            try await exportTrying(
                asset: AVURLAsset(url: url),
                output: output,
                fileType: MediaExport.fileType(for: ext),
                presets: presets,
                timeRange: nil,
                progress: report
            )
            return output
        }
    }

    private static func exportTrying(
        asset: AVAsset,
        output: URL,
        fileType: AVFileType,
        presets: [String],
        timeRange: CMTimeRange?,
        progress: @escaping (Double) -> Void
    ) async throws {
        var last = ToolError(message: "Export failed.")
        for preset in presets {
            do {
                try await MediaExport.export(
                    asset: asset,
                    output: output,
                    fileType: fileType,
                    preset: preset,
                    timeRange: timeRange,
                    progress: progress
                )
                return
            } catch {
                last = ToolError(message: error.localizedDescription)
                try? FileManager.default.removeItem(at: output)
            }
        }
        throw last
    }

    struct BuiltClip {
        var composition: AVMutableComposition
        var videoComposition: AVMutableVideoComposition
        var audioMix: AVMutableAudioMix?
        var duration: CMTime
    }

    private static func composition(
        url: URL,
        rate: Double = 1,
        preservePitch: Bool = true,
        mute: Bool = false,
        outputSize: CGSize? = nil,
        quarterTurns: Int = 0,
        inset: Double = 0,
        flipHorizontal: Bool = false
    ) async throws -> BuiltClip {
        let asset = AVURLAsset(url: url)
        let full = try await asset.load(.duration)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw ToolError(message: "That file has no video track.")
        }
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ToolError(message: "Could not prepare the video.")
        }
        let range = CMTimeRange(start: .zero, duration: full)
        try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)
        var audioMix: AVMutableAudioMix?
        if !mute, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(range, of: sourceAudio, at: .zero)
            let params = AVMutableAudioMixInputParameters(track: audioTrack)
            params.audioTimePitchAlgorithm = preservePitch ? .spectral : .varispeed
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            audioMix = mix
            if abs(rate - 1) > 0.01 {
                let scaled = CMTimeMultiplyByFloat64(full, multiplier: 1 / rate)
                audioTrack.scaleTimeRange(range, toDuration: scaled)
            }
        }
        if abs(rate - 1) > 0.01 {
            let scaled = CMTimeMultiplyByFloat64(full, multiplier: 1 / rate)
            videoTrack.scaleTimeRange(range, toDuration: scaled)
        }
        let natural = try await sourceVideo.load(.naturalSize)
        let preferred = try await sourceVideo.load(.preferredTransform)
        var oriented = ClipGeometry.oriented(natural: natural, preferred: preferred)
        if flipHorizontal {
            let flip = CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(translationX: oriented.size.width, y: 0))
            oriented.transform = oriented.transform.concatenating(flip)
        }
        let rotated = ClipGeometry.rotate(transform: oriented.transform, size: oriented.size, quarterTurns: quarterTurns)
        let cropped = ClipGeometry.inset(CGFloat(inset), transform: rotated.0, size: rotated.1)
        var size = ClipGeometry.even(cropped.1)
        var transform = cropped.0
        if let outputSize {
            let target = ClipGeometry.even(outputSize)
            transform = ClipGeometry.fit(transform, size: size, into: target)
            size = target
        }
        let duration = abs(rate - 1) > 0.01 ? CMTimeMultiplyByFloat64(full, multiplier: 1 / rate) : full
        let videoComposition = makeVideoComposition(track: videoTrack, transform: transform, size: size, duration: duration)
        return BuiltClip(composition: composition, videoComposition: videoComposition, audioMix: audioMix, duration: duration)
    }

    private static func makeVideoComposition(
        track: AVCompositionTrack,
        transform: CGAffineTransform,
        size: CGSize,
        duration: CMTime
    ) -> AVMutableVideoComposition {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        composition.renderSize = size
        return composition
    }

    private static func exportBuilt(_ built: BuiltClip, output: URL, ext: String, progress: @escaping (Double) -> Void) async throws {
        var last = ToolError(message: "Export failed.")
        for preset in [AVAssetExportPresetHighestQuality, AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality] {
            do {
                try await MediaExport.export(
                    asset: built.composition,
                    output: output,
                    fileType: MediaExport.fileType(for: ext),
                    preset: preset,
                    videoComposition: built.videoComposition,
                    audioMix: built.audioMix,
                    progress: progress
                )
                return
            } catch {
                last = ToolError(message: error.localizedDescription)
                try? FileManager.default.removeItem(at: output)
            }
        }
        throw last
    }

    private static func map(
        _ urls: [URL],
        progress: @escaping (Double) -> Void,
        _ body: (URL, @escaping (Double) -> Void) async throws -> URL
    ) async throws -> [URL] {
        guard !urls.isEmpty else { throw ToolError(message: "Drop a file first.") }
        var outputs: [URL] = []
        for (index, url) in urls.enumerated() {
            let output = try await body(url) { value in
                progress((Double(index) + value) / Double(urls.count))
            }
            outputs.append(output)
        }
        return outputs
    }

    private static func writePCM(url: URL, output: URL, progress: @escaping (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ToolError(message: "That file has no audio track.")
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let outputTrack = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        outputTrack.alwaysCopiesSampleData = false
        guard reader.canAdd(outputTrack) else { throw ToolError(message: "Could not read that audio.") }
        reader.add(outputTrack)
        guard reader.startReading() else {
            throw ToolError(message: reader.error?.localizedDescription ?? "Could not read that audio.")
        }
        guard let format = AVAudioFormat(settings: settings) else {
            throw ToolError(message: "Could not prepare a PCM file.")
        }
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        let file = try AVAudioFile(forWriting: output, settings: format.settings)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        while let sample = outputTrack.copyNextSampleBuffer() {
            try append(sample, format: format, to: file)
            if duration > 0 {
                let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                progress(min(1, time / duration))
            }
        }
        if reader.status == .failed {
            throw ToolError(message: reader.error?.localizedDescription ?? "Could not finish the audio file.")
        }
    }

    private static func append(_ sample: CMSampleBuffer, format: AVAudioFormat, to file: AVAudioFile) throws {
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        if status != noErr { throw ToolError(message: "Could not copy audio samples.") }
        try file.write(from: buffer)
    }
}

struct MediaRow: Identifiable {
    var label: String
    var value: String
    var id: String { label }
}

enum ImageFiles {
    static func load(_ url: URL, maxPixel: CGFloat = 16_000) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ToolError(message: "Could not open \(url.lastPathComponent).")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ToolError(message: "Could not read \(url.lastPathComponent).")
        }
        return image
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double?) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ToolError(message: "Could not create \(url.lastPathComponent).")
        }
        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw ToolError(message: "Could not write \(url.lastPathComponent).")
        }
    }

    static func writeGIF(_ images: [CGImage], delay: Double, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil) else {
            throw ToolError(message: "Could not create the GIF.")
        }
        let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, fileProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]]
        for image in images {
            CGImageDestinationAddImage(destination, image, frameProps as CFDictionary)
        }
        if !CGImageDestinationFinalize(destination) {
            throw ToolError(message: "Could not write the GIF.")
        }
    }

    static func type(for ext: String) -> UTType {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "tif", "tiff": return .tiff
        case "heic": return .heic
        case "gif": return .gif
        case "bmp": return .bmp
        default: return .png
        }
    }
}
