import SwiftUI
import SatchelCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let plan = model.homePlan
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                hero
                if !model.incomingFiles.isEmpty {
                    incomingNote
                }
                continueRow(plan.recentIDs)
                if !plan.favoriteIDs.isEmpty {
                    favoriteRow(plan.favoriteIDs)
                }
                suggested(plan)
                ForEach(plan.categoryCards, id: \.category) { card in
                    categoryBlock(card)
                }
                savingsLine
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Satchel")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
            Text("What do you want to finish?")
                .font(.system(size: 34, weight: .semibold, design: .default))
                .fixedSize(horizontal: false, vertical: true)
            Text("Video, sound, pictures, documents, and the small chores that pile up. The files stay here.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
        }
        .padding(.bottom, 4)
    }

    private var incomingNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .foregroundStyle(Palette.accent)
            Text("\(model.incomingFiles.count) file\(model.incomingFiles.count == 1 ? "" : "s") waiting. Open a tool, then press ⌘↩.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.accent.opacity(0.08)))
    }

    private func continueRow(_ ids: [ToolID]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Continue", detail: ids.isEmpty ? "Nothing opened yet" : nil)
            if ids.isEmpty {
                Text("Tools you open will line up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                chipScroll(ids)
            }
        }
    }

    private func favoriteRow(_ ids: [ToolID]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Favorites", detail: nil)
            chipScroll(ids)
        }
    }

    private func chipScroll(_ ids: [ToolID]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    if let tool = ToolRegistry.byID[id] {
                        Button {
                            model.open(id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tool.symbol)
                                    .foregroundStyle(Palette.accent)
                                Text(tool.name)
                                    .lineLimit(1)
                            }
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Palette.chip(scheme)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func suggested(_ plan: HomePlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Suggested", detail: nil)
            VStack(spacing: 0) {
                let tools = plan.spotlight.prefix(4).compactMap { ToolRegistry.byID[$0] }
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                    ToolRow(tool: tool, selected: model.selection == tool.id)
                    if index < tools.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.card(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline(scheme, strong: false)))
        }
    }

    private func categoryBlock(_ card: CategoryCardPlan) -> some View {
        let tools = ToolRegistry.tools(in: card.category).prefix(4)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(card.category.title, detail: "\(card.total) tools")
                Spacer()
                Button("See all") { model.selectTab(card.category) }
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
            VStack(spacing: 0) {
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                    ToolRow(tool: tool, selected: model.selection == tool.id)
                    if index < tools.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.card(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline(scheme, strong: false)))
        }
    }

    private var savingsLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
            Text(model.savings.files == 0
                 ? "Compress tools will note what they save, this week."
                 : "\(ByteFormat.string(bytes: model.savings.bytes)) saved across \(model.savings.files) files this week.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
