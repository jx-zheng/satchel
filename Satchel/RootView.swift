import AppKit
import SwiftUI
import SatchelCore

enum TabHitFrames {
    static var latest: [String: CGRect] = [:]
}

private struct TabFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension Notification.Name {
    static let satchelRun = Notification.Name("satchel.run")
    static let satchelOpenPanel = Notification.Name("satchel.openPanel")
    static let satchelIncomingFiles = Notification.Name("satchel.incomingFiles")
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.satchelSnapshot) private var snapshot
    @FocusState private var searchFocused: Bool
    @State private var monitor: Any?
    @State private var searchLog: Task<Void, Never>?
    @State private var choosingFile = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 252)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .coordinateSpace(name: "satchel-root")
        .onPreferenceChange(TabFrameKey.self) { TabHitFrames.latest = $0 }
        .frame(minWidth: snapshot ? 1440 : 880, minHeight: snapshot ? 900 : 560)
        .onAppear {
            guard !snapshot else { return }
            installMonitor()
        }
        .onDisappear {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        .onChange(of: model.searchFocusTick) { _, _ in
            searchFocused = true
        }
        .onChange(of: searchFocused) { _, focused in
            model.searchFieldFocused = focused
        }
        .onChange(of: model.query) { _, newValue in
            guard !snapshot else { return }
            model.selection = model.searchResults.first?.id
            searchLog?.cancel()
            searchLog = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                let length = newValue.trimmingCharacters(in: .whitespacesAndNewlines).count
                SatchelLog.search(length: length, results: model.searchResults.count)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .satchelOpenPanel)) { _ in
            choosingFile = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .satchelIncomingFiles)) { note in
            if let urls = note.object as? [URL], !urls.isEmpty {
                model.incomingFiles = urls
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case let .success(urls) = result {
                for url in urls { _ = url.startAccessingSecurityScopedResource() }
                model.incomingFiles = urls
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            FileDrop.load(providers) { model.incomingFiles = $0 }
            return true
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if let icon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
                Text("Satchel")
                    .font(.headline)
            }
            .padding(.horizontal, 8)
            .padding(.top, 16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search tools", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($searchFocused)
                    .accessibilityIdentifier("tool-search")
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.chip(scheme)))

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tabs, id: \.0) { tab in
                        tabButton(tab.0, tab.1)
                    }
                }
                .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar(scheme))
    }

    private var tabs: [(String, ToolCategory?)] {
        [("All", nil)] + ToolCategory.allCases.map { ($0.title, Optional($0)) }
    }

    private func tabButton(_ title: String, _ category: ToolCategory?) -> some View {
        let selected = model.category == category && model.openTool == nil && !model.isSearching
        return Button {
            model.query = ""
            model.selectTab(category)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category?.symbol ?? "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Palette.accent : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(selected ? Palette.accent.opacity(scheme == .dark ? 0.28 : 0.14) : Color.clear))
            .contentShape(Capsule())
            .background(GeometryReader { geo in
                Color.clear.preference(key: TabFrameKey.self, value: [title: geo.frame(in: .named("satchel-root"))])
            })
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityIdentifier("tab-\(title)")
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            if let id = model.openTool, let tool = ToolRegistry.byID[id] {
                ToolRouter(tool: tool)
            } else if model.isSearching {
                ResultGrid(tools: model.searchResults, query: model.trimmedQuery)
            } else if let category = model.category {
                CategoryGrid(category: category)
            } else {
                HomeView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            model.focusSearch()
            return nil
        }
        let key = event.keyCode
        if model.searchFieldFocused {
            switch key {
            case 125, 124:
                model.moveSelection(by: 1)
                return nil
            case 126, 123:
                model.moveSelection(by: -1)
                return nil
            case 36, 76:
                model.openSelection()
                return nil
            case 53:
                model.query = ""
                return nil
            default:
                return event
            }
        }
        let editing = NSApp.keyWindow?.firstResponder is NSTextView
        if editing { return event }
        if key == 53 {
            if model.openTool != nil {
                if model.toolRunning {
                    model.requestCancel()
                } else {
                    model.closeTool()
                }
                return nil
            }
            if model.isSearching {
                model.query = ""
                return nil
            }
        }
        if model.openTool == nil {
            switch key {
            case 124, 125: model.moveSelection(by: 1); return nil
            case 123, 126: model.moveSelection(by: -1); return nil
            case 36, 76: model.openSelection(); return nil
            default: break
            }
        }
        return event
    }
}
