import AVFoundation
import AVFAudio
import CoreMedia
import Speech
import Foundation

enum SpeechJobs {
    struct Transcript {
        var plain: String
        var timestamped: String
        var srt: String
    }

    static func transcribe(url: URL, progress: @escaping (Double) -> Void) async throws -> Transcript {
        let granted = await authorizeSpeech()
        guard granted else { throw ToolError(message: "Speech recognition is turned off for Satchel in System Settings.") }
        let audioURL = try await extractWAV(url)
        let asset = AVURLAsset(url: audioURL)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let chunk: Double = 45
        var pieces: [Piece] = []
        if duration <= chunk + 1 {
            pieces = try await recognize(audioURL, offset: 0)
            progress(1)
        } else {
            var start = 0.0
            var index = 0
            let total = Int(ceil(duration / chunk))
            while start < duration {
                let end = min(duration, start + chunk)
                let slice = FileManager.default.temporaryDirectory.appendingPathComponent("satchel-chunk-\(index).m4a")
                try await exportRange(asset: AVURLAsset(url: audioURL), start: start, end: end, output: slice)
                let found = try await recognize(slice, offset: start)
                pieces.append(contentsOf: found)
                try? FileManager.default.removeItem(at: slice)
                index += 1
                start = end
                progress(Double(index) / Double(max(1, total)))
            }
        }
        if pieces.isEmpty { throw ToolError(message: "No speech was recognized. On-device recognition may need a language download in System Settings.") }
        let plain = pieces.map(\.text).joined(separator: " ")
        let timestamped = pieces.map { "\(stamp($0.start))  \($0.text)" }.joined(separator: "\n")
        var srt = ""
        for (index, piece) in pieces.enumerated() {
            srt += "\(index + 1)\n\(srtTime(piece.start)) --> \(srtTime(piece.end))\n\(piece.text)\n\n"
        }
        return Transcript(plain: plain, timestamped: timestamped, srt: srt)
    }

    static func speak(text: String, language: String, progress: @escaping (Double) -> Void) async throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ToolError(message: "Type something to speak.") }
        let folder = try Outputs.directory(in: .musicDirectory, subfolder: "Satchel")
        let name = "Speech-\(Self.fileStamp()).wav"
        let output = folder.appendingPathComponent(name)
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: trimmed)
        if let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        var file: AVAudioFile?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    gate.resume(continuation)
                    return
                }
                do {
                    if file == nil {
                        file = try AVAudioFile(forWriting: output, settings: pcm.format.settings)
                    }
                    try file?.write(from: pcm)
                    progress(0.5)
                } catch {
                    gate.fail(continuation, error)
                }
            }
        }
        progress(1)
        return output
    }

    private struct Piece {
        var start: Double
        var end: Double
        var text: String
    }

    private static func authorizeSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func extractWAV(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        if try await asset.loadTracks(withMediaType: .audio).isEmpty {
            throw ToolError(message: "That file has no audio track.")
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("satchel-speech-\(UUID().uuidString).m4a")
        try await MediaExport.export(asset: asset, output: output, fileType: .m4a, preset: AVAssetExportPresetAppleM4A, progress: { _ in })
        return output
    }

    private static func exportRange(asset: AVURLAsset, start: Double, end: Double, output: URL) async throws {
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        try await MediaExport.export(
            asset: asset,
            output: output,
            fileType: .m4a,
            preset: AVAssetExportPresetAppleM4A,
            timeRange: range,
            progress: { _ in }
        )
    }

    private static func recognize(_ url: URL, offset: Double) async throws -> [Piece] {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw ToolError(message: "Speech recognition is not available on this Mac.")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            recognizer.recognitionTask(with: request) { result, error in
                func pieces(from result: SFSpeechRecognitionResult) -> [Piece] {
                    result.bestTranscription.segments.map { segment in
                        Piece(
                            start: offset + segment.timestamp,
                            end: offset + segment.timestamp + segment.duration,
                            text: segment.substring
                        )
                    }
                }
                if let result, result.isFinal {
                    gate.succeed(continuation, pieces(from: result))
                    return
                }
                if let error {
                    if let result, !result.bestTranscription.segments.isEmpty {
                        gate.succeed(continuation, pieces(from: result))
                    } else {
                        gate.fail(continuation, error)
                    }
                }
            }
        }
    }

    private static func stamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func srtTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let hours = Int(clamped) / 3600
        let minutes = (Int(clamped) % 3600) / 60
        let secs = Int(clamped) % 60
        let millis = Int((clamped - floor(clamped)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume()
    }

    func fail(_ continuation: CheckedContinuation<Void, Error>, _ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(throwing: error)
    }

    func succeed<T>(_ continuation: CheckedContinuation<T, Error>, _ value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value)
    }

    func fail<T>(_ continuation: CheckedContinuation<T, Error>, _ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(throwing: error)
    }
}
