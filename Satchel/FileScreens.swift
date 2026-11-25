import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import Vision
import SatchelCore

struct FileToolScreen: View {
    let id: ToolID
    var body: some View {
        switch id {
        case .qrCode: QRTool()
        case .batchRename: RenameTool()
        case .findDuplicates: DuplicateTool()
        case .zipUnzip: ZipTool()
        case .organizeDownloads: OrganizeTool()
        default:
            if let tool = ToolRegistry.byID[id] { ComingSoonView(tool: tool) }
        }
    }
}

private struct QRTool: View {
    @StateObject private var permission = PermissionCoordinator(tool: .qrCode)
    @State private var text = "https://"
    @State private var image: NSImage?
    @State private var read = ""
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.qrCode)) {
            TextField("Text or link", text: $text)
            PrimaryButton(title: "Make QR code", enabled: !text.isEmpty) { generate() }
            if let image {
                Image(nsImage: image).interpolation(.none).frame(width: 180, height: 180)
                PrimaryButton(title: "Save PNG", enabled: true) { save() }
            }
            DropZone(prompt: "Or drop an image to read a code", types: MediaTypes.images, multiple: false) { urls in
                if let url = urls.first { decode(url) }
            }
            PermissionBannerSlot(coordinator: permission)
            if !read.isEmpty { Text(read).textSelection(.enabled) }
            Text(message).foregroundStyle(.secondary)
        }
        .onAppear {
            guard DemoSession.enabled, DemoSession.take(.qrCode) else { return }
            text = "https://example.com"
            generate()
        }
    }

    private func generate() {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return }
        let context = CIContext()
        let extent = output.extent.integral
        guard let cg = context.createCGImage(output, from: extent) else { return }
        image = NSImage(cgImage: cg, size: NSSize(width: extent.width, height: extent.height))
        SatchelLog.toolRun(id: ToolID.qrCode.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
    }

    private func save() {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        do {
            let folder = try Outputs.directory(in: .downloadsDirectory, subfolder: "Satchel")
            let url = folder.appendingPathComponent("QR-\(Int(Date().timeIntervalSince1970)).png")
            try ImageFiles.write(cg, to: url, type: .png, quality: nil)
            permission.clear()
            message = "Saved \(url.lastPathComponent)"
            Outputs.reveal(url)
        } catch {
            if permission.handleError(error, targetURL: downloads, retry: { save() }) {
                message = ""
            } else {
                message = error.localizedDescription
            }
        }
    }

    private func decode(_ url: URL) {
        do {
            let cg = try ImageFiles.load(url)
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([request])
            let values = (request.results ?? []).compactMap(\.payloadStringValue)
            read = values.isEmpty ? "No QR code found." : values.joined(separator: "\n")
            SatchelLog.toolRun(id: ToolID.qrCode.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
        } catch { read = error.localizedDescription }
    }
}

private struct RenameTool: View {
    @State private var urls: [URL] = []
    @State private var find = ""
    @State private var replace = ""
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var numbering = false
    @State private var start = "1"
    @State private var style = TextCase.lower
    @State private var useCase = false
    @State private var message = ""

    var body: some View {
        let rows = preview()
        ToolPage(tool: ToolRegistry.definition(.batchRename)) {
            DropZone(prompt: "Drop files to rename", types: [.item]) { urls = $0 }
            TextField("Find", text: $find)
            TextField("Replace with", text: $replace)
            TextField("Prefix", text: $prefix)
            TextField("Suffix", text: $suffix)
            Toggle("Add numbers", isOn: $numbering)
            if numbering { TextField("Start at", text: $start).frame(width: 80) }
            Toggle("Change case", isOn: $useCase)
            if useCase {
                Picker("Case", selection: $style) {
                    ForEach(TextCase.allCases) { Text($0.label).tag($0) }
                }
            }
            ForEach(rows, id: \.original) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.original).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(row.proposed).font(.system(size: 13, weight: .medium))
                    if let issue = row.issue { Text(issue).foregroundStyle(.red).font(.system(size: 11)) }
                }
            }
            PrimaryButton(title: "Rename", enabled: !urls.isEmpty && rows.allSatisfy { $0.issue == nil }) { apply(rows) }
            Text("Originals are renamed in place only after you confirm this preview. Nothing is overwritten.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
        .onAppear {
            guard DemoSession.enabled, DemoSession.take(.batchRename), let file = DemoSession.files[.batchRename]?.first else { return }
            urls = [file]
            prefix = "satchel-"
        }
    }

    private func operations() -> [RenameOperation] {
        var ops: [RenameOperation] = []
        if !find.isEmpty {
            ops.append(.findReplace(find: find, replace: replace, useRegex: false, caseInsensitive: false))
        }
        if !prefix.isEmpty { ops.append(.prefix(prefix)) }
        if !suffix.isEmpty { ops.append(.suffix(suffix)) }
        if numbering {
            ops.append(.number(start: Int(start) ?? 1, padding: 2, position: .suffix))
        }
        if useCase { ops.append(.changeCase(style)) }
        return ops
    }

    private func preview() -> [RenamePreviewRow] {
        let items = urls.map { RenameItem(name: $0.lastPathComponent, modified: nil) }
        return RenameEngine.preview(items: items, operations: operations())
    }

    private func apply(_ rows: [RenamePreviewRow]) {
        guard rows.allSatisfy({ $0.issue == nil }) else { return }
        let startDate = Date()
        do {
            for (url, row) in zip(urls, rows) where row.original != row.proposed {
                let destination = url.deletingLastPathComponent().appendingPathComponent(row.proposed)
                if FileManager.default.fileExists(atPath: destination.path) {
                    throw ToolError(message: "\(row.proposed) already exists.")
                }
                try FileManager.default.moveItem(at: url, to: destination)
            }
            message = "Renamed \(rows.count) files."
            urls = []
            SatchelLog.toolRun(id: ToolID.batchRename.rawValue, inputs: rows.count, outcome: "ok", seconds: RunLog.stamp(startDate))
        } catch {
            message = error.localizedDescription
            SatchelLog.toolRun(id: ToolID.batchRename.rawValue, inputs: rows.count, outcome: "failed", seconds: RunLog.stamp(startDate))
        }
    }
}

private struct DuplicateTool: View {
    @State private var folder: URL?
    @State private var groups: [[DuplicateFile]] = []
    @State private var selected: Set<String> = []
    @State private var message = ""
    @State private var running = false
    @State private var confirm = false

    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.findDuplicates)) {
            PrimaryButton(title: running ? "Scanning…" : "Choose a folder", enabled: !running) { pick() }
            if let folder { Text(folder.path).font(.system(size: 12)).lineLimit(2) }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.count) copies · \(ByteFormat.string(bytes: group.first?.size ?? 0))")
                        .font(.system(size: 12, weight: .semibold))
                    ForEach(group, id: \.path) { file in
                        Toggle(file.path, isOn: Binding(
                            get: { selected.contains(file.path) },
                            set: { on in
                                if on { selected.insert(file.path) } else { selected.remove(file.path) }
                            }
                        ))
                        .font(.system(size: 11))
                    }
                }
                .padding(.vertical, 4)
            }
            PrimaryButton(title: "Move selected to Trash", enabled: !selected.isEmpty) { confirm = true }
            Text("The first file in each group is left unchecked. Trashing never deletes the last copy unless you check it too.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
        .confirmationDialog("Move \(selected.count) files to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { trash() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        running = true
        Task.detached {
            let files = DuplicateScan.collect(url)
            let candidates = DuplicateGrouper.sizeCandidates(files)
            var hashed: [DuplicateFile] = []
            for group in candidates {
                for file in group {
                    let data = (try? Data(contentsOf: URL(fileURLWithPath: file.path), options: [.mappedIfSafe])) ?? Data()
                    hashed.append(DuplicateFile(path: file.path, size: file.size, hash: Digests.sha256Hex(data)))
                }
            }
            let groups = DuplicateGrouper.hashGroups(hashed)
            var keep = Set<String>()
            for group in groups.dropFirst(0) {
                if let first = group.first { keep.insert(first.path) }
            }
            let preselected = Set(groups.flatMap { $0.map(\.path) }).subtracting(keep)
            await MainActor.run {
                self.groups = groups
                self.selected = preselected
                self.running = false
                self.message = groups.isEmpty ? "No duplicates in that folder." : "\(groups.count) duplicate groups."
                SatchelLog.toolRun(id: ToolID.findDuplicates.rawValue, inputs: files.count, outcome: "ok", seconds: "0s")
            }
        }
    }

    private func trash() {
        var count = 0
        for path in selected {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                count += 1
            } catch { message = error.localizedDescription }
        }
        message = "Moved \(count) files to the Trash."
        selected = []
        groups = []
    }
}

private enum DuplicateScan {
    static func collect(_ root: URL) -> [DuplicateFile] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [DuplicateFile] = []
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            files.append(DuplicateFile(path: item.path, size: Int64(values?.fileSize ?? 0)))
        }
        return files
    }
}

private struct ZipTool: View {
    @State private var urls: [URL] = []
    @State private var message = ""
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.zipUnzip)) {
            DropZone(prompt: "Drop files to zip, or a zip to unpack", types: [.item]) { urls = $0 }
            ForEach(urls, id: \.path) { Text($0.lastPathComponent).font(.system(size: 12)) }
            HStack {
                PrimaryButton(title: "Zip", enabled: !urls.isEmpty) { zip() }
                PrimaryButton(title: "Unzip", enabled: urls.contains { $0.pathExtension.lowercased() == "zip" }) { unzip() }
            }
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func zip() {
        guard let first = urls.first else { return }
        let start = Date()
        do {
            let output = try Outputs.make(nextTo: first, suffix: "-archive", ext: "zip")
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for url in urls {
                let dest = temp.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: dest)
            }
            let result = Commands.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", temp.path, output.path])
            try? FileManager.default.removeItem(at: temp)
            guard result.status == 0 else { throw ToolError(message: result.output) }
            message = "Saved \(output.lastPathComponent)"
            SatchelLog.toolRun(id: ToolID.zipUnzip.rawValue, inputs: urls.count, outcome: "ok", seconds: RunLog.stamp(start))
        } catch { message = error.localizedDescription }
    }

    private func unzip() {
        guard let zip = urls.first(where: { $0.pathExtension.lowercased() == "zip" }) else { return }
        let start = Date()
        do {
            let folder = try Outputs.folder(nextTo: zip, nameSuffix: "-unpacked")
            let result = Commands.run("/usr/bin/ditto", ["-xk", zip.path, folder.path])
            guard result.status == 0 else { throw ToolError(message: result.output) }
            message = "Unpacked into \(folder.lastPathComponent)"
            Outputs.reveal(folder)
            SatchelLog.toolRun(id: ToolID.zipUnzip.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
        } catch { message = error.localizedDescription }
    }
}

private struct OrganizeTool: View {
    @StateObject private var permission = PermissionCoordinator(tool: .organizeDownloads)
    @State private var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @State private var moves: [PlannedMove] = []
    @State private var message = ""
    @State private var confirm = false
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.organizeDownloads)) {
            Text(folder.path).font(.system(size: 12)).textSelection(.enabled)
            PrimaryButton(title: "Preview Downloads", enabled: true) { preview() }
            Button("Choose another folder") { choose() }
            PermissionBannerSlot(coordinator: permission)
            ForEach(moves, id: \.name) { move in
                HStack {
                    Text(move.name).lineLimit(1)
                    Spacer()
                    Text(move.folder).foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }
            PrimaryButton(title: "Move files", enabled: !moves.isEmpty) { confirm = true }
            Text("Files are moved into folders, not deleted. Hidden files and the folders themselves stay put.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
        .confirmationDialog("Move \(moves.count) files into folders?", isPresented: $confirm) {
            Button("Move") { apply() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
            permission.clear()
        }
    }

    private func preview() {
        Task {
            if let kind = PermissionClassifier.folderKind(for: folder) {
                guard await permission.ensure(kind, retry: { preview() }) else {
                    moves = []
                    message = ""
                    return
                }
            }
            do {
                let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                let mapped = entries.map { url -> DownloadEntry in
                    let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    return DownloadEntry(name: url.lastPathComponent, isDirectory: dir)
                }
                moves = DownloadOrganizer.plan(mapped)
                message = moves.isEmpty ? "Nothing to sort." : "\(moves.count) files would move."
            } catch {
                moves = []
                if permission.handleError(error, targetURL: folder, retry: { preview() }) {
                    message = ""
                } else {
                    message = error.localizedDescription
                }
            }
        }
    }

    private func apply() {
        let start = Date()
        var moved = 0
        do {
            for move in moves {
                let source = folder.appendingPathComponent(move.name)
                let destinationFolder = folder.appendingPathComponent(move.folder, isDirectory: true)
                try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                var destination = destinationFolder.appendingPathComponent(move.name)
                if FileManager.default.fileExists(atPath: destination.path) {
                    let unique = OutputNaming.unique(move.name, existing: Set(try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path)))
                    destination = destinationFolder.appendingPathComponent(unique)
                }
                try FileManager.default.moveItem(at: source, to: destination)
                moved += 1
            }
            message = "Moved \(moved) files."
            moves = []
            SatchelLog.toolRun(id: ToolID.organizeDownloads.rawValue, inputs: moved, outcome: "ok", seconds: RunLog.stamp(start))
        } catch {
            if permission.handleError(error, targetURL: folder, retry: { apply() }) {
                message = ""
            } else {
                message = error.localizedDescription
            }
        }
    }
}
