import Foundation

public struct CategoryCardPlan: Equatable, Sendable {
    public var category: ToolCategory
    public var total: Int
    public var shownNames: [String]
    public var moreCount: Int

    public init(category: ToolCategory, total: Int, shownNames: [String], moreCount: Int) {
        self.category = category
        self.total = total
        self.shownNames = shownNames
        self.moreCount = moreCount
    }
}

public struct HomePlan: Equatable, Sendable {
    public var spotlight: [ToolID]
    public var categoryCards: [CategoryCardPlan]
    public var featureIDs: [ToolID]
    public var macRow: [ToolID]
    public var macMore: Int
    public var recentIDs: [ToolID]
    public var favoriteIDs: [ToolID]

    public init(
        spotlight: [ToolID],
        categoryCards: [CategoryCardPlan],
        featureIDs: [ToolID],
        macRow: [ToolID],
        macMore: Int,
        recentIDs: [ToolID],
        favoriteIDs: [ToolID]
    ) {
        self.spotlight = spotlight
        self.categoryCards = categoryCards
        self.featureIDs = featureIDs
        self.macRow = macRow
        self.macMore = macMore
        self.recentIDs = recentIDs
        self.favoriteIDs = favoriteIDs
    }
}

public enum HomeLayout {
    public static let namesPerCategoryCard = 8
    public static let macRowCount = 4
    public static let recentChipLimit = 4

    /// Headline tools shown as feature cards on the home bento.
    public static let featureIDs: [ToolID] = [.compressVideo, .removeBackground, .batchRename]

    /// Preferred spotlight order. Tools the person has already opened drop out when alternatives remain.
    public static let spotlightOrder: [ToolID] = [
        .compressVideo, .removeBackground, .signPDF, .transcribe, .redactPDF,
        .batchRename, .storageExplorer, .beautifyScreenshot, .mergePDFs, .qrCode,
        .extractText, .keepAwake
    ]

    /// Category cards on the home bento, in visual order. Mac has its own row.
    public static let homeCategories: [ToolCategory] = [.docs, .video, .images, .audio, .text, .files]

    public static func make(
        catalog: [ToolDefinition] = ToolRegistry.all,
        recents: [ToolID],
        favorites: [ToolID]
    ) -> HomePlan {
        let known = Set(catalog.map(\.id))
        let recentValid = recents.filter { known.contains($0) }
        let favoriteValid = favorites.filter { known.contains($0) }
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let opened = Set(recentValid)

        var spotlight = spotlightOrder.filter { id in
            guard let tool = byID[id], tool.status == .working else { return false }
            return !opened.contains(id)
        }
        if spotlight.isEmpty {
            spotlight = spotlightOrder.filter { byID[$0]?.status == .working }
        }

        let cards = homeCategories.map { category -> CategoryCardPlan in
            let tools = catalog.filter { $0.category == category }
            let shown = Array(tools.prefix(namesPerCategoryCard).map(\.name))
            return CategoryCardPlan(
                category: category,
                total: tools.count,
                shownNames: shown,
                moreCount: max(0, tools.count - shown.count)
            )
        }

        let macTools = catalog.filter { $0.category == .mac }
        let macRow = Array(macTools.prefix(macRowCount).map(\.id))
        return HomePlan(
            spotlight: spotlight,
            categoryCards: cards,
            featureIDs: featureIDs.filter { byID[$0] != nil },
            macRow: macRow,
            macMore: max(0, macTools.count - macRow.count),
            recentIDs: Array(recentValid.prefix(recentChipLimit)),
            favoriteIDs: favoriteValid
        )
    }
}

public enum RecentList {
    public static let storeLimit = 12

    public static func push(_ id: ToolID, into list: [ToolID]) -> [ToolID] {
        var next = [id]
        next.append(contentsOf: list.filter { $0 != id })
        if next.count > storeLimit {
            next.removeLast(next.count - storeLimit)
        }
        return next
    }
}

public enum FavoriteList {
    public static func toggle(_ id: ToolID, in list: [ToolID]) -> [ToolID] {
        if let index = list.firstIndex(of: id) {
            var next = list
            next.remove(at: index)
            return next
        }
        return list + [id]
    }
}

public struct WeekSavings: Equatable, Codable, Sendable {
    public var weekKey: String
    public var bytes: Int64
    public var files: Int

    public init(weekKey: String, bytes: Int64, files: Int) {
        self.weekKey = weekKey
        self.bytes = bytes
        self.files = files
    }

    public static let empty = WeekSavings(weekKey: "", bytes: 0, files: 0)

    public static func key(for date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        var cal = calendar
        if cal.identifier != .iso8601 {
            cal = Calendar(identifier: .iso8601)
            cal.timeZone = calendar.timeZone
        }
        let year = cal.component(.yearForWeekOfYear, from: date)
        let week = cal.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    /// Adds a real size reduction. A new ISO week replaces the previous totals.
    public func recording(saved bytes: Int64, fileCount: Int, on date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> WeekSavings {
        let saved = max(0, bytes)
        let count = max(0, fileCount)
        let key = Self.key(for: date, calendar: calendar)
        if weekKey != key {
            return WeekSavings(weekKey: key, bytes: saved, files: count)
        }
        return WeekSavings(weekKey: key, bytes: self.bytes + saved, files: self.files + count)
    }
}

public enum ByteFormat {
    public static func string(bytes: Int64) -> String {
        let negative = bytes < 0
        let magnitude = bytes == Int64.min ? Double(Int64.max) : Double(abs(bytes))
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = magnitude
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        let body: String
        if index == 0 {
            body = "\(Int(value)) \(units[index])"
        } else if value >= 100 {
            body = String(format: "%.0f %@", value, units[index])
        } else if value >= 10 {
            body = String(format: "%.1f %@", value, units[index])
        } else {
            body = String(format: "%.2f %@", value, units[index])
        }
        return negative ? "-\(body)" : body
    }
}
