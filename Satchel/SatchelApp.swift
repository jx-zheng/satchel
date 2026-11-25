import AppKit
import AVFoundation
import CoreMedia
import SwiftUI

@main
enum SatchelMain {
    static func main() {
        Launch.noteBoot()
        if CommandLine.arguments.contains("--trim-movie") {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: "--trim-movie"), index + 3 < args.count else { exit(2) }
            let input = args[index + 1]
            let output = args[index + 2]
            let seconds = Double(args[index + 3]) ?? 75
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task {
                let asset = AVURLAsset(url: URL(fileURLWithPath: input))
                let range = CMTimeRange(start: .zero, duration: CMTime(seconds: seconds, preferredTimescale: 600))
                do {
                    try await MediaExport.export(
                        asset: asset,
                        output: URL(fileURLWithPath: output),
                        fileType: .mp4,
                        preset: AVAssetExportPreset1280x720,
                        timeRange: range,
                        progress: { _ in }
                    )
                    exit(0)
                } catch {
                    fputs("trim failed: \(error)\n", stderr)
                    exit(1)
                }
            }
            app.run()
        } else if CommandLine.arguments.contains("--perf-samples"), let directory = CommandLine.arguments.last {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task {
                await PerfSamples.run(directory: directory)
                exit(0)
            }
            app.run()
        } else if CommandLine.arguments.contains("--cold-window") {
            ColdWindow.run()
        } else if CommandLine.arguments.contains("--tab-hit") {
            Task { @MainActor in
                let ok = (try? TabHitTest.clickEdgeSelectsVideo()) != nil
                exit(ok ? 0 : 1)
            }
            dispatchMain()
        } else if CommandLine.arguments.contains("--permission-gate") {
            Task { @MainActor in
                do {
                    try await PermissionGateProbe.verifyAll()
                    exit(0)
                } catch {
                    fputs("permission-gate failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            dispatchMain()
        } else if let job = Launch.selfTestJob {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            Task { @MainActor in
                let code = await SelfTest.runOne(directory: job.directory, toolID: job.tool)
                exit(Int32(code))
            }
            app.run()
        } else {
            SatchelApp.main()
        }
    }
}

struct SatchelApp: App {
    @NSApplicationDelegateAdaptor(SatchelDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            if let job = Launch.selfTestJob {
                SelfTestDriver(directory: job.directory, only: job.tool)
            } else if let directory = Launch.selfTestDirectory {
                SelfTestDriver(directory: directory)
            } else if let directory = Launch.perfDirectory {
                PerfDriver(directory: directory)
            } else if let directory = Launch.demoDirectory {
                DemoRoot(directory: directory, record: !Launch.demoSkipsRecording)
            } else if let directory = Launch.snapshotDirectory {
                SnapshotDriver(directory: directory)
            } else {
                RootView()
                    .environmentObject(model)
                    .onOpenURL { url in
                        model.incomingFiles = [url]
                    }
            }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open File…") {
                    NotificationCenter.default.post(name: .satchelOpenPanel, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Run") {
                    NotificationCenter.default.post(name: .satchelRun, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Search Tools") {
                    model.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

final class SatchelDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        NotificationCenter.default.post(name: .satchelIncomingFiles, object: urls)
    }
}

enum Launch {
    static let booted = Date()

    static func noteBoot() {}

    static var demoSkipsRecording: Bool {
        CommandLine.arguments.contains("--demo-norecord")
    }

    static var demoSmoke: Bool {
        CommandLine.arguments.contains("--demo-smoke")
    }

    static var demoDirectory: String? { flag("--demo") }
    static var perfDirectory: String? { flag("--perf") }

    private static func flag(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: name) else { return nil }
        guard index + 1 < args.count else {
            fputs("Satchel \(name) needs a directory.\n", stderr)
            exit(2)
        }
        return args[index + 1]
    }

    static var snapshotDirectory: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot") else { return nil }
        guard index + 1 < args.count else {
            fputs("Satchel --snapshot needs a directory.\n", stderr)
            exit(2)
        }
        return args[index + 1]
    }

    static var selfTestJob: (tool: String, directory: String)? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--selftest-one") else { return nil }
        guard index + 2 < args.count else {
            fputs("Satchel --selftest-one needs a tool id and a directory.\n", stderr)
            exit(2)
        }
        return (args[index + 1], args[index + 2])
    }

    static var selfTestDirectory: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--selftest") else { return nil }
        guard index + 1 < args.count else {
            fputs("Satchel --selftest needs a directory.\n", stderr)
            exit(2)
        }
        return args[index + 1]
    }
}
