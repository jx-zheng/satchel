import SwiftUI
import SatchelCore

struct ToolRouter: View {
    let tool: ToolDefinition

    var body: some View {
        if tool.status == .placeholder {
            ComingSoonView(tool: tool)
        } else {
            switch tool.category {
            case .video:
                VideoToolScreen(id: tool.id)
            case .audio:
                AudioToolScreen(id: tool.id)
            case .images:
                ImageToolScreen(id: tool.id)
            case .docs:
                DocToolScreen(id: tool.id)
            case .text:
                TextToolScreen(id: tool.id)
            case .files:
                FileToolScreen(id: tool.id)
            case .mac:
                MacToolScreen(id: tool.id)
            case .dev:
                DevToolScreen(id: tool.id)
            }
        }
    }
}
