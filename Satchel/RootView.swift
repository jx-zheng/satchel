import AppKit
import SwiftUI
import SatchelCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.satchelSnapshot) private var snapshot
    @FocusState private var searchFocused: Bool
    @State private var monitor: Any?
    @State private var searchLog: Task<Void, Never>?

    var body: some View {
        ZStack {
            CanvasBackground()
            VStack(spacing: 0) {
                TopBar(searchFocused: $searchFocused)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: snapshot ? 1440 : 1080, minHeight: snapshot ? 900 : 680)
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
                model.closeTool()
                return nil
            }
            if model.isSearching {
                model.query = ""
                return nil
            }
        }
        if model.openTool == nil, !model.isSearching, model.category != nil {
            let columns = 5
            switch key {
            case 124: model.moveSelection(by: 1); return nil
            case 123: model.moveSelection(by: -1); return nil
            case 125: model.moveSelection(by: columns); return nil
            case 126: model.moveSelection(by: -columns); return nil
            case 36, 76: model.openSelection(); return nil
            default: break
            }
        }
        return event
    }
}

struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @FocusState.Binding var searchFocused: Bool

    private var tabs: [(String, ToolCategory?)] {
        [("All", nil)] + ToolCategory.allCases.map { ($0.title, Optional($0)) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 70)
            HStack(spacing: 2) {
                ForEach(tabs, id: \.0) { tab in
                    let selected = model.category == tab.1 && model.openTool == nil
                    Button {
                        model.selectTab(tab.1)
                    } label: {
                        Text(tab.0)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? (scheme == .dark ? Color.white : Color.black) : Palette.secondaryText(scheme))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(selected ? Palette.chip(scheme) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Palette.track(scheme)))
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondaryText(scheme))
                TextField("Search tools", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondaryText(scheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 210, height: 30)
            .background(Capsule().fill(Palette.chip(scheme)))
            .overlay(Capsule().strokeBorder(Palette.hairline(scheme, strong: false)))
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
