import SwiftUI

enum Palette {
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)

    static func canvasTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.07, green: 0.08, blue: 0.095)
            : Color(red: 0.90, green: 0.945, blue: 0.935)
    }

    static func canvasBottom(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.04, green: 0.045, blue: 0.055)
            : Color(red: 0.82, green: 0.89, blue: 0.885)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.125, green: 0.14, blue: 0.165) : .white
    }

    static func chip(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : .white
    }

    static func track(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.62, green: 0.67, blue: 0.73)
            : Color(red: 0.36, green: 0.42, blue: 0.46)
    }

    static func titleMuted(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.55, green: 0.62, blue: 0.68)
            : Color(red: 0.42, green: 0.52, blue: 0.56)
    }

    static func hairline(_ scheme: ColorScheme, strong: Bool) -> Color {
        if scheme == .dark {
            return Color.white.opacity(strong ? 0.72 : 0.10)
        }
        return Color.black.opacity(strong ? 0.16 : 0.06)
    }
}

private struct SnapshotFlagKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var satchelSnapshot: Bool {
        get { self[SnapshotFlagKey.self] }
        set { self[SnapshotFlagKey.self] = newValue }
    }
}

struct CanvasBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: [Palette.canvasTop(scheme), Palette.canvasBottom(scheme)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
