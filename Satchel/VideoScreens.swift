import AppKit
import AVFoundation
import AVFAudio
import AudioToolbox
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import SwiftUI
import SatchelCore

struct VideoToolScreen: View {
    let id: ToolID

    var body: some View {
        switch id {
        case .recordScreen:
            RecordScreenTool()
        case .mergeVideos:
            MergeVideosTool()
        case .replaceAudio:
            ReplaceAudioTool()
        case .mediaInfo:
            MediaInfoTool()
        case .compressVideo:
            CompressVideoTool()
        case .convertVideo:
            ConvertVideoTool()
        case .resizeVideo:
            ResizeVideoTool()
        case .trimVideo:
            TrimMediaTool(video: true)
        case .changeSpeed:
            ChangeSpeedTool()
        case .cropRotateVideo:
            CropRotateTool()
        case .muteVideo:
            MuteVideoTool()
        case .extractFrames:
            ExtractFramesTool()
        case .videoToGIF:
            GIFTool()
        default:
            if let tool = ToolRegistry.byID[id] { ComingSoonView(tool: tool) }
        }
    }
}

struct AudioToolScreen: View {
    let id: ToolID

    var body: some View {
        switch id {
        case .recordAudio:
            RecordAudioTool()
        case .trimAudio:
            TrimMediaTool(video: false)
        case .extractAudio:
            ExtractAudioTool()
        case .convertAudio:
            ConvertAudioTool()
        default:
            if let tool = ToolRegistry.byID[id] { ComingSoonView(tool: tool) }
        }
    }
}

private struct CompressVideoTool: View {
    @State private var quality = 1
    var body: some View {
        FileJobView(tool: .compressVideo, types: MediaTypes.movies, prompt: "Drop videos to shrink", actionTitle: "Compress", tracksSavings: true) {
            Picker("Size", selection: $quality) {
                Text("Smaller").tag(0)
                Text("Balanced").tag(1)
                Text("Sharper").tag(2)
            }
            .pickerStyle(.segmented)
        } perform: { urls, progress in
            try await MediaJobs.compress(urls: urls, quality: quality, progress: progress)
        }
    }
}

private struct ConvertVideoTool: View {
    @State private var format = "mp4"
    var body: some View {
        FileJobView(tool: .convertVideo, types: MediaTypes.movies, prompt: "Drop videos to convert", actionTitle: "Convert") {
            Picker("Format", selection: $format) {
                Text("MP4").tag("mp4")
                Text("MOV").tag("mov")
                Text("M4V").tag("m4v")
            }
            .pickerStyle(.segmented)
            Text("WebM is not available without an extra converter.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } perform: { urls, progress in
            try await MediaJobs.convert(urls: urls, ext: format, progress: progress)
        }
    }
}

private struct ResizeVideoTool: View {
    @State private var width = "1280"
    @State private var height = "720"
    var body: some View {
        FileJobView(tool: .resizeVideo, types: MediaTypes.movies, prompt: "Drop videos to resize", actionTitle: "Resize") {
            HStack {
                TextField("Width", text: $width).frame(width: 100)
                Text("×")
                TextField("Height", text: $height).frame(width: 100)
            }
        } perform: { urls, progress in
            try await MediaJobs.resize(urls: urls, width: Int(width) ?? 1280, height: Int(height) ?? 720, progress: progress)
        }
    }
}

private struct TrimMediaTool: View {
    var video: Bool
    @State private var start = "0"
    @State private var end = ""
    var body: some View {
        FileJobView(
            tool: video ? .trimVideo : .trimAudio,
            types: video ? MediaTypes.movies : MediaTypes.audio,
            prompt: video ? "Drop a video to trim" : "Drop audio to trim",
            actionTitle: "Trim"
        ) {
            HStack {
                TextField("Start seconds", text: $start).frame(width: 140)
                TextField("End seconds", text: $end).frame(width: 140)
            }
            Text("Leave the end empty to keep the rest of the file.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } perform: { urls, progress in
            let startValue = Double(start) ?? 0
            let endValue = Double(end) ?? 0
            if video {
                return try await MediaJobs.trim(urls: urls, start: startValue, end: endValue, progress: progress)
            }
            return try await MediaJobs.trimAudio(urls: urls, start: startValue, end: endValue, progress: progress)
        }
    }
}

private struct ChangeSpeedTool: View {
    @State private var speed = 1.0
    @State private var pitch = true
    var body: some View {
        FileJobView(tool: .changeSpeed, types: MediaTypes.movies, prompt: "Drop a video", actionTitle: "Change speed") {
            HStack {
                Slider(value: $speed, in: 0.25...4)
                Text(String(format: "%.2f×", speed)).frame(width: 54)
            }
            Toggle("Keep the original pitch", isOn: $pitch)
        } perform: { urls, progress in
            try await MediaJobs.changeSpeed(urls: urls, rate: speed, preservePitch: pitch, progress: progress)
        }
    }
}

private struct CropRotateTool: View {
    @State private var turns = 0
    @State private var inset = 0.0
    @State private var flip = false
    var body: some View {
        FileJobView(tool: .cropRotateVideo, types: MediaTypes.movies, prompt: "Drop a video", actionTitle: "Save copy") {
            Picker("Turn", selection: $turns) {
                Text("None").tag(0)
                Text("90°").tag(1)
                Text("180°").tag(2)
                Text("270°").tag(3)
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Trim edges")
                Slider(value: $inset, in: 0...0.3)
            }
            Toggle("Flip horizontally", isOn: $flip)
        } perform: { urls, progress in
            try await MediaJobs.cropRotate(urls: urls, quarterTurns: turns, inset: inset, flipHorizontal: flip, progress: progress)
        }
    }
}

private struct MuteVideoTool: View {
    var body: some View {
        FileJobView(tool: .muteVideo, types: MediaTypes.movies, prompt: "Drop videos to silence", actionTitle: "Remove audio") {
            EmptyView()
        } perform: { urls, progress in
            try await MediaJobs.mute(urls: urls, progress: progress)
        }
    }
}

private struct ExtractFramesTool: View {
    @State private var every = "1"
    var body: some View {
        FileJobView(tool: .extractFrames, types: MediaTypes.movies, prompt: "Drop one video", actionTitle: "Save frames", multiple: false) {
            TextField("Seconds between frames", text: $every).frame(width: 180)
        } perform: { urls, progress in
            guard let url = urls.first else { return [] }
            return try await MediaJobs.frames(url: url, every: Double(every) ?? 1, progress: progress)
        }
    }
}

private struct GIFTool: View {
    @State private var fps = 10.0
    var body: some View {
        FileJobView(tool: .videoToGIF, types: MediaTypes.movies, prompt: "Drop a short clip", actionTitle: "Make GIF", multiple: false) {
            HStack {
                Text("Frames per second")
                Slider(value: $fps, in: 4...15)
                Text("\(Int(fps))").frame(width: 28)
            }
            Text("Uses up to 8 seconds, so the GIF stays a reasonable size.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } perform: { urls, progress in
            guard let url = urls.first else { return [] }
            return try await MediaJobs.gif(url: url, fps: fps, progress: progress)
        }
    }
}

private struct ExtractAudioTool: View {
    var body: some View {
        FileJobView(tool: .extractAudio, types: MediaTypes.movies, prompt: "Drop a video", actionTitle: "Extract audio") {
            EmptyView()
        } perform: { urls, progress in
            try await MediaJobs.extractAudio(urls: urls, progress: progress)
        }
    }
}

private struct ConvertAudioTool: View {
    @State private var format = "m4a"
    var body: some View {
        FileJobView(tool: .convertAudio, types: MediaTypes.audio + MediaTypes.movies, prompt: "Drop audio or video", actionTitle: "Convert") {
            Picker("Format", selection: $format) {
                Text("M4A").tag("m4a")
                Text("WAV").tag("wav")
                Text("AIFF").tag("aiff")
                Text("CAF").tag("caf")
            }
            .pickerStyle(.segmented)
        } perform: { urls, progress in
            try await MediaJobs.convertAudio(urls: urls, ext: format, progress: progress)
        }
    }
}

private struct MergeVideosTool: View {
    @State private var urls: [URL] = []
    @State private var running = false
    @State private var outputs: [URL] = []
    @State private var errorText: String?
    @State private var progress = 0.0

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.mergeVideos)) {
            DropZone(prompt: "Drop videos in the order you want", types: MediaTypes.movies) { urls = $0 }
            ForEach(Array(urls.enumerated()), id: \.element.path) { index, url in
                HStack {
                    Text("\(index + 1). \(url.lastPathComponent)").lineLimit(1)
                    Spacer()
                    Button("Up") { move(index, -1) }.disabled(index == 0)
                    Button("Down") { move(index, 1) }.disabled(index == urls.count - 1)
                }
            }
            PrimaryButton(title: "Merge", enabled: urls.count >= 2 && !running) { run() }
            if running { ProgressView(value: progress) }
            if let errorText { Text(errorText).foregroundStyle(.red) }
            outputList(outputs)
        }
    }

    private func move(_ index: Int, _ delta: Int) {
        let next = index + delta
        guard urls.indices.contains(next) else { return }
        urls.swapAt(index, next)
    }

    private func run() {
        running = true
        errorText = nil
        let current = urls
        Task {
            do {
                let made = try await RunLog.measure(tool: .mergeVideos, inputs: current.count) {
                    try await MediaJobs.merge(urls: current) { progress = $0 }
                }
                outputs = made
            } catch {
                errorText = error.localizedDescription
            }
            running = false
        }
    }
}

private struct ReplaceAudioTool: View {
    @State private var video: URL?
    @State private var audio: URL?
    @State private var running = false
    @State private var outputs: [URL] = []
    @State private var errorText: String?

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.replaceAudio)) {
            DropZone(prompt: "Drop the video", types: MediaTypes.movies, multiple: false) { video = $0.first }
            if let video { Text(video.lastPathComponent).font(.system(size: 12)) }
            DropZone(prompt: "Drop the new soundtrack", types: MediaTypes.audio, multiple: false) { audio = $0.first }
            if let audio { Text(audio.lastPathComponent).font(.system(size: 12)) }
            PrimaryButton(title: "Replace audio", enabled: video != nil && audio != nil && !running) { run() }
            if let errorText { Text(errorText).foregroundStyle(.red) }
            outputList(outputs)
        }
    }

    private func run() {
        guard let video, let audio else { return }
        running = true
        errorText = nil
        Task {
            do {
                let made = try await RunLog.measure(tool: .replaceAudio, inputs: 2) {
                    try await MediaJobs.replaceAudio(video: video, audio: audio) { _ in }
                }
                outputs = made
            } catch {
                errorText = error.localizedDescription
            }
            running = false
        }
    }
}

private struct MediaInfoTool: View {
    @State private var rows: [MediaRow] = []
    @State private var errorText: String?
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.mediaInfo)) {
            DropZone(prompt: "Drop a video or audio file", types: MediaTypes.movies + MediaTypes.audio, multiple: false) { urls in
                guard let url = urls.first else { return }
                Task {
                    do {
                        let start = Date()
                        let loaded = try await MediaJobs.info(url: url)
                        rows = loaded
                        errorText = nil
                        SatchelLog.toolRun(id: ToolID.mediaInfo.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                    } catch {
                        errorText = error.localizedDescription
                        SatchelLog.toolRun(id: ToolID.mediaInfo.rawValue, inputs: 1, outcome: "failed", seconds: "0s")
                    }
                }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
            ForEach(rows) { row in
                HStack {
                    Text(row.label).frame(width: 140, alignment: .leading).foregroundStyle(.secondary)
                    Text(row.value)
                    Spacer()
                }
                .font(.system(size: 13))
            }
        }
    }
}

private struct RecordScreenTool: View {
    @StateObject private var recorder = DisplayRecorder()
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.recordScreen)) {
            Text("macOS will ask for screen recording permission the first time. The movie is saved in Movies/Satchel.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            PrimaryButton(title: recorder.recording ? "Stop and save" : "Record display", enabled: true) {
                Task {
                    if recorder.recording {
                        let start = Date()
                        if let url = await recorder.stop() {
                            recorder.message = "Saved \(url.lastPathComponent)"
                            SatchelLog.toolRun(id: ToolID.recordScreen.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                        }
                    } else {
                        await recorder.start()
                    }
                }
            }
            if recorder.recording { ProgressView().controlSize(.small) }
            Text(recorder.message).font(.system(size: 13))
            if let url = recorder.output, !recorder.recording {
                Button("Reveal in Finder") { Outputs.reveal(url) }
            }
        }
    }
}

final class DisplayRecorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published var recording = false
    @Published var message = ""
    @Published var output: URL?
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private let queue = DispatchQueue(label: "satchel.screen.record")

    func start() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw ToolError(message: "No display is available.") }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 5
            let folder = try Outputs.directory(in: .moviesDirectory, subfolder: "Satchel")
            let url = folder.appendingPathComponent("Recording-\(Int(Date().timeIntervalSince1970)).mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: display.width,
                AVVideoHeightKey: display.height
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw ToolError(message: "Could not prepare the recording.") }
            writer.add(input)
            writer.startWriting()
            self.writer = writer
            self.input = input
            self.output = url
            sessionStarted = false
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            await MainActor.run {
                self.recording = true
                self.message = "Recording this display. Click Stop when you are done."
            }
        } catch {
            await MainActor.run {
                self.message = error.localizedDescription
                self.recording = false
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sampleBuffer), let input, input.isReadyForMoreMediaData else { return }
        if !sessionStarted {
            sessionStarted = true
            writer?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        input.append(sampleBuffer)
    }

    func stop() async -> URL? {
        try? await stream?.stopCapture()
        stream = nil
        input?.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if let writer {
                writer.finishWriting { continuation.resume() }
            } else {
                continuation.resume()
            }
        }
        await MainActor.run { self.recording = false }
        return output
    }
}

private struct RecordAudioTool: View {
    @State private var recorder: AVAudioRecorder?
    @State private var recording = false
    @State private var message = ""
    @State private var file: URL?

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.recordAudio)) {
            Text("The microphone is used only while you record. The file is saved in Music/Satchel.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            PrimaryButton(title: recording ? "Stop" : "Record", enabled: true) {
                Task { await toggle() }
            }
            Text(message).font(.system(size: 13))
            if let file, !recording {
                Button("Reveal in Finder") { Outputs.reveal(file) }
            }
        }
    }

    private func toggle() async {
        if recording {
            recorder?.stop()
            recording = false
            message = "Saved \(file?.lastPathComponent ?? "the recording")."
            SatchelLog.toolRun(id: ToolID.recordAudio.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
            return
        }
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            message = "Microphone access is off for Satchel."
            return
        }
        do {
            let folder = try Outputs.directory(in: .musicDirectory, subfolder: "Satchel")
            let url = folder.appendingPathComponent("Recording-\(Int(Date().timeIntervalSince1970)).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let audio = try AVAudioRecorder(url: url, settings: settings)
            audio.record()
            recorder = audio
            file = url
            recording = true
            message = "Recording…"
        } catch {
            message = error.localizedDescription
        }
    }
}

func outputList(_ urls: [URL]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        ForEach(urls, id: \.path) { url in
            HStack {
                Text(url.lastPathComponent).lineLimit(1)
                Spacer()
                Button("Reveal in Finder") { Outputs.reveal(url) }
            }
        }
    }
}
