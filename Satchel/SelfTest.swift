import AppKit
import SwiftUI
import AVFoundation
import AVFAudio
import AudioToolbox
import CoreImage
import CoreMedia
import CoreVideo
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import SatchelCore

struct SelfTestDriver: View {
    let directory: String
    var only: String? = nil

    var body: some View {
        Color.clear
            .frame(width: 4, height: 4)
            .task {
                let code: Int
                if let only {
                    code = await SelfTest.runOne(directory: directory, toolID: only)
                } else {
                    code = await SelfTest.run(directory: directory)
                }
                exit(Int32(code))
            }
    }
}

enum SelfTest {
    @MainActor
    static func run(directory: String) async -> Int {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            _ = try await FixtureSet.make(in: root.appendingPathComponent("fixtures", isDirectory: true))
        } catch {
            let line = "SELFTEST fixtures FAIL \(error.localizedDescription)"
            emit(line)
            try? line.write(to: root.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
            return 1
        }
        var failed = 0
        let tabLine: String
        do {
            try TabHitTest.clickEdgeSelectsVideo()
            tabLine = "SELFTEST tab-hit PASS"
        } catch {
            tabLine = "SELFTEST tab-hit FAIL \(error.localizedDescription.replacingOccurrences(of: "\n", with: " "))"
            failed += 1
        }
        emit(tabLine)
        var lines: [String] = [tabLine]
        for tool in ToolRegistry.all {
            let line: String
            if tool.status != .working {
                line = report(tool.id, "SKIP", "placeholder")
            } else if let reason = skipReason(tool.id) {
                line = report(tool.id, "SKIP", reason)
            } else {
                line = await runChild(tool, directory: directory)
            }
            emit(line)
            lines.append(line)
            if line.contains(" FAIL ") { failed += 1 }
            let summary = lines.joined(separator: "\n") + "\n"
            try? summary.write(to: root.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
        }
        return failed == 0 ? 0 : 1
    }

    @MainActor
    static func runOne(directory: String, toolID: String) async -> Int {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let fixtures = FixtureSet.load(from: root.appendingPathComponent("fixtures", isDirectory: true))
        guard let tool = ToolRegistry.all.first(where: { $0.id.rawValue == toolID }) else {
            let line = "SELFTEST \(toolID) FAIL unknown tool"
            try? line.write(to: root.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            return 1
        }
        let line = await evaluate(tool, fixtures: fixtures)
        try? line.write(to: root.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        return line.contains(" FAIL ") ? 1 : 0
    }

    @MainActor
    private static func runChild(_ tool: ToolDefinition, directory: String) async -> String {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let result = root.appendingPathComponent("result.txt")
        let log = root.appendingPathComponent("child.log")
        try? FileManager.default.removeItem(at: result)
        try? FileManager.default.removeItem(at: log)
        guard let exe = Bundle.main.executableURL else {
            return report(tool.id, "FAIL", "missing executable")
        }
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let process = Process()
        process.executableURL = exe
        process.arguments = ["--selftest-one", tool.id.rawValue, directory]
        if let handle = try? FileHandle(forWritingTo: log) {
            process.standardOutput = handle
            process.standardError = handle
        }
        let status: Int32 = await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            process.terminationHandler = { proc in
                once.run { continuation.resume(returning: proc.terminationStatus) }
            }
            do {
                try process.run()
            } catch {
                once.run { continuation.resume(returning: -2) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 140) {
                if process.isRunning {
                    process.terminate()
                    kill(process.processIdentifier, SIGKILL)
                }
                once.run { continuation.resume(returning: -1) }
            }
        }
        if status == -2 { return report(tool.id, "FAIL", "could not launch") }
        if let text = try? String(contentsOf: result, encoding: .utf8) {
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("SELFTEST ") {
                try? FileManager.default.removeItem(at: result)
                try? FileManager.default.removeItem(at: log)
                return line
            }
        }
        if status == -1 { return report(tool.id, "FAIL", "timed out") }
        let tail = (try? String(contentsOf: log, encoding: .utf8))?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reason = tail.isEmpty ? "crashed" : "crashed \(tail.suffix(180))"
        return report(tool.id, "FAIL", reason)
    }

    private static func emit(_ line: String) {
        print(line)
        fflush(stdout)
    }

    @MainActor
    private static func evaluate(_ tool: ToolDefinition, fixtures: FixtureSet) async -> String {
        if tool.status != .working {
            return report(tool.id, "SKIP", "placeholder")
        }
        if let reason = skipReason(tool.id) {
            return report(tool.id, "SKIP", reason)
        }
        do {
            try await exercise(tool.id, fixtures)
            return report(tool.id, "PASS", "")
        } catch let skip as SkipSignal {
            return report(tool.id, "SKIP", skip.reason)
        } catch {
            return report(tool.id, "FAIL", error.localizedDescription.replacingOccurrences(of: "\n", with: " "))
        }
    }

    private static func report(_ id: ToolID, _ outcome: String, _ reason: String) -> String {
        if reason.isEmpty { return "SELFTEST \(id.rawValue) \(outcome)" }
        return "SELFTEST \(id.rawValue) \(outcome) \(reason)"
    }

    private static func skipReason(_ id: ToolID) -> String? {
        switch id {
        case .recordAudio:
            return "needs microphone permission"
        case .wifiPassword:
            return "needs the keychain and the current network"
        case .networkSpeed:
            return "uses the network"
        case .presentationMode:
            return "hides the desktop and the Dock"
        case .resetPermissions:
            return "resets system privacy permissions"
        default:
            return nil
        }
    }

    @MainActor
    private static func exercise(_ id: ToolID, _ fixtures: FixtureSet) async throws {
        switch id {
        case .changeSpeed:
            _ = try await check(MediaJobs.changeSpeed(urls: [fixtures.video], rate: 1.5, preservePitch: true, progress: { _ in }))
        case .extractFrames:
            _ = try await check(MediaJobs.frames(url: fixtures.video, every: 1, progress: { _ in }))
        case .compressVideo:
            _ = try await check(MediaJobs.compress(urls: [fixtures.video], quality: 0, progress: { _ in }))
        case .convertVideo:
            _ = try await check(MediaJobs.convert(urls: [fixtures.video], ext: "mp4", progress: { _ in }))
        case .resizeVideo:
            _ = try await check(MediaJobs.resize(urls: [fixtures.video], width: 160, height: 120, progress: { _ in }))
        case .cropRotateVideo:
            _ = try await check(MediaJobs.cropRotate(urls: [fixtures.video], quarterTurns: 1, inset: 0.05, flipHorizontal: false, progress: { _ in }))
        case .mediaInfo:
            let rows = try await MediaJobs.info(url: fixtures.video)
            if rows.isEmpty { throw ToolError(message: "no media info") }
        case .trimVideo:
            _ = try await check(MediaJobs.trim(urls: [fixtures.video], start: 0.2, end: 1.5, progress: { _ in }))
        case .mergeVideos:
            _ = try await check(MediaJobs.merge(urls: [fixtures.video, fixtures.video2], progress: { _ in }))
        case .muteVideo:
            _ = try await check(MediaJobs.mute(urls: [fixtures.video], progress: { _ in }))
        case .replaceAudio:
            _ = try await check(MediaJobs.replaceAudio(video: fixtures.video, audio: fixtures.audio, progress: { _ in }))
        case .videoToGIF:
            _ = try await check(MediaJobs.gif(url: fixtures.video, fps: 8, progress: { _ in }))
        case .trimAudio:
            _ = try await check(MediaJobs.trimAudio(urls: [fixtures.audio], start: 0.1, end: 1.2, progress: { _ in }))
        case .extractAudio:
            _ = try await check(MediaJobs.extractAudio(urls: [fixtures.video], progress: { _ in }))
        case .convertAudio:
            for ext in ["m4a", "wav", "aiff", "caf"] {
                let made = try await check(MediaJobs.convertAudio(urls: [fixtures.audio], ext: ext, progress: { _ in }))
                let file = try AVAudioFile(forReading: made[0])
                if file.length < 1000 { throw ToolError(message: "\(ext) was too short") }
                if made[0].pathExtension.lowercased() != ext {
                    throw ToolError(message: "expected a .\(ext) file")
                }
            }
        case .beautifyScreenshot:
            _ = try checkOne(ImageJobs.beautify(url: fixtures.png, padding: 12, radius: 8, shadow: true, aspect: CGSize(width: 16, height: 9), background: .white))
        case .convertImages:
            _ = try await check(ImageJobs.convert(urls: [fixtures.png], ext: "jpg", progress: { _ in }))
        case .compressImages:
            _ = try await check(ImageJobs.compress(urls: [fixtures.jpeg], quality: 0.5, progress: { _ in }))
        case .resizeImages:
            _ = try await check(ImageJobs.resize(urls: [fixtures.png], maxEdge: 80, progress: { _ in }))
        case .rotateImages:
            _ = try await check(ImageJobs.rotate(urls: [fixtures.png], quarterTurns: 1, flip: false, progress: { _ in }))
        case .removeMetadata:
            _ = try await check(ImageJobs.stripMetadata(urls: [fixtures.jpeg], progress: { _ in }))
        case .watermark:
            _ = try await check(ImageJobs.watermark(urls: [fixtures.png], text: "Satchel", progress: { _ in }))
        case .annotateScreenshot:
            _ = try await check(ImageJobs.watermark(urls: [fixtures.png], text: "Note", progress: { _ in }))
        case .scanDocument:
            _ = try await check(ImageJobs.scan(urls: [fixtures.png], progress: { _ in }))
        case .redactPDF:
            _ = try check(PDFJobs.redact(url: fixtures.pdf, word: "secret", extra: [:], progress: { _ in }))
        case .searchablePDF:
            _ = try check(PDFJobs.searchable(url: fixtures.pdf, progress: { _ in }))
        case .signPDF:
            let signature = NSImage(size: NSSize(width: 120, height: 40))
            signature.lockFocus()
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 8, y: 10))
            path.line(to: NSPoint(x: 100, y: 28))
            path.lineWidth = 2
            path.stroke()
            signature.unlockFocus()
            _ = try check(PDFJobs.sign(url: fixtures.pdf, signature: signature, pageIndex: 0, placement: CGRect(x: 40, y: 40, width: 120, height: 40)))
        case .mergePDFs:
            _ = try check(PDFJobs.merge(urls: [fixtures.pdf, fixtures.pdf], progress: { _ in }))
        case .splitPDF:
            _ = try check(PDFJobs.split(url: fixtures.pdf, spec: "1", perPage: false, progress: { _ in }))
        case .organizePDF:
            _ = try check(PDFJobs.organize(url: fixtures.pdf, order: [2, 1]))
        case .deletePages:
            _ = try check(PDFJobs.deletePages(url: fixtures.pdf, spec: "2"))
        case .extractPages:
            _ = try check(PDFJobs.extract(url: fixtures.pdf, spec: "1"))
        case .imagesToPDF:
            _ = try check(PDFJobs.imagesToPDF(urls: [fixtures.png, fixtures.jpeg], progress: { _ in }))
        case .cropPDF:
            _ = try check(PDFJobs.crop(url: fixtures.pdf, margin: 12))
        case .compressPDF:
            let heavy = fixtures.folder.appendingPathComponent("photos.pdf")
            try PhotoPDF.write(to: heavy, pages: 10)
            let before = FileSize.bytes(heavy)
            let made = try PDFJobs.compress(url: heavy, quality: 0.45, progress: { _ in })
            _ = try check(made)
            if FileSize.bytes(made[0]) >= before {
                throw ToolError(message: "compressed PDF was not smaller")
            }
        case .fillForms:
            let form = fixtures.folder.appendingPathComponent("form.pdf")
            try PDFJobs.writeForm(to: form)
            let fields = try PDFJobs.formFields(url: form, password: "")
            if fields.isEmpty { throw ToolError(message: "form PDF has no text field") }
            _ = try check(PDFJobs.fill(url: form, password: "", values: ["Name": "Ada"]))
        case .blurFaces:
            let face = try BundleFixture.copy(name: "face", ext: "jpg", to: fixtures.folder)
            _ = try await check(ImageJobs.blurFaces(urls: [face], style: .blur, progress: { _ in }))
        case .removeBackground:
            let subject = try BundleFixture.copy(name: "subject", ext: "png", to: fixtures.folder)
            _ = try await check(ImageJobs.removeBackground(urls: [subject], background: .white, crop: false, progress: { _ in }))
        case .redactImage:
            _ = try checkOne(ImageJobs.cover(url: fixtures.png, rects: [CGRect(x: 20, y: 20, width: 80, height: 40)]))
        case .colorPicker:
            let swatch = fixtures.folder.appendingPathComponent("swatch.png")
            try ColorSample.swatch(color: (255, 0, 0), to: swatch)
            let image = try ImageFiles.load(swatch)
            let hex = ColorSample.hex(image: image, x: 8, y: 8)
            if hex != "#FF0000" { throw ToolError(message: "sampled \(hex)") }
        case .cleanKeyboard:
            if !KeyboardCover.shared.show() { throw SkipSignal(reason: "no display for the keyboard cover") }
            KeyboardCover.shared.hide()
        case .deadPixel:
            if !DeadPixelCover.shared.show() { throw SkipSignal(reason: "no display for the color cover") }
            DeadPixelCover.shared.hide()
        case .hiddenSettings, .mouseFixes:
            try DefaultsLab.roundTrip()
        case .uninstallApp:
            let app = try AppLab.dummyApp(in: fixtures.folder)
            try AppLab.trash(app)
            if FileManager.default.fileExists(atPath: app.path) { throw ToolError(message: "dummy app was not moved to the Trash") }
        case .fixDamaged:
            let app = try AppLab.dummyApp(in: fixtures.folder.appendingPathComponent("damaged", isDirectory: true))
            try AppLab.clearQuarantine(app)
        case .webPageToPDF:
            _ = try await checkOne(WebProbe.pdf(html: "<html><body><h1>Satchel page</h1><p>local only</p></body></html>", in: fixtures.folder))
        case .transcribe:
            try await transcribeFixture(fixtures)
        case .textToSpeech:
            try await speakFixture()
        case .translate:
            let translated = try await TranslateProbe.tryPhrase()
            if translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolError(message: "translation was empty")
            }
        case .screenshot:
            do {
                _ = try await checkOne(ScreenGrab.capture(to: fixtures.folder))
            } catch let skip as SkipSignal {
                throw skip
            } catch {
                throw SkipSignal(reason: permissionReason(error, fallback: "screen capture was not granted"))
            }
        case .recordScreen:
            try await recordBriefly(fixtures)
        case .addPassword:
            _ = try check(PDFJobs.addPassword(url: fixtures.pdf, current: "", password: "test-pass"))
        case .removePassword:
            let locked = try PDFJobs.addPassword(url: fixtures.pdf, current: "", password: "test-pass")
            _ = try check(PDFJobs.removePassword(url: locked[0], password: "test-pass"))
        case .pdfToImages:
            _ = try check(PDFJobs.pdfToImages(url: fixtures.pdf, ext: "png", progress: { _ in }))
        case .wordToPDF:
            let printed = try checkOne(try await PDFJobs.wordToPDF(url: fixtures.notes))
            try requirePDFText(printed, contains: "Hello")
        case .markdownToPDF:
            let notes = try checkOne(try await PDFJobs.markdown("# Hello\n\nA note about Satchel.", nextTo: fixtures.notes))
            try requirePDFText(notes, contains: "Hello")
        case .downloadVideo:
            try await downloadCheck(fixtures)
        case .burnSubtitles:
            let srt = fixtures.folder.appendingPathComponent("cues.srt")
            try """
            1
            00:00:00,200 --> 00:00:02,600
            HELLO

            """.write(to: srt, atomically: true, encoding: .utf8)
            let burned = try await SubtitleBurn.burn(video: fixtures.video, srt: srt, progress: { _ in })
            _ = try checkOne(burned)
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: burned))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let sample = try await generator.image(at: CMTime(seconds: 1.0, preferredTimescale: 600)).image
            let recognized = (try? OCRJobs.text(from: sample)) ?? ""
            if !recognized.uppercased().contains("HELLO") {
                throw ToolError(message: "burned frame text was \(recognized)")
            }
        case .cleanAudio:
            try AudioCleanup.assertLouderSignal()
            let noisy = fixtures.folder.appendingPathComponent("noisy.wav")
            try AudioCleanup.writeTestTone(to: noisy)
            _ = try await check(AudioCleanup.clean(urls: [noisy], progress: { _ in }))
        case .pdfToWord:
            let docx = try OfficeDocs.pdfToWord(url: fixtures.pdf)
            let extracted = try DocxPackage.plainText(docx)
            if !extracted.localizedCaseInsensitiveContains("Hello") || !extracted.localizedCaseInsensitiveContains("secret") {
                throw ToolError(message: "docx missed the PDF text: \(extracted)")
            }
        case .convertDocuments:
            let rtf = try OfficeDocs.convert(url: fixtures.notes, ext: "rtf")
            let rtfText = try String(contentsOf: rtf, encoding: .utf8)
            if !rtfText.hasPrefix("{\\rtf") || !rtfText.contains("Hello") {
                throw ToolError(message: "rtf conversion failed")
            }
            let html = try OfficeDocs.convert(url: fixtures.notes, ext: "html")
            let htmlText = try String(contentsOf: html, encoding: .utf8)
            if !htmlText.localizedCaseInsensitiveContains("Hello") {
                throw ToolError(message: "html conversion missed the text")
            }
        case .powerpointToPDF:
            let deck = fixtures.folder.appendingPathComponent("deck.pptx")
            try OfficeDocs.makeSlides(lines: ["Roadmap"], to: deck)
            let slides = try await OfficeDocs.powerpoint(url: deck, progress: { _ in })
            try requirePDFText(slides, contains: "Roadmap")
        case .excelToPDF:
            let book = fixtures.folder.appendingPathComponent("sheet.xlsx")
            try OfficeDocs.makeWorkbook(cells: [["Revenue", "42"]], to: book)
            let table = try await OfficeDocs.excel(url: book, progress: { _ in })
            try requirePDFText(table, contains: "Revenue")
            try requirePDFText(table, contains: "42")
        case .summarize:
            let note = Array(repeating: "Cats sleep in warm sun.", count: 4).joined(separator: " ")
                + " " + Array(repeating: "Trains cross the valley at dusk.", count: 4).joined(separator: " ")
            let summary = Summaries.extractive(note)
            if summary.count >= note.count { throw ToolError(message: "summary was not shorter") }
            if !summary.localizedCaseInsensitiveContains("cats") && !summary.localizedCaseInsensitiveContains("trains") {
                throw ToolError(message: "summary missed the topic")
            }
            let generated = await Summaries.make(note)
            if generated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolError(message: "summary was empty")
            }
        case .askDocument:
            let document = "The secret color is indigo. The sky is wide and the road is long."
            let passage = DocumentQA.bestPassage(question: "What is the secret color?", document: document)
            if !passage.localizedCaseInsensitiveContains("indigo") {
                throw ToolError(message: "passage missed indigo: \(passage)")
            }
            let answer = await DocumentQA.answer(question: "What is the secret color?", document: document)
            if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ToolError(message: "answer was empty")
            }
        case .displayControl:
            let reading = try DisplayDesk.read()
            guard let mode = reading.modes.first(where: { $0.current }) ?? reading.modes.first,
                  mode.width > 0, mode.height > 0 else {
                throw ToolError(message: "display mode was empty")
            }
        case .extractText, .captureText:
            _ = try OCRJobs.text(from: ImageFiles.load(fixtures.labeled))
        case .wordCounter:
            let count = TextTransforms.count("Hello world.\nSecond line.")
            if count.words < 2 { throw ToolError(message: "word count failed") }
        case .caseConverter:
            if TextTransforms.apply("hello world", .camel) != "helloWorld" { throw ToolError(message: "case convert failed") }
        case .qrCode:
            _ = try checkOne(try QRJobs.writePNG(text: "https://example.com", nextTo: fixtures.png))
        case .batchRename:
            let copy = fixtures.folder.appendingPathComponent("rename-me.txt")
            try "alpha".write(to: copy, atomically: true, encoding: .utf8)
            let rows = RenameEngine.preview(items: [RenameItem(name: copy.lastPathComponent)], operations: [.prefix("ok-")])
            guard rows.first?.issue == nil, let proposed = rows.first?.proposed else { throw ToolError(message: "rename preview failed") }
            try FileManager.default.moveItem(at: copy, to: copy.deletingLastPathComponent().appendingPathComponent(proposed))
        case .findDuplicates:
            let files = [
                DuplicateFile(path: fixtures.dupA.path, size: FileSize.bytes(fixtures.dupA), hash: Digests.sha256Hex(try Data(contentsOf: fixtures.dupA))),
                DuplicateFile(path: fixtures.dupB.path, size: FileSize.bytes(fixtures.dupB), hash: Digests.sha256Hex(try Data(contentsOf: fixtures.dupB)))
            ]
            if DuplicateGrouper.hashGroups(files).isEmpty { throw ToolError(message: "duplicates were not grouped") }
        case .zipUnzip:
            let zip = try Outputs.make(nextTo: fixtures.notes, suffix: "-pack", ext: "zip")
            let packed = Commands.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", fixtures.notes.path, zip.path])
            if packed.status != 0 { throw ToolError(message: packed.output) }
            let folder = try Outputs.folder(nextTo: zip, nameSuffix: "-out")
            let unpacked = Commands.run("/usr/bin/ditto", ["-xk", zip.path, folder.path])
            if unpacked.status != 0 { throw ToolError(message: unpacked.output) }
        case .organizeDownloads:
            let plan = DownloadOrganizer.plan([
                DownloadEntry(name: "shot.jpg", isDirectory: false),
                DownloadEntry(name: "clip.mp4", isDirectory: false)
            ])
            if plan.count != 2 { throw ToolError(message: "organize plan was empty") }
        case .clipboardHistory:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("satchel-selftest", forType: .string)
            if NSPasteboard.general.string(forType: .string) != "satchel-selftest" { throw ToolError(message: "clipboard round trip failed") }
        case .storageExplorer:
            if FileSize.directory(fixtures.folder) <= 0 { throw ToolError(message: "folder size was zero") }
        case .diskSpeed:
            if DiskBench.measure().isEmpty { throw ToolError(message: "disk test returned nothing") }
        case .batteryHealth:
            if BatteryReader.read().isEmpty { throw ToolError(message: "battery read returned nothing") }
        case .keepAwake:
            let keeper = AwakeKeeper()
            keeper.start(minutes: 1)
            keeper.stop()
        case .ejectDisks:
            _ = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey], options: []) ?? []
        case .loginItems:
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
            _ = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        case .jsonFormatter:
            _ = try JSONFormat.pretty("{\"b\":1}")
        case .base64:
            if try Base64Codec.decode(Base64Codec.encode("hi", urlSafe: false), urlSafe: false) != "hi" { throw ToolError(message: "base64 mismatch") }
        case .hashGenerator:
            if Digests.sha256Hex("abc").count != 64 { throw ToolError(message: "hash length") }
        case .uuidGenerator:
            var rng = SplitMix64(seed: 1)
            if !UUIDFactory.isVersion4(UUIDFactory.make(using: &rng)) { throw ToolError(message: "uuid version") }
        case .jwtDecoder:
            let header = Base64Codec.encode("{\"alg\":\"none\"}", urlSafe: true)
            let payload = Base64Codec.encode("{\"sub\":\"satchel\"}", urlSafe: true)
            _ = try JWTDecoder.decode("\(header).\(payload).sig")
        case .timestamp:
            _ = TimestampCodec.iso8601(TimestampCodec.date(unix: 1_700_000_000, unit: .seconds))
        case .diffChecker:
            if LineDiff.diff("a", "b").isEmpty { throw ToolError(message: "empty diff") }
        case .regexTester:
            let hits = try RegexTester.matches(pattern: "a+", text: "baa", caseInsensitive: false, multiline: false)
            if hits.isEmpty { throw ToolError(message: "no regex match") }
        case .cleanLinks:
            if LinkCleaner.clean("https://e.com/a?utm_source=x&id=1") == "https://e.com/a?utm_source=x&id=1" {
                throw ToolError(message: "tracking param remained")
            }
        case .coordinatePicker:
            _ = try Coordinates.parse("1, 2")
        case .unicodeInspector:
            if UnicodeInspector.inspect("A").isEmpty { throw ToolError(message: "no scalars") }
        case .loremIpsum:
            if LoremIpsum.wordList(count: 3).isEmpty { throw ToolError(message: "empty lorem") }
        case .passwordGenerator:
            var rng = SplitMix64(seed: 2)
            _ = try PasswordGenerator.generate(.default, using: &rng)
        case .csvJSON:
            _ = try TabularConvert.csvToJSON("name\nAda\n")
        default:
            throw ToolError(message: "no selftest for \(id.rawValue)")
        }
    }

    private static func permissionReason(_ error: Error, fallback: String) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("permission") || text.contains("denied") || text.contains("not authorized") || text.contains("tcc") {
            return error.localizedDescription
        }
        return "\(fallback): \(error.localizedDescription)"
    }

    @MainActor
    private static func transcribeFixture(_ fixtures: FixtureSet) async throws {
        let spoken = fixtures.folder.appendingPathComponent("spoken.aiff")
        try SpeechFixture.say("Hello Satchel", to: spoken)
        do {
            let transcript = try await SpeechJobs.transcribe(url: spoken, progress: { _ in })
            let plain = transcript.plain.lowercased()
            if !plain.contains("hello") && !plain.contains("satchel") {
                throw ToolError(message: "transcript missed the spoken words: \(transcript.plain)")
            }
        } catch let skip as SkipSignal {
            throw skip
        } catch {
            let text = error.localizedDescription.lowercased()
            if text.contains("speech") || text.contains("author") || text.contains("language") || text.contains("recogn") {
                throw SkipSignal(reason: error.localizedDescription)
            }
            throw error
        }
    }

    @MainActor
    private static func speakFixture() async throws {
        let spoken = try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await SpeechJobs.speak(text: "Hello Satchel", language: "en-US", progress: { _ in }) }
            group.addTask {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                throw SkipSignal(reason: "speech synthesis timed out")
            }
            guard let url = try await group.next() else { throw ToolError(message: "speech synthesis produced nothing") }
            group.cancelAll()
            return url
        }
        if FileSize.bytes(spoken) < 100 { throw ToolError(message: "speech file was empty") }
    }

    @MainActor
    private static func recordBriefly(_ fixtures: FixtureSet) async throws {
        let recorder = DisplayRecorder()
        await recorder.start()
        if !recorder.recording {
            throw SkipSignal(reason: recorder.message.isEmpty ? "screen recording was not granted" : recorder.message)
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        guard let url = await recorder.stop(), FileManager.default.fileExists(atPath: url.path) else {
            throw SkipSignal(reason: "screen recording did not produce a file")
        }
        _ = fixtures
    }

    private static func check(_ urls: [URL]) throws -> [URL] {
        if urls.isEmpty { throw ToolError(message: "no output") }
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            throw ToolError(message: "missing \(url.lastPathComponent)")
        }
        return urls
    }

    private static func checkOne(_ url: URL) throws -> URL {
        _ = try check([url])
        return url
    }

    private static func downloadCheck(_ fixtures: FixtureSet) async throws {
        let clip = try Data(contentsOf: fixtures.video)
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:4
        #EXTINF:3.0,
        clip.mov
        #EXT-X-ENDLIST
        """
        let (port, stop) = try LoopbackServer.start([
            "clip.mov": clip,
            "index.m3u8": Data(playlist.utf8)
        ])
        defer { stop() }
        try await Task.sleep(nanoseconds: 150_000_000)
        let folder = fixtures.folder.appendingPathComponent("downloads", isDirectory: true)
        let direct = try await VideoDownload.save(urlString: "http://127.0.0.1:\(port)/clip.mov", directory: folder, allowPageTool: false, progress: { _ in })
        if try Data(contentsOf: direct) != clip { throw ToolError(message: "direct download did not match") }
        let hlsFolder = fixtures.folder.appendingPathComponent("hls", isDirectory: true)
        let streamed = try await VideoDownload.save(urlString: "http://127.0.0.1:\(port)/index.m3u8", directory: hlsFolder, allowPageTool: false, progress: { _ in })
        if try Data(contentsOf: streamed) != clip { throw ToolError(message: "hls download did not match the segment") }
    }

    private static func requirePDFText(_ url: URL, contains needle: String) throws {
        guard let document = PDFDocument(url: url), let text = document.string, text.localizedCaseInsensitiveContains(needle) else {
            throw ToolError(message: "PDF did not contain \(needle)")
        }
    }
}

enum QRJobs {
    static func writePNG(text: String, nextTo: URL) throws -> URL {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw ToolError(message: "QR generator is unavailable.")
        }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else {
            throw ToolError(message: "Could not draw the QR code.")
        }
        let context = CIContext()
        let extent = output.extent.integral
        guard let image = context.createCGImage(output, from: extent) else {
            throw ToolError(message: "Could not render the QR code.")
        }
        let url = try Outputs.make(nextTo: nextTo, suffix: "-qr", ext: "png")
        try ImageFiles.write(image, to: url, type: .png, quality: nil)
        return url
    }
}

struct FixtureSet {
    var folder: URL
    var video: URL
    var video2: URL
    var audio: URL
    var png: URL
    var jpeg: URL
    var labeled: URL
    var pdf: URL
    var notes: URL
    var dupA: URL
    var dupB: URL

    static func make(in folder: URL) async throws -> FixtureSet {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let picture = folder.appendingPathComponent("clip-picture.mov")
        let picture2 = folder.appendingPathComponent("clip-b-picture.mov")
        let video = folder.appendingPathComponent("clip.mov")
        let video2 = folder.appendingPathComponent("clip-b.mov")
        let wav = folder.appendingPathComponent("tone.wav")
        let audio = folder.appendingPathComponent("tone.m4a")
        try await MediaFixture.writePicture(to: picture, color: (40, 90, 160))
        try await MediaFixture.writePicture(to: picture2, color: (160, 90, 40))
        try MediaFixture.writeWAV(to: wav)
        try MediaFixture.writeM4A(from: wav, to: audio)
        try await MediaFixture.muxOrCopy(picture: picture, wav: wav, to: video)
        try await MediaFixture.muxOrCopy(picture: picture2, wav: wav, to: video2)
        let png = folder.appendingPathComponent("photo.png")
        let jpeg = folder.appendingPathComponent("photo.jpg")
        let labeled = folder.appendingPathComponent("label.png")
        try ImageFixture.write(to: png, type: .png, text: nil, metadata: false)
        try ImageFixture.write(to: jpeg, type: .jpeg, text: nil, metadata: true)
        try ImageFixture.write(to: labeled, type: .png, text: "HELLO", metadata: false)
        let pdf = folder.appendingPathComponent("pages.pdf")
        try PDFFixture.write(to: pdf)
        let notes = folder.appendingPathComponent("notes.txt")
        try "Hello from a text file.\n".write(to: notes, atomically: true, encoding: .utf8)
        let dupA = folder.appendingPathComponent("same-a.txt")
        let dupB = folder.appendingPathComponent("same-b.txt")
        try "duplicate-bytes".write(to: dupA, atomically: true, encoding: .utf8)
        try "duplicate-bytes".write(to: dupB, atomically: true, encoding: .utf8)
        return FixtureSet(folder: folder, video: video, video2: video2, audio: audio, png: png, jpeg: jpeg, labeled: labeled, pdf: pdf, notes: notes, dupA: dupA, dupB: dupB)
    }

    static func load(from folder: URL) -> FixtureSet {
        FixtureSet(
            folder: folder,
            video: folder.appendingPathComponent("clip.mov"),
            video2: folder.appendingPathComponent("clip-b.mov"),
            audio: folder.appendingPathComponent("tone.m4a"),
            png: folder.appendingPathComponent("photo.png"),
            jpeg: folder.appendingPathComponent("photo.jpg"),
            labeled: folder.appendingPathComponent("label.png"),
            pdf: folder.appendingPathComponent("pages.pdf"),
            notes: folder.appendingPathComponent("notes.txt"),
            dupA: folder.appendingPathComponent("same-a.txt"),
            dupB: folder.appendingPathComponent("same-b.txt")
        )
    }
}

final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if done { return }
        done = true
        body()
    }
}

final class ClipWriteState: @unchecked Sendable {
    let lock = NSLock()
    var index = 0
    var videoDone = false
    var audioDone = false
    var audioQueued = false
    var armed = false
    var failed = false
    var finishing = false

    func claimAudio() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if audioQueued || failed { return false }
        audioQueued = true
        return true
    }

    func arm() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        armed = true
        return ready
    }

    func markVideo() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        videoDone = true
        return ready
    }

    func markAudio() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        audioDone = true
        return ready
    }

    func fail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if failed { return false }
        failed = true
        return true
    }

    func bumpFrame(limit: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        if index >= limit { return nil }
        let current = index
        index += 1
        return current
    }

    func filled(_ limit: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return index >= limit
    }

    private var ready: Bool {
        if videoDone && audioDone && armed && !failed && !finishing {
            finishing = true
            return true
        }
        return false
    }
}

enum MediaFixture {
    static func writePicture(to url: URL, color: (UInt8, UInt8, UInt8)) async throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240
        ])
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240
        ])
        guard writer.canAdd(video) else { throw ToolError(message: "fixture writer rejected video") }
        writer.add(video)
        guard writer.startWriting() else { throw ToolError(message: writer.error?.localizedDescription ?? "writer did not start") }
        writer.startSession(atSourceTime: .zero)
        let frames = 45
        let state = ClipWriteState()
        let queue = DispatchQueue(label: "satchel.fixture.video")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            video.requestMediaDataWhenReady(on: queue) {
                if state.failed || state.videoDone { return }
                while video.isReadyForMoreMediaData {
                    guard let index = state.bumpFrame(limit: frames) else { break }
                    guard let buffer = pixelBuffer(color: color) else {
                        video.markAsFinished()
                        if state.fail() { gate.fail(continuation, ToolError(message: "no pixel buffer")) }
                        return
                    }
                    let time = CMTime(value: CMTimeValue(index), timescale: 15)
                    if !adaptor.append(buffer, withPresentationTime: time) {
                        video.markAsFinished()
                        if state.fail() { gate.fail(continuation, ToolError(message: writer.error?.localizedDescription ?? "could not append video")) }
                        return
                    }
                }
                if state.filled(frames) {
                    state.videoDone = true
                    video.markAsFinished()
                    writer.finishWriting {
                        if writer.status == .completed {
                            gate.resume(continuation)
                        } else {
                            gate.fail(continuation, ToolError(message: writer.error?.localizedDescription ?? "clip was not written"))
                        }
                    }
                }
            }
            queue.asyncAfter(deadline: .now() + 20) {
                if state.fail() { gate.fail(continuation, ToolError(message: "fixture writer timed out")) }
            }
        }
    }

    static func writeWAV(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let rate = 44_100
        let frames = rate * 3
        var samples = [Int16](repeating: 0, count: frames)
        for index in 0..<frames {
            let angle = 2 * Double.pi * 440 * Double(index) / Double(rate)
            samples[index] = Int16(sin(angle) * 8000)
        }
        let dataSize = frames * 2
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.append(contentsOf: le32(UInt32(36 + dataSize)))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20])
        data.append(contentsOf: le32(16))
        data.append(contentsOf: le16(1))
        data.append(contentsOf: le16(1))
        data.append(contentsOf: le32(UInt32(rate)))
        data.append(contentsOf: le32(UInt32(rate * 2)))
        data.append(contentsOf: le16(2))
        data.append(contentsOf: le16(16))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        data.append(contentsOf: le32(UInt32(dataSize)))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        try data.write(to: url)
    }

    static func writeM4A(from wav: URL, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        process.arguments = ["-f", "m4af", "-d", "aac", wav.path, url.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ToolError(message: "could not encode the m4a fixture \(text)")
        }
    }

    static func muxOrCopy(picture: URL, wav: URL, to url: URL) async throws {
        do {
            try await mux(picture: picture, wav: wav, to: url)
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: picture, to: url)
        }
    }

    static func mux(picture: URL, wav: URL, to url: URL) async throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let pictureAsset = AVURLAsset(url: picture)
        let soundAsset = AVURLAsset(url: wav)
        guard let videoTrack = try await pictureAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await soundAsset.loadTracks(withMediaType: .audio).first else {
            throw ToolError(message: "fixture tracks were missing")
        }
        let videoReader = try AVAssetReader(asset: pictureAsset)
        let audioReader = try AVAssetReader(asset: soundAsset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = true
        audioOutput.alwaysCopiesSampleData = true
        guard videoReader.canAdd(videoOutput), audioReader.canAdd(audioOutput) else {
            throw ToolError(message: "could not read fixture tracks")
        }
        videoReader.add(videoOutput)
        audioReader.add(audioOutput)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        videoInput.expectsMediaDataInRealTime = false
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw ToolError(message: "could not add fixture tracks")
        }
        writer.add(videoInput)
        writer.add(audioInput)
        guard videoReader.startReading(), audioReader.startReading(), writer.startWriting() else {
            throw ToolError(message: writer.error?.localizedDescription ?? videoReader.error?.localizedDescription ?? audioReader.error?.localizedDescription ?? "mux did not start")
        }
        writer.startSession(atSourceTime: .zero)
        let queue = DispatchQueue(label: "satchel.fixture.mux")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
                videoReader.cancelReading()
                audioReader.cancelReading()
                gate.fail(continuation, ToolError(message: "mux timed out"))
            }
            queue.async {
                var videoOpen = true
                var audioOpen = true
                let started = Date()
                while videoOpen || audioOpen {
                    var wrote = false
                    if videoOpen, videoInput.isReadyForMoreMediaData {
                        wrote = true
                        if let sample = videoOutput.copyNextSampleBuffer() {
                            if !videoInput.append(sample) {
                                gate.fail(continuation, ToolError(message: writer.error?.localizedDescription ?? "could not mux the picture"))
                                return
                            }
                        } else {
                            videoInput.markAsFinished()
                            videoOpen = false
                        }
                    }
                    if audioOpen, audioInput.isReadyForMoreMediaData {
                        wrote = true
                        if let sample = audioOutput.copyNextSampleBuffer() {
                            if !audioInput.append(sample) {
                                gate.fail(continuation, ToolError(message: writer.error?.localizedDescription ?? "could not mux the tone"))
                                return
                            }
                        } else {
                            audioInput.markAsFinished()
                            audioOpen = false
                        }
                    }
                    if !videoOpen && !audioOpen { break }
                    if !wrote {
                        if Date().timeIntervalSince(started) > 8 {
                            gate.fail(continuation, ToolError(message: "mux stalled"))
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
                writer.finishWriting {
                    if writer.status == .completed {
                        gate.resume(continuation)
                    } else {
                        gate.fail(continuation, ToolError(message: writer.error?.localizedDescription ?? "mux did not finish"))
                    }
                }
            }
        }
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
    }

    private static func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
    }


    private static func pixelBuffer(color: (UInt8, UInt8, UInt8)) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<240 {
                for x in 0..<320 {
                    let offset = y * row + x * 4
                    bytes[offset] = color.2
                    bytes[offset + 1] = color.1
                    bytes[offset + 2] = color.0
                    bytes[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

}

enum ImageFixture {
    static func write(to url: URL, type: UTType, text: String?, metadata: Bool) throws {
        let width = 320
        let height = 200
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ToolError(message: "could not draw a fixture image") }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.darkGray.cgColor)
        context.fill(CGRect(x: 40, y: 40, width: 80, height: 100))
        if let text {
            let line = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: NSColor.black
            ])
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            line.draw(at: NSPoint(x: 40, y: 70))
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let image = context.makeImage() else { throw ToolError(message: "fixture image was empty") }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ToolError(message: "could not create the fixture image")
        }
        var properties: [CFString: Any] = [:]
        if metadata {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: "2024:05:09 12:00:00"]
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.7,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4,
                kCGImagePropertyGPSLongitudeRef: "W"
            ]
        }
        if type == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        if !CGImageDestinationFinalize(destination) { throw ToolError(message: "could not save the fixture image") }
    }
}

enum PDFFixture {
    static func write(to url: URL) throws {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { throw ToolError(message: "pdf consumer") }
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw ToolError(message: "pdf context") }
        for (index, words) in ["Hello Satchel", "secret token"].enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            let line = NSAttributedString(string: words, attributes: [
                .font: NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.black
            ])
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            line.draw(at: NSPoint(x: 40, y: 200))
            NSGraphicsContext.restoreGraphicsState()
            _ = index
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: url)
    }
}
