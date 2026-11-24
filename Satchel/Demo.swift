import AppKit
import AVFoundation
import SwiftUI
import SatchelCore

enum DemoSession {
    static var enabled = false
    static var files: [ToolID: [URL]] = [:]
    private static var armed = Set<String>()

    static func arm(_ id: ToolID) {
        armed.insert(id.rawValue)
    }

    static func take(_ id: ToolID) -> Bool {
        armed.remove(id.rawValue) != nil
    }
}

struct DemoRoot: View {
    let directory: String
    var record: Bool
    @StateObject private var model = AppModel(persists: false)

    var body: some View {
        RootView()
            .environmentObject(model)
            .frame(width: 1280, height: 840)
            .task {
                await DemoScript.run(directory: directory, record: record, model: model)
                exit(0)
            }
            .onAppear { center() }
    }

    private func center() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            for window in NSApp.windows where window.isVisible || window.contentView != nil {
                window.setContentSize(NSSize(width: 1280, height: 840))
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

enum DemoScript {
    @MainActor
    static func run(directory: String, record: Bool, model: AppModel) async {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let samples = folder.appendingPathComponent("samples", isDirectory: true)
        let fixtures = (try? await FixtureSet.make(in: samples))
        if let subject = try? BundleFixture.copy(name: "subject", ext: "png", to: samples) {
            DemoSession.files[.removeBackground] = [subject]
        }
        if let fixtures {
            DemoSession.files[.compressVideo] = [fixtures.video]
            DemoSession.files[.convertAudio] = [fixtures.audio]
            DemoSession.files[.mergePDFs] = [fixtures.pdf, fixtures.pdf]
            DemoSession.files[.extractText] = [fixtures.labeled]
            DemoSession.files[.batchRename] = [fixtures.notes]
            let srt = samples.appendingPathComponent("cues.srt")
            try? "1\n00:00:00,200 --> 00:00:02,000\nHELLO\n".write(to: srt, atomically: true, encoding: .utf8)
            DemoSession.files[.burnSubtitles] = [fixtures.video, srt]
        }
        model.setDraft(.markdownToPDF, "# Notes\n\nA short page, made on this Mac.")
        model.setDraft(.summarize, "Cats sleep in warm sun. Cats sleep in warm sun. Trains cross the valley at dusk. Trains cross the valley at dusk.")
        model.setDraft(.jsonFormatter, "{\"name\":\"Satchel\",\"offline\":true}")
        DemoSession.enabled = true
        await pause(0.6)
        let recorder = DisplayRecorder()
        if record {
            await recorder.start()
        }
        if Launch.demoSmoke {
            try? "draft smoke, not the deliverable".write(to: folder.appendingPathComponent("demo-draft.txt"), atomically: true, encoding: .utf8)
            model.selectTab(.video)
            await pause(1.2)
            for character in "pdf" {
                model.query.append(character)
                await pause(0.2)
            }
            await pause(0.8)
            model.query = ""
            await open(.compressVideo, model, seconds: 3)
            model.closeTool()
            await pause(0.6)
            if record, let movie = await recorder.stop() {
                try? await transcode(movie, to: folder.appendingPathComponent("satchel-demo.mp4"))
            }
            return
        }
        await pause(0.4)
        for category in ToolCategory.allCases {
            model.selectTab(category)
            await pause(0.7)
        }
        model.selectTab(nil)
        await pause(0.4)
        for character in "pdf" {
            model.query.append(character)
            await pause(0.25)
        }
        await pause(1.0)
        model.query = ""
        await pause(0.3)
        await open(.compressVideo, model, seconds: 5)
        await open(.burnSubtitles, model, seconds: 5)
        await open(.convertAudio, model, seconds: 4)
        await open(.mergePDFs, model, seconds: 4)
        await open(.markdownToPDF, model, seconds: 4)
        await open(.summarize, model, seconds: 4)
        await open(.extractText, model, seconds: 4)
        await open(.batchRename, model, seconds: 4)
        model.closeTool()
        model.selectTab(nil)
        await pause(1.0)
        if record, let movie = await recorder.stop() {
            do {
                try await transcode(movie, to: folder.appendingPathComponent("satchel-demo.mp4"))
            } catch {
                try? "transcode failed: \(error.localizedDescription)".write(
                    to: folder.appendingPathComponent("demo-note.txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        } else if record {
            try? "screen recording did not start".write(
                to: folder.appendingPathComponent("demo-note.txt"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private static func transcode(_ movie: URL, to mp4: URL) async throws {
        try await MediaExport.export(
            asset: AVURLAsset(url: movie),
            output: mp4,
            fileType: .mp4,
            preset: AVAssetExportPresetMediumQuality,
            progress: { _ in }
        )
    }

    @MainActor
    private static func open(_ id: ToolID, _ model: AppModel, seconds: Double) async {
        DemoSession.arm(id)
        model.open(id)
        await pause(seconds)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
