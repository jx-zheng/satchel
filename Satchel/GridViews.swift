import SwiftUI
import SatchelCore

struct CategoryGrid: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let category: ToolCategory

    var body: some View {
        let tools = ToolRegistry.tools(in: category)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(count: tools.count)
                grouped(tools)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.title)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(count) tools · \(category.tagline)")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func grouped(_ tools: [ToolDefinition]) -> some View {
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

struct ResultGrid: View {
    @EnvironmentObject private var model: AppModel
    let tools: [ToolDefinition]
    let query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tools.isEmpty ? "No matches" : "\(tools.count) tools")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(tools.isEmpty ? "Nothing for “\(query)”" : "Search")
                        .font(.largeTitle.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if tools.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Try a shorter word, such as pdf, audio, or rename.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                            ToolRow(tool: tool, selected: model.selection == tool.id)
                            if index < tools.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ToolRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let tool: ToolDefinition
    var selected: Bool

    var body: some View {
        Button {
            model.open(tool.id)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ToolArt(tool: tool, compact: true)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(tool.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.accent.opacity(scheme == .dark ? 0.22 : 0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.name)
        .accessibilityHint(tool.summary)
    }
}
