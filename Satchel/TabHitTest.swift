import AppKit
import SwiftUI
import SatchelCore

enum TabHitTest {
    @MainActor
    static func clickEdgeSelectsVideo() throws {
        TabHitFrames.latest = [:]
        let model = AppModel(persists: false)
        let host = NSHostingView(
            rootView: RootView()
                .environmentObject(model)
                .environment(\.satchelSnapshot, true)
                .frame(width: 1440, height: 900)
        )
        host.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        defer {
            host.removeFromSuperview()
            window.contentView = nil
            window.orderOut(nil)
        }
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()

        guard let frame = TabHitFrames.latest["Video"], frame.width > 8, frame.height > 8 else {
            let names = TabHitFrames.latest.keys.sorted().joined(separator: ", ")
            throw ToolError(message: "Video tab frame was missing (\(names))")
        }
        let local = NSPoint(x: frame.minX + 3, y: frame.midY)
        guard let hit = host.hitTest(local) else {
            throw ToolError(message: "pill edge was not a hit target")
        }
        let hitFrame = hit.convert(hit.bounds, to: host)
        if !frame.insetBy(dx: -2, dy: -2).intersects(hitFrame) && !frame.contains(local) {
            throw ToolError(message: "pill edge hit a view outside the Video tab")
        }
        let windowPoint = host.convert(local, to: nil)
        guard let down = mouseEvent(.leftMouseDown, at: windowPoint, window: window),
              let up = mouseEvent(.leftMouseUp, at: windowPoint, window: window) else {
            throw ToolError(message: "could not build a click")
        }
        window.sendEvent(down)
        window.sendEvent(up)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        guard model.category == .video else {
            throw ToolError(message: "a click at the pill edge did not select Video")
        }
    }

    private static func mouseEvent(_ type: NSEvent.EventType, at windowPoint: NSPoint, window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    }
}
