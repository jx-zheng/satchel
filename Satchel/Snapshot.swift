import AppKit
import SwiftUI
import SatchelCore

struct SnapshotDriver: View {
    let directory: String

    var body: some View {
        Color.clear
            .frame(width: 4, height: 4)
            .task {
                await Snapshotter.writeAll(directory: directory)
            }
    }
}

enum Snapshotter {
    @MainActor
    static func writeAll(directory: String) async {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            fputs("Could not create snapshot directory: \(error)\n", stderr)
            exit(1)
        }
        let model = AppModel.snapshotModel()
        let toolsFolder = folder.appendingPathComponent("tools", isDirectory: true)
        let redesign = folder.appendingPathComponent("redesign", isDirectory: true)
        try? FileManager.default.createDirectory(at: toolsFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: redesign, withIntermediateDirectories: true)
        let schemes: [(String, ColorScheme, NSAppearance.Name)] = [
            ("light", .light, .aqua),
            ("dark", .dark, .darkAqua)
        ]
        for (schemeName, scheme, appearance) in schemes {
            model.recents = [.compressVideo, .mergePDFs, .removeBackground, .transcribe]
            model.favorites = [.signPDF, .keepAwake]
            model.openTool = nil
            model.query = ""
            model.category = nil
            shot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("all-\(schemeName).png"), sample: false)
            shot(model, scheme: scheme, appearance: appearance, to: redesign.appendingPathComponent("after-home-\(schemeName).png"), sample: false)
            for category in [ToolCategory.video, .docs] {
                model.category = category
                model.openTool = nil
                model.query = ""
                let name = category.rawValue
                shot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("\(name)-\(schemeName).png"), sample: false)
                shot(model, scheme: scheme, appearance: appearance, to: redesign.appendingPathComponent("after-\(name)-\(schemeName).png"), sample: false)
            }
            for category in ToolCategory.allCases where category != .video && category != .docs {
                model.category = category
                model.openTool = nil
                model.query = ""
                shot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("\(category.rawValue)-\(schemeName).png"), sample: false)
            }
            model.category = nil
            model.openTool = nil
            model.recents = []
            model.favorites = []
            model.query = ""
            shot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("home-empty-\(schemeName).png"), sample: false)
            model.recents = [.compressVideo, .mergePDFs]
            model.favorites = [.signPDF]
            model.query = "pdf"
            shot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("search-\(schemeName).png"), sample: false)
            shot(model, scheme: scheme, appearance: appearance, to: redesign.appendingPathComponent("after-search-\(schemeName).png"), sample: false)
            model.query = ""
            model.openTool = .compressVideo
            model.category = .video
            shot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("tool-video-\(schemeName).png"), sample: false)
            shot(model, scheme: scheme, appearance: appearance, to: redesign.appendingPathComponent("after-tool-\(schemeName).png"), sample: true)
            let featured: [(String, ToolID)] = [
                ("audio", .convertAudio), ("images", .removeBackground), ("docs", .mergePDFs),
                ("text", .summarize), ("files", .batchRename), ("mac", .displayControl), ("dev", .jsonFormatter)
            ]
            for (name, id) in featured {
                model.openTool = id
                model.category = ToolRegistry.byID[id]?.category
                shot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("tool-\(name)-\(schemeName).png"), sample: false)
            }
            for id in ToolID.allCases {
                guard let tool = ToolRegistry.byID[id] else { continue }
                model.openTool = id
                model.category = tool.category
                let toolView = ToolRouter(tool: tool)
                    .environmentObject(model)
                    .environment(\.colorScheme, scheme)
                    .environment(\.satchelSnapshot, true)
                    .frame(width: 980, height: 820)
                    .background(Color(nsColor: .windowBackgroundColor))
                let url = toolsFolder.appendingPathComponent("\(id.rawValue)-\(schemeName).png")
                fputs("snapshot \(url.lastPathComponent)\n", stderr)
                fflush(stderr)
                do {
                    try render(toolView, appearance: appearance, to: url, settle: 0.02)
                } catch {
                    fputs("Snapshot \(url.lastPathComponent) failed: \(error)\n", stderr)
                    exit(1)
                }
            }
            let deniedCases: [(ToolID, PermissionKind)] = [
                (.recordAudio, .microphone),
                (.storageExplorer, .fullDiskAccess)
            ]
            for (id, kind) in deniedCases {
                guard let tool = ToolRegistry.byID[id] else { continue }
                model.openTool = id
                model.category = tool.category
                let toolView = ToolRouter(tool: tool)
                    .environmentObject(model)
                    .environment(\.colorScheme, scheme)
                    .environment(\.satchelSnapshot, true)
                    .environment(\.satchelSimulatedPermissionDenied, kind)
                    .frame(width: 980, height: 820)
                    .background(Color(nsColor: .windowBackgroundColor))
                let url = folder.appendingPathComponent("permission-denied-\(id.rawValue)-\(schemeName).png")
                fputs("snapshot \(url.lastPathComponent)\n", stderr)
                fflush(stderr)
                do {
                    try render(toolView, appearance: appearance, to: url, settle: 0.04)
                } catch {
                    fputs("Snapshot \(url.lastPathComponent) failed: \(error)\n", stderr)
                    exit(1)
                }
            }
            model.openTool = nil
        }
        exit(0)
    }

    @MainActor
    private static func shot(_ model: AppModel, scheme: ColorScheme, appearance: NSAppearance.Name, to url: URL, sample: Bool, settle: Double = 0.12) {
        let view = RootView()
            .environmentObject(model)
            .environment(\.colorScheme, scheme)
            .environment(\.satchelSnapshot, true)
            .environment(\.satchelSampleResult, sample)
            .frame(width: 1440, height: 900)
        fputs("snapshot \(url.lastPathComponent)\n", stderr)
        fflush(stderr)
        do {
            try render(view, appearance: appearance, to: url, settle: settle)
        } catch {
            fputs("Snapshot \(url.lastPathComponent) failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL, settle: Double = 0.12) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        window.orderFrontRegardless()
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw ToolError(message: "No bitmap for snapshot.")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]), data.count > 1000 {
            try data.write(to: url)
            window.close()
            return
        }
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 1440, height: 900)
        renderer.scale = 1
        renderer.isOpaque = true
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            window.close()
            throw ToolError(message: "Could not render \(url.lastPathComponent).")
        }
        try png.write(to: url)
        window.close()
    }
}
