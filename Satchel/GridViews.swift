import SwiftUI
import SatchelCore

struct CategoryGrid: View {
    @EnvironmentObject private var model: AppModel
    let category: ToolCategory

    var body: some View {
        let tools = ToolRegistry.tools(in: category)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(count: tools.count)
                ToolGrid(tools: tools)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) tools · \(category.tagline)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(category.title)
                    .font(.system(size: 34, weight: .bold))
            }
            Spacer()
            recentChips
        }
        .padding(.top, 6)
    }

    private var recentChips: some View {
        let ids = model.homePlan.recentIDs
        return VStack(alignment: .trailing, spacing: 6) {
            Text("Recent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if ids.isEmpty {
                    Text("None yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ids, id: \.self) { id in
                        if let tool = ToolRegistry.byID[id] {
                            Button(tool.name) { model.open(id) }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
            }
        }
    }
}

struct ResultGrid: View {
    @EnvironmentObject private var model: AppModel
    let tools: [ToolDefinition]
    let query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tools.isEmpty ? "No matches" : "\(tools.count) tools")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(tools.isEmpty ? "Nothing for “\(query)”" : "Search")
                        .font(.system(size: 34, weight: .bold))
                }
                .padding(.top, 6)
                if tools.isEmpty {
                    Text("Try a shorter word, like “pdf”, “audio”, or “rename”.")
                        .foregroundStyle(.secondary)
                } else {
                    ToolGrid(tools: tools)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }
}

struct ToolGrid: View {
    @EnvironmentObject private var model: AppModel
    let tools: [ToolDefinition]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 5)
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(tools) { tool in
                ToolCard(tool: tool, selected: model.selection == tool.id)
                    .gridCellColumns(tool.spansTwoColumns ? 2 : 1)
            }
        }
    }

}

struct ToolCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let tool: ToolDefinition
    var selected: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            model.open(tool.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    ToolArt(tool: tool)
                        .frame(maxWidth: .infinity)
                        .frame(height: 124)
                        .padding(8)
                    if tool.status == .placeholder {
                        Text("Soon")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(14)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                    Text(tool.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, minHeight: 196, alignment: .top)
            .background(Palette.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        (hovering || selected)
                            ? (scheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.18))
                            : Palette.hairline(scheme, strong: false),
                        lineWidth: hovering || selected ? 1.25 : 1
                    )
            )
            .shadow(color: (hovering || selected) ? Color.white.opacity(scheme == .dark ? 0.18 : 0) : .clear, radius: 10)
            .shadow(color: scheme == .dark ? .clear : Color.black.opacity(hovering ? 0.08 : 0.04), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
