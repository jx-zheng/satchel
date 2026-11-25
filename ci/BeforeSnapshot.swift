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
        let schemes: [(String, ColorScheme, NSAppearance.Name)] = [
            ("light", .light, .aqua),
            ("dark", .dark, .darkAqua)
        ]
        for (schemeName, scheme, appearance) in schemes {
            model.openTool = nil
            model.query = ""
            model.category = nil
            renderRoot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("before-home-\(schemeName).png"))
            model.category = .video
            renderRoot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("before-video-\(schemeName).png"))
            model.category = .docs
            renderRoot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("before-docs-\(schemeName).png"))
            model.category = nil
            model.openTool = nil
            model.query = "pdf"
            renderRoot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("before-search-\(schemeName).png"))
            model.query = ""
            model.openTool = .compressVideo
            model.category = .video
            renderRoot(model, scheme: scheme, appearance: appearance, to: folder.appendingPathComponent("before-tool-\(schemeName).png"))
            model.openTool = nil
            model.query = ""
        }
        exit(0)
    }

    @MainActor
    private static func renderRoot(_ model: AppModel, scheme: ColorScheme, appearance: NSAppearance.Name, to url: URL) {
        let view = RootView()
            .environmentObject(model)
            .environment(\.colorScheme, scheme)
            .environment(\.satchelSnapshot, true)
            .frame(width: 1440, height: 900)
        do {
            try render(view, appearance: appearance, to: url)
        } catch {
            fputs("Snapshot \(url.lastPathComponent) failed: \(error)\n", stderr)
            exit(1)
        }
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
        window.close()
        throw ToolError(message: "Could not render \(url.lastPathComponent).")
    }
}
