import SwiftUI
import SatchelCore

/// Symbol medallion used in place of the old per-tool illustration set.
struct ToolArt: View {
    let tool: ToolDefinition
    var compact = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
                .fill(Palette.accent.opacity(0.12))
            Image(systemName: tool.symbol)
                .font(.system(size: compact ? 16 : 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.accent)
        }
        .accessibilityHidden(true)
    }
}
