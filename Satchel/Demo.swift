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
            for window in NSApp.windows where window.isVisible || window.contentView != nil {
                window.setContentSize(NSSize(width: 1280, height: 840))
                window.center()
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
            DemoSession.files[.mergePDFs] = [fixtures.pdf, fixtures.pdf]
            DemoSession.files[.redactPDF] = [fixtures.pdf]
            DemoSession.files[.extractText] = [fixtures.labeled]
            DemoSession.files[.batchRename] = [fixtures.notes]
        }
        model.setDraft(.jsonFormatter, "{\"name\":\"Satchel\",\"offline\":true}")
        DemoSession.enabled = true
        let recorder = DisplayRecorder()
        if record {
            await recorder.start()
        }
        await pause(2)
        for category in ToolCategory.allCases {
            model.selectTab(category)
            await pause(1.2)
        }
        model.selectTab(nil)
        await pause(0.6)
        for character in "pdf" {
            model.query.append(character)
            await pause(0.35)
        }
        await pause(1.4)
        model.query = ""
        await pause(0.4)
        await open(.compressVideo, model, seconds: 7)
        await open(.removeBackground, model, seconds: 7)
        await open(.mergePDFs, model, seconds: 6)
        await open(.redactPDF, model, seconds: 6)
        await open(.extractText, model, seconds: 5)
        await open(.qrCode, model, seconds: 4)
        await open(.jsonFormatter, model, seconds: 4)
        await open(.batteryHealth, model, seconds: 4)
        await open(.batchRename, model, seconds: 5)
        model.closeTool()
        model.selectTab(nil)
        await pause(1.5)
        if record, let movie = await recorder.stop() {
            let mp4 = folder.appendingPathComponent("satchel-demo.mp4")
            do {
                try await MediaExport.export(
                    asset: AVURLAsset(url: movie),
                    output: mp4,
                    fileType: .mp4,
                    preset: AVAssetExportPresetLowQuality,
                    progress: { _ in }
                )
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
