import AppKit
import SwiftUI
import SatchelCore

enum TabHitTest {
    @MainActor
    static func clickEdgeSelectsVideo() throws {
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
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()
        defer { window.close() }

        guard let button = find(identifier: "tab-Video", in: host) else {
            throw ToolError(message: "Video tab was not in the view tree")
        }
        let windowFrame = button.convert(button.bounds, to: nil)
        guard windowFrame.width > 8, windowFrame.height > 8 else {
            throw ToolError(message: "Video tab frame was empty")
        }
        let windowPoint = NSPoint(x: windowFrame.minX + 3, y: windowFrame.midY)
        guard let content = window.contentView else { throw ToolError(message: "window had no content") }
        let local = content.convert(windowPoint, from: nil)
        guard let hit = content.hitTest(local) else {
            throw ToolError(message: "pill edge was not a hit target")
        }
        let hitID = hit.accessibilityIdentifier()
        let ancestor = nearestIdentifier(from: hit)
        if hitID != "tab-Video" && ancestor != "tab-Video" && !owns(hit, identifier: "tab-Video") {
            let label = hitID.isEmpty ? String(describing: type(of: hit)) : hitID
            throw ToolError(message: "pill edge hit \(label)")
        }
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

    private static func find(identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let found = find(identifier: identifier, in: subview) { return found }
        }
        return nil
    }

    private static func nearestIdentifier(from view: NSView) -> String {
        var current: NSView? = view
        while let node = current {
            let identifier = node.accessibilityIdentifier()
            if !identifier.isEmpty { return identifier }
            current = node.superview
        }
        return ""
    }

    private static func owns(_ view: NSView, identifier: String) -> Bool {
        var current: NSView? = view
        while let node = current {
            if node.accessibilityIdentifier() == identifier { return true }
            current = node.superview
        }
        return false
    }
}
