import AppKit
import SwiftUI
import SatchelCore

enum Palette {
    /// Quiet indigo, not the system-blue used by the earlier layout.
    static let accent = Color(red: 0.31, green: 0.35, blue: 0.70)

    static func canvasTop(_ scheme: ColorScheme) -> Color {
        Color(nsColor: scheme == .dark ? .windowBackgroundColor : .windowBackgroundColor)
    }

    static func canvasBottom(_ scheme: ColorScheme) -> Color {
        canvasTop(scheme)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static func chip(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.14 : 0.06)
    }

    static func track(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.10 : 0.05)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        Color.secondary
    }

    static func titleMuted(_ scheme: ColorScheme) -> Color {
        Color.secondary
    }

    static func hairline(_ scheme: ColorScheme, strong: Bool) -> Color {
        Color.primary.opacity(strong ? 0.28 : (scheme == .dark ? 0.14 : 0.08))
    }

    static func sidebar(_ scheme: ColorScheme) -> Color {
        Color(nsColor: scheme == .dark ? .underPageBackgroundColor : .windowBackgroundColor)
    }
}

private struct SnapshotFlagKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SampleResultKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SimulatedPermissionDeniedKey: EnvironmentKey {
    static let defaultValue: PermissionKind? = nil
}

extension EnvironmentValues {
    var satchelSnapshot: Bool {
        get { self[SnapshotFlagKey.self] }
        set { self[SnapshotFlagKey.self] = newValue }
    }

    var satchelSampleResult: Bool {
        get { self[SampleResultKey.self] }
        set { self[SampleResultKey.self] = newValue }
    }

    var satchelSimulatedPermissionDenied: PermissionKind? {
        get { self[SimulatedPermissionDeniedKey.self] }
        set { self[SimulatedPermissionDeniedKey.self] = newValue }
    }
}

struct CanvasBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}
