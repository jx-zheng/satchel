import SwiftUI
import SatchelCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var spotlightIndex = 0

    var body: some View {
        let plan = model.homePlan
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(plan)
                topRow(plan)
                middleRow(plan)
                featureRow(plan)
                macRow(plan)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
    }

    private func header(_ plan: HomePlan) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(ToolRegistry.all.count) tools")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondaryText(scheme))
                    .padding(.bottom, 2)
                Text("A satchel of tools,")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Color.white : Color(red: 0.09, green: 0.11, blue: 0.13))
                Text("kept on this Mac.")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Palette.titleMuted(scheme))
            }
            Spacer(minLength: 12)
            recentChips(plan.recentIDs)
        }
        .padding(.top, 4)
    }

    private func recentChips(_ ids: [ToolID]) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Recent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.secondaryText(scheme))
            HStack(spacing: 6) {
                if ids.isEmpty {
                    Text("Tools you open show up here")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText(scheme))
                } else {
                    ForEach(ids, id: \.self) { id in
                        if let tool = ToolRegistry.byID[id] {
                            Button {
                                model.open(id)
                            } label: {
                                Text(tool.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Palette.chip(scheme)))
                                    .overlay(Capsule().strokeBorder(Palette.hairline(scheme, strong: false)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func topRow(_ plan: HomePlan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            spotlight(plan.spotlight)
                .frame(maxWidth: .infinity)
            if plan.categoryCards.count > 1 {
                categoryCard(plan.categoryCards[0])
                    .frame(maxWidth: .infinity)
                categoryCard(plan.categoryCards[1])
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 228)
    }

    private func spotlight(_ ids: [ToolID]) -> some View {
        let tools = ids.compactMap { ToolRegistry.byID[$0] }
        let index = tools.isEmpty ? 0 : min(spotlightIndex, tools.count - 1)
        return ZStack {
            if tools.isEmpty {
                cardBody { Text("No tools yet") }
            } else {
                let tool = tools[index]
                cardBody {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start here · New to you")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                            Text(tool.name)
                                .font(.system(size: 26, weight: .bold))
                            Text(tool.summary)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.secondaryText(scheme))
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            HStack(spacing: 8) {
                                Button {
                                    model.open(tool.id)
                                } label: {
                                    Text("Open \(tool.name)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(Palette.accent))
                                }
                                .buttonStyle(.plain)
                                Button { step(tools.count, -1) } label: {
                                    Image(systemName: "chevron.left")
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(Palette.track(scheme)))
                                }
                                .buttonStyle(.plain)
                                Button { step(tools.count, 1) } label: {
                                    Image(systemName: "chevron.right")
                                        .frame(width: 28, height: 28)
                                        .background(Circle().fill(Palette.track(scheme)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        ToolArt(tool: tool)
                            .frame(width: 180, height: 168)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func step(_ count: Int, _ delta: Int) {
        guard count > 0 else { return }
        spotlightIndex = (spotlightIndex + delta + count) % count
    }

    private func middleRow(_ plan: HomePlan) -> some View {
        let cards = Array(plan.categoryCards.dropFirst(2).prefix(3))
        return HStack(alignment: .top, spacing: 12) {
            ForEach(cards, id: \.category) { card in
                categoryCard(card)
                    .frame(maxWidth: .infinity)
            }
            statCard
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 168)
    }

    private func categoryCard(_ card: CategoryCardPlan) -> some View {
        cardBody {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: card.category.symbol)
                        .foregroundStyle(Palette.accent)
                    Text(card.category.title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(card.total) tools")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.secondaryText(scheme))
                }
                let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(card.shownNames, id: \.self) { name in
                        Button {
                            if let tool = ToolRegistry.tools(in: card.category).first(where: { $0.name == name }) {
                                model.open(tool.id)
                            }
                        } label: {
                            Text(name)
                                .font(.system(size: 12))
                                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.78))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    model.selectTab(card.category)
                } label: {
                    Text(card.moreCount > 0 ? "\(card.moreCount) more" : "Open")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
    }

    private var statCard: some View {
        cardBody {
            VStack(alignment: .leading, spacing: 6) {
                Text("This week")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText(scheme))
                Text(ByteFormat.string(bytes: model.savings.bytes))
                    .font(.system(size: 28, weight: .bold))
                Text(model.savings.files == 0
                     ? "Nothing saved yet"
                     : "saved on \(model.savings.files) files")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondaryText(scheme))
                Spacer(minLength: 0)
                Text("From compress tools")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText(scheme))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func featureRow(_ plan: HomePlan) -> some View {
        HStack(alignment: .top, spacing: 12) {
            favoritesCard(plan.favoriteIDs)
                .frame(maxWidth: .infinity)
            ForEach(plan.featureIDs, id: \.self) { id in
                if let tool = ToolRegistry.byID[id] {
                    Button {
                        model.open(id)
                    } label: {
                        cardBody {
                            VStack(alignment: .leading, spacing: 8) {
                                ToolArt(tool: tool, compact: true)
                                    .frame(height: 72)
                                Text(tool.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(scheme == .dark ? .white : .black)
                                Text(tool.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.secondaryText(scheme))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func favoritesCard(_ ids: [ToolID]) -> some View {
        cardBody {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("Favorites")
                        .font(.system(size: 15, weight: .semibold))
                }
                if ids.isEmpty {
                    Text("Star a tool and it stays here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText(scheme))
                } else {
                    ForEach(ids.prefix(4), id: \.self) { id in
                        if let tool = ToolRegistry.byID[id] {
                            Button {
                                model.open(id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: tool.symbol)
                                        .frame(width: 16)
                                        .foregroundStyle(Palette.accent)
                                    Text(tool.name)
                                        .font(.system(size: 13))
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 150)
    }

    private func macRow(_ plan: HomePlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mac")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(ToolRegistry.tools(in: .mac).count) tools")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText(scheme))
                Spacer()
                Button {
                    model.selectTab(.mac)
                } label: {
                    Text("\(plan.macMore) more")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                ForEach(plan.macRow, id: \.self) { id in
                    if let tool = ToolRegistry.byID[id] {
                        Button {
                            model.open(id)
                        } label: {
                            cardBody {
                                HStack(alignment: .center, spacing: 10) {
                                    ToolArt(tool: tool, compact: true)
                                        .frame(width: 86, height: 68)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tool.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(scheme == .dark ? .white : .black)
                                            .lineLimit(1)
                                        Text(tool.summary)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Palette.secondaryText(scheme))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func cardBody<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.hairline(scheme, strong: false))
            )
            .shadow(color: scheme == .dark ? .clear : Color.black.opacity(0.06), radius: 14, y: 6)
    }
}

