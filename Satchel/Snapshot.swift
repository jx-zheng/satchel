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
        let tabs: [(String, ToolCategory?)] = [("all", nil)] + ToolCategory.allCases.map { ($0.rawValue, $0) }
        let toolShots: [(String, ToolID)] = [
            ("video", .compressVideo),
            ("audio", .recordAudio),
            ("images", .removeBackground),
            ("docs", .mergePDFs),
            ("text", .transcribe),
            ("files", .batchRename),
            ("mac", .storageExplorer),
            ("dev", .jsonFormatter)
        ]
        let schemes: [(String, ColorScheme, NSAppearance.Name)] = [
            ("light", .light, .aqua),
            ("dark", .dark, .darkAqua)
        ]
        for (schemeName, scheme, appearance) in schemes {
            for (name, category) in tabs {
                model.category = category
                model.openTool = nil
                model.query = ""
                model.selection = nil
                let view = RootView()
                    .environmentObject(model)
                    .environment(\.colorScheme, scheme)
                    .environment(\.satchelSnapshot, true)
                    .frame(width: 1440, height: 900)
                let url = folder.appendingPathComponent("\(name)-\(schemeName).png")
                do {
                    try render(view, appearance: appearance, to: url)
                } catch {
                    fputs("Snapshot \(url.lastPathComponent) failed: \(error)\n", stderr)
                    exit(1)
                }
            }
            model.category = nil
            model.openTool = nil
            model.recents = []
            model.favorites = []
            model.query = ""
            let empty = RootView()
                .environmentObject(model)
                .environment(\.colorScheme, scheme)
                .environment(\.satchelSnapshot, true)
                .frame(width: 1440, height: 900)
            do {
                try render(empty, appearance: appearance, to: folder.appendingPathComponent("home-empty-\(schemeName).png"))
            } catch {
                fputs("Snapshot home-empty-\(schemeName) failed: \(error)\n", stderr)
                exit(1)
            }
            model.recents = [.compressVideo, .mergePDFs]
            model.favorites = [.signPDF]
            model.query = "pdf"
            let search = RootView()
                .environmentObject(model)
                .environment(\.colorScheme, scheme)
                .environment(\.satchelSnapshot, true)
                .frame(width: 1440, height: 900)
            do {
                try render(search, appearance: appearance, to: folder.appendingPathComponent("search-\(schemeName).png"))
            } catch {
                fputs("Snapshot search-\(schemeName) failed: \(error)\n", stderr)
                exit(1)
            }
            model.query = ""
            for (name, id) in toolShots {
                model.openTool = id
                model.category = ToolRegistry.byID[id]?.category
                let toolView = RootView()
                    .environmentObject(model)
                    .environment(\.colorScheme, scheme)
                    .environment(\.satchelSnapshot, true)
                    .frame(width: 1440, height: 900)
                do {
                    try render(toolView, appearance: appearance, to: folder.appendingPathComponent("tool-\(name)-\(schemeName).png"))
                } catch {
                    fputs("Snapshot tool-\(name)-\(schemeName) failed: \(error)\n", stderr)
                    exit(1)
                }
            }
            model.openTool = nil
        }
        exit(0)
    }

    @MainActor
    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFrontRegardless()
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
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
