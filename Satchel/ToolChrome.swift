import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SatchelCore

struct ToolError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

struct ToolScaffold<Content: View>: View {
    @EnvironmentObject private var model: AppModel
    let tool: ToolDefinition
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        model.closeTool()
                    } label: {
                        Label(model.category?.title ?? "All", systemImage: "chevron.left")
                            .font(.callout)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.toggleFavorite(tool.id)
                    } label: {
                        Image(systemName: model.isFavorite(tool.id) ? "star.fill" : "star")
                            .foregroundStyle(model.isFavorite(tool.id) ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(model.isFavorite(tool.id) ? "Remove from Favorites" : "Add to Favorites")
                }
                HStack(alignment: .center, spacing: 12) {
                    ToolArt(tool: tool, compact: true)
                        .frame(width: 36, height: 36)
                    Text(tool.name)
                        .font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(tool.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
                Text("⌘O chooses a file · ⌘↩ runs · ⎋ cancels")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusSection()
    }
}

typealias ToolPage = ToolScaffold

struct ComingSoonView: View {
    let tool: ToolDefinition

    var body: some View {
        ToolPage(tool: tool) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coming soon")
                    .font(.system(size: 22, weight: .semibold))
                Text("This tool is listed so you can find it, but it is not built in this version. Nothing is uploaded, and nothing is changed on disk.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
        }
    }
}

struct PrimaryButton: View {
    @EnvironmentObject private var model: AppModel
    var title: String
    var enabled: Bool = true
    var registersRun = true
    var action: () -> Void
    @State private var token = UUID().uuidString

    private var claimsRun: Bool {
        guard registersRun else { return false }
        let lower = title.lowercased()
        let blocked = ["trash", "eject", "reset", "quarantine"]
        return !blocked.contains { lower.contains($0) }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(enabled ? Palette.accent : Palette.accent.opacity(0.35)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onAppear { claim() }
        .onDisappear {
            if model.runClaim == token { model.runClaim = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .satchelRun)) { _ in
            guard model.runClaim == token, enabled else { return }
            action()
        }
    }

    private func claim() {
        guard claimsRun, model.runClaim == nil else { return }
        model.runClaim = token
    }
}

struct DropZone: View {
    var prompt: String
    var types: [UTType]
    var multiple = true
    var onURLs: ([URL]) -> Void
    @State private var targeted = false
    @State private var importer = false

    var body: some View {
        Button {
            importer = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(targeted ? Palette.accent : Color.secondary)
                Text(prompt)
                    .font(.system(size: 15, weight: .semibold))
                Text("Drop files, or click to choose")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 168)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(targeted ? Palette.accent.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(targeted ? Palette.accent : Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, dash: [7, 5]))
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            FileDrop.load(providers, completion: onURLs)
            return true
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: types, allowsMultipleSelection: multiple) { result in
            if case let .success(urls) = result {
                for url in urls {
                    _ = url.startAccessingSecurityScopedResource()
                }
                onURLs(urls)
            }
        }
    }
}

struct FileJobView<Controls: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.satchelSampleResult) private var sampleResult
    let tool: ToolID
    var types: [UTType]
    var prompt: String
    var actionTitle: String
    var multiple = true
    var tracksSavings = false
    @ViewBuilder var controls: () -> Controls
    var perform: ([URL], @escaping (Double) -> Void) async throws -> [URL]
    var onFiles: ([URL]) -> Void = { _ in }

    @State private var urls: [URL] = []
    @State private var outputs: [URL] = []
    @State private var running = false
    @State private var progress = 0.0
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?
    @StateObject private var permission: PermissionCoordinator

    init(
        tool: ToolID,
        types: [UTType],
        prompt: String,
        actionTitle: String,
        multiple: Bool = true,
        tracksSavings: Bool = false,
        @ViewBuilder controls: @escaping () -> Controls,
        perform: @escaping ([URL], @escaping (Double) -> Void) async throws -> [URL],
        onFiles: @escaping ([URL]) -> Void = { _ in }
    ) {
        self.tool = tool
        self.types = types
        self.prompt = prompt
        self.actionTitle = actionTitle
        self.multiple = multiple
        self.tracksSavings = tracksSavings
        self.controls = controls
        self.perform = perform
        self.onFiles = onFiles
        _permission = StateObject(wrappedValue: PermissionCoordinator(tool: tool))
    }

    var body: some View {
        let definition = ToolRegistry.definition(tool)
        ToolPage(tool: definition) {
            DropZone(prompt: prompt, types: types, multiple: multiple) { picked in
                urls = picked
                outputs = []
                errorText = nil
                onFiles(picked)
            }
            if urls.isEmpty {
                Text("Nothing selected yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(urls, id: \.path) { url in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                urls.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove")
                        }
                    }
                }
            }
            controls()
            PrimaryButton(title: running ? "Working…" : actionTitle, enabled: !urls.isEmpty && !running) {
                start()
            }
            if running {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress) {
                        Text("Working…")
                            .font(.callout)
                    }
                    .progressViewStyle(.linear)
                    Button("Cancel") { stop() }
                        .buttonStyle(.borderless)
                }
            }
            PermissionBannerSlot(coordinator: permission)
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.08)))
            }
            if !outputs.isEmpty {
                ResultTray(urls: outputs, heading: "Saved next to the original")
            } else if sampleResult {
                ResultTray(urls: [URL(fileURLWithPath: "/tmp/Result.pdf")], heading: "Ready")
            }
        }
        .onAppear {
            adoptIncoming()
            guard DemoSession.enabled, DemoSession.take(tool), urls.isEmpty,
                  let files = DemoSession.files[tool], !files.isEmpty else { return }
            urls = files
            start()
        }
        .onChange(of: model.incomingFiles) { _, _ in
            adoptIncoming()
        }
        .onChange(of: model.cancelTick) { _, _ in
            if running { stop() }
        }
        .onChange(of: running) { _, value in
            if model.openTool == tool { model.toolRunning = value }
        }
        .onDisappear {
            if model.openTool == tool { model.toolRunning = false }
        }
    }

    private func adoptIncoming() {
        guard model.openTool == tool, !model.incomingFiles.isEmpty else { return }
        urls = model.incomingFiles
        outputs = []
        errorText = nil
        model.incomingFiles = []
        onFiles(urls)
    }

    private func stop() {
        task?.cancel()
        running = false
        model.toolRunning = false
    }

    private func start() {
        let current = urls
        running = true
        progress = 0
        errorText = nil
        outputs = []
        task = Task {
            do {
                let made = try await RunLog.measure(tool: tool, inputs: current.count) {
                    try await perform(current) { value in
                        progress = value
                    }
                }
                outputs = made
                if tracksSavings {
                    let before = current.reduce(Int64(0)) { $0 + FileSize.bytes($1) }
                    let after = made.reduce(Int64(0)) { $0 + FileSize.bytes($1) }
                    model.noteSavings(bytes: before - after, files: made.count)
                }
            } catch {
                if permission.handleError(error, targetURL: current.first, retry: { start() }) {
                    errorText = nil
                } else {
                    errorText = error.localizedDescription
                }
            }
            running = false
            progress = 1
        }
    }
}

struct ResultTray: View {
    var urls: [URL]
    var heading = "Ready"

    var body: some View {
        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(heading)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(urls, id: \.path) { url in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .foregroundStyle(Palette.accent)
                            Text(url.lastPathComponent)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 12) {
                            Button("Reveal") { Outputs.reveal(url) }
                            Button("Open") { NSWorkspace.shared.open(url) }
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([url as NSURL])
                            }
                        }
                        .font(.callout)
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onDrag {
                        NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url.path as NSString)
                    }
                    .help("Drag the file to the Desktop or another app")
                }
            }
        }
    }
}

enum FileDrop {
    static func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let box = URLBox()
        for provider in providers {
            group.enter()
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                _ = url.startAccessingSecurityScopedResource()
                box.append(url)
            }
        }
        group.notify(queue: .main) {
            completion(box.items)
        }
    }
}

final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    var items: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

enum Outputs {
    static func make(nextTo source: URL, suffix: String, ext: String?) throws -> URL {
        let folder = source.deletingLastPathComponent()
        let desired = OutputNaming.fileName(original: source.lastPathComponent, suffix: suffix, newExtension: ext)
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        return folder.appendingPathComponent(OutputNaming.unique(desired, existing: names))
    }

    static func folder(nextTo source: URL, nameSuffix: String) throws -> URL {
        let parent = source.deletingLastPathComponent()
        let stem = OutputNaming.stemAndExtension(source.lastPathComponent).stem
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [])
        let unique = OutputNaming.unique(stem + nameSuffix, existing: names)
        let url = parent.appendingPathComponent(unique, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func directory(in domain: FileManager.SearchPathDirectory, subfolder: String) throws -> URL {
        let base = FileManager.default.urls(for: domain, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = base.appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum FileSize {
    static func bytes(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory == true {
            return directory(url)
        }
        return Int64(values?.fileSize ?? 0)
    }

    static func directory(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}

struct CommandResult {
    var status: Int32
    var output: String
}

enum Commands {
    static func run(_ path: String, _ args: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return CommandResult(status: 1, output: error.localizedDescription)
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

enum MediaTypes {
    static var movies: [UTType] {
        [.movie, .mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "m4v") ?? .movie, UTType(filenameExtension: "mkv") ?? .movie]
    }

    static var audio: [UTType] {
        [.audio, .mp3, .wav, .aiff, UTType(filenameExtension: "m4a") ?? .audio]
    }

    static var images: [UTType] { [.image] }
    static var pdfs: [UTType] { [.pdf] }
    static var anyFile: [UTType] { [.item] }
    static var apps: [UTType] { [UTType(filenameExtension: "app") ?? .application] }
}
