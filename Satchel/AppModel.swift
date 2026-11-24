import Foundation
import SwiftUI
import SatchelCore

@MainActor
final class AppModel: ObservableObject {
    @Published var category: ToolCategory?
    @Published var openTool: ToolID?
    @Published var query = ""
    @Published var recents: [ToolID] = []
    @Published var favorites: [ToolID] = []
    @Published var savings = WeekSavings.empty
    @Published var drafts: [String: String] = [:]
    @Published var selection: ToolID?
    @Published var searchFocusTick = 0
    @Published var searchFieldFocused = false
    @Published var toolRunning = false
    @Published var cancelTick = 0
    @Published var incomingFiles: [URL] = []
    var runClaim: String?

    private let defaults: UserDefaults
    private let persists: Bool

    init(defaults: UserDefaults = .standard, persists: Bool = true) {
        self.defaults = defaults
        self.persists = persists
        if persists {
            load()
        }
    }

    static func snapshotModel() -> AppModel {
        let model = AppModel(persists: false)
        model.recents = [.compressVideo, .mergePDFs, .removeBackground, .transcribe]
        model.favorites = [.signPDF, .keepAwake, .batchRename]
        model.savings = WeekSavings(weekKey: WeekSavings.key(for: Date()), bytes: 0, files: 0)
        return model
    }

    var homePlan: HomePlan {
        HomeLayout.make(recents: recents, favorites: favorites)
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool { !trimmedQuery.isEmpty }

    var searchResults: [ToolDefinition] {
        ToolSearch.results(query: query, in: ToolRegistry.all, category: nil)
    }

    var visibleTools: [ToolDefinition] {
        if isSearching { return searchResults }
        if let category { return ToolRegistry.tools(in: category) }
        let plan = homePlan
        var ids = plan.recentIDs + plan.spotlight
        for card in plan.categoryCards {
            ids.append(contentsOf: ToolRegistry.tools(in: card.category).prefix(4).map(\.id))
        }
        var seen = Set<ToolID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return ToolRegistry.byID[id]
        }
    }

    func selectTab(_ category: ToolCategory?) {
        self.category = category
        openTool = nil
        selection = nil
        SatchelLog.tab(category?.title ?? "All")
    }

    func open(_ id: ToolID) {
        if let tool = ToolRegistry.byID[id] {
            category = category ?? nil
            if category == nil {
                // Stay on the current tab. Opening a tool does not switch tabs.
            } else if tool.category != category && isSearching {
                category = tool.category
            }
        }
        openTool = id
        recents = RecentList.push(id, into: recents)
        selection = id
        persistRecents()
        SatchelLog.opened(id.rawValue)
    }

    func closeTool() {
        openTool = nil
        toolRunning = false
        runClaim = nil
    }

    func requestCancel() {
        cancelTick += 1
    }

    func toggleFavorite(_ id: ToolID) {
        favorites = FavoriteList.toggle(id, in: favorites)
        persistFavorites()
    }

    func isFavorite(_ id: ToolID) -> Bool {
        favorites.contains(id)
    }

    func focusSearch() {
        searchFocusTick += 1
    }

    func moveSelection(by delta: Int) {
        let tools = visibleTools
        guard !tools.isEmpty else { return }
        let current = tools.firstIndex(where: { $0.id == selection }) ?? (delta > 0 ? -1 : 0)
        let next = min(max(0, current + delta), tools.count - 1)
        selection = tools[next].id
    }

    func openSelection() {
        let tools = visibleTools
        if let selection, tools.contains(where: { $0.id == selection }) {
            open(selection)
        } else if let first = tools.first {
            open(first.id)
        }
    }

    func draft(for id: ToolID) -> String {
        drafts[id.rawValue] ?? ""
    }

    func setDraft(_ id: ToolID, _ text: String) {
        let clipped = text.count > 200_000 ? String(text.prefix(200_000)) : text
        drafts[id.rawValue] = clipped
        guard persists else { return }
        defaults.set(drafts, forKey: Keys.drafts)
    }

    func binding(for id: ToolID) -> Binding<String> {
        Binding(
            get: { self.draft(for: id) },
            set: { self.setDraft(id, $0) }
        )
    }

    func noteSavings(bytes: Int64, files: Int) {
        guard bytes > 0, files > 0 else { return }
        savings = savings.recording(saved: bytes, fileCount: files, on: Date())
        guard persists else { return }
        if let data = try? JSONEncoder().encode(savings) {
            defaults.set(data, forKey: Keys.savings)
        }
    }

    private enum Keys {
        static let recents = "satchel.recents"
        static let favorites = "satchel.favorites"
        static let savings = "satchel.savings"
        static let drafts = "satchel.drafts"
    }

    private func load() {
        if let raw = defaults.stringArray(forKey: Keys.recents) {
            recents = raw.compactMap(ToolID.init(rawValue:))
        }
        if let raw = defaults.stringArray(forKey: Keys.favorites) {
            favorites = raw.compactMap(ToolID.init(rawValue:))
        }
        if let data = defaults.data(forKey: Keys.savings),
           let saved = try? JSONDecoder().decode(WeekSavings.self, from: data) {
            let key = WeekSavings.key(for: Date())
            savings = saved.weekKey == key ? saved : WeekSavings(weekKey: key, bytes: 0, files: 0)
        } else {
            savings = WeekSavings(weekKey: WeekSavings.key(for: Date()), bytes: 0, files: 0)
        }
        if let stored = defaults.dictionary(forKey: Keys.drafts) as? [String: String] {
            drafts = stored
        }
    }

    private func persistRecents() {
        guard persists else { return }
        defaults.set(recents.map(\.rawValue), forKey: Keys.recents)
    }

    private func persistFavorites() {
        guard persists else { return }
        defaults.set(favorites.map(\.rawValue), forKey: Keys.favorites)
    }
}
