import AppKit
import CoreImage
import CoreWLAN
import IOKit
import IOKit.pwr_mgt
import SwiftUI
import SatchelCore

struct MacToolScreen: View {
    let id: ToolID
    var body: some View {
        switch id {
        case .networkSpeed: NetworkTool()
        case .clipboardHistory: ClipboardTool()
        case .storageExplorer: StorageTool()
        case .wifiPassword: WiFiTool()
        case .diskSpeed: DiskSpeedTool()
        case .batteryHealth: BatteryTool()
        case .keepAwake: KeepAwakeTool()
        case .uninstallApp: UninstallTool()
        case .presentationMode: PresentationTool()
        case .cleanKeyboard: CleanKeyboardTool()
        case .deadPixel: DeadPixelTool()
        case .ejectDisks: EjectTool()
        case .loginItems: LoginTool()
        case .fixDamaged: QuarantineTool()
        case .resetPermissions: PermissionTool()
        case .hiddenSettings: HiddenSettingsTool()
        case .mouseFixes: MouseTool()
        default:
            if let tool = ToolRegistry.byID[id] { ComingSoonView(tool: tool) }
        }
    }
}

private struct NetworkTool: View {
    @State private var message = "Uses networkQuality, the test built into macOS."
    @State private var running = false
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.networkSpeed)) {
            Text(message).textSelection(.enabled)
            PrimaryButton(title: running ? "Testing…" : "Run test", enabled: !running) {
                running = true
                let start = Date()
                Task.detached {
                    let result = Commands.run("/usr/bin/networkQuality", [])
                    await MainActor.run {
                        message = result.output.isEmpty ? "The test did not return any text." : result.output
                        running = false
                        SatchelLog.toolRun(id: ToolID.networkSpeed.rawValue, inputs: 1, outcome: result.status == 0 ? "ok" : "failed", seconds: RunLog.stamp(start))
                    }
                }
            }
        }
    }
}

private struct DiskSpeedTool: View {
    @State private var message = "Writes and reads a temporary 64 MB file, then deletes it."
    @State private var running = false
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.diskSpeed)) {
            Text(message)
            PrimaryButton(title: running ? "Testing…" : "Test disk", enabled: !running) {
                running = true
                let start = Date()
                Task.detached {
                    let text = DiskBench.measure()
                    await MainActor.run {
                        message = text
                        running = false
                        SatchelLog.toolRun(id: ToolID.diskSpeed.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
                    }
                }
            }
        }
    }

}

enum DiskBench {
    static func measure() -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("satchel-disk-\(UUID().uuidString)")
        let chunk = 1024 * 1024
        let count = 64
        var bytes = [UInt8](repeating: 0, count: chunk)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index &* 31 &+ 17) }
        let data = Data(bytes)
        do {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            let writeStart = Date()
            for _ in 0..<count { try handle.write(contentsOf: data) }
            try handle.synchronize()
            try handle.close()
            let writeSeconds = Date().timeIntervalSince(writeStart)
            let readStart = Date()
            let read = try Data(contentsOf: url)
            _ = read.count
            let readSeconds = Date().timeIntervalSince(readStart)
            try? FileManager.default.removeItem(at: url)
            let megabytes = Double(count)
            return String(format: "Write %.0f MB/s\nRead %.0f MB/s", megabytes / max(writeSeconds, 0.001), megabytes / max(readSeconds, 0.001))
        } catch {
            try? FileManager.default.removeItem(at: url)
            return error.localizedDescription
        }
    }
}

private struct BatteryTool: View {
    @State private var lines: [String] = ["Press refresh to read the battery."]
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.batteryHealth)) {
            ForEach(lines, id: \.self) { Text($0).frame(maxWidth: .infinity, alignment: .leading) }
            PrimaryButton(title: "Refresh", enabled: true) {
                let start = Date()
                lines = BatteryReader.read()
                SatchelLog.toolRun(id: ToolID.batteryHealth.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
            }
        }
    }
}

enum BatteryReader {
    static func read() -> [String] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return ["No internal battery was found. Desktop Macs often have none."] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let raw = properties?.takeRetainedValue() as? [String: Any] else {
            return ["The battery is present, but its details could not be read."]
        }
        func int(_ key: String) -> Int? {
            if let value = raw[key] as? Int { return value }
            if let number = raw[key] as? NSNumber { return number.intValue }
            return nil
        }
        let current = int("AppleRawCurrentCapacity") ?? int("CurrentCapacity")
        let maxCap = int("AppleRawMaxCapacity") ?? int("MaxCapacity") ?? int("NominalChargeCapacity")
        let design = int("DesignCapacity") ?? int("AppleRawDesignCapacity")
        let cycles = int("CycleCount")
        let tempRaw = int("Temperature")
        let voltage = int("Voltage")
        let amperage = int("Amperage") ?? int("InstantAmperage")
        var lines: [String] = []
        if let current, let maxCap {
            lines.append("Charge: \(current) / \(maxCap) mAh")
        }
        if let maxCap, let design, design > 0 {
            lines.append(String(format: "Maximum capacity: %.0f%%", Double(maxCap) / Double(design) * 100))
        }
        if let cycles { lines.append("Cycle count: \(cycles)") }
        if let tempRaw {
            let celsius = Double(tempRaw) / 10.0 - 273.15
            let shown = (celsius > -20 && celsius < 100) ? celsius : Double(tempRaw) / 100.0 - 273.15
            lines.append(String(format: "Temperature: %.1f °C", shown))
        }
        if let voltage, let amperage {
            let watts = abs(Double(voltage) * Double(amperage)) / 1_000_000
            lines.append(String(format: "Power: %.1f W", watts))
        }
        let charging = (raw["IsCharging"] as? Bool) ?? ((raw["IsCharging"] as? NSNumber)?.boolValue ?? false)
        let external = (raw["ExternalConnected"] as? Bool) ?? ((raw["ExternalConnected"] as? NSNumber)?.boolValue ?? false)
        lines.append(external ? (charging ? "Charger connected, charging" : "Charger connected") : "On battery")
        return lines.isEmpty ? ["Battery keys were present, but none of the usual values were readable."] : lines
    }
}

final class AwakeKeeper: ObservableObject {
    @Published var active = false
    @Published var remaining = ""
    private var assertions: [IOPMAssertionID] = []
    private var timer: Timer?
    private var end: Date?

    func start(minutes: Int?) {
        stop()
        for name in [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep] {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(name as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Satchel is keeping this Mac awake" as CFString, &id)
            if result == kIOReturnSuccess { assertions.append(id) }
        }
        active = !assertions.isEmpty
        if let minutes {
            end = Date().addingTimeInterval(Double(minutes) * 60)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } else {
            remaining = "Until you stop it"
        }
        SatchelLog.toolRun(id: ToolID.keepAwake.rawValue, inputs: 1, outcome: active ? "ok" : "failed", seconds: "0s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for id in assertions { IOPMAssertionRelease(id) }
        assertions = []
        active = false
        remaining = ""
        end = nil
    }

    private func tick() {
        guard let end else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            stop()
            return
        }
        remaining = String(format: "%d:%02d left", Int(left) / 60, Int(left) % 60)
    }
}

private struct KeepAwakeTool: View {
    @StateObject private var keeper = AwakeKeeper()
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.keepAwake)) {
            Text(keeper.active ? keeper.remaining : "Stops the display and the Mac from idle sleep.")
            HStack {
                PrimaryButton(title: "15 min", enabled: !keeper.active) { keeper.start(minutes: 15) }
                PrimaryButton(title: "1 hour", enabled: !keeper.active) { keeper.start(minutes: 60) }
                PrimaryButton(title: "Until I stop", enabled: !keeper.active) { keeper.start(minutes: nil) }
            }
            if keeper.active { PrimaryButton(title: "Stop", enabled: true) { keeper.stop() } }
        }
        .onDisappear { keeper.stop() }
    }
}

private struct ClipboardTool: View {
    @State private var items: [String] = []
    @State private var timer: Timer?
    @State private var change = NSPasteboard.general.changeCount
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.clipboardHistory)) {
            Text("Text you copy while this tool is open is kept here, on this Mac. Concealed clipboard items are skipped.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Button(item) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item, forType: .string)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
            }
            Button("Clear") { items = [] }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in poll() }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != change else { return }
        change = board.changeCount
        let types = board.types ?? []
        if types.contains(where: { $0.rawValue.localizedCaseInsensitiveContains("concealed") }) { return }
        guard let string = board.string(forType: .string), !string.isEmpty else { return }
        let clipped = String(string.prefix(10_000))
        items.removeAll { $0 == clipped }
        items.insert(clipped, at: 0)
        if items.count > 40 { items.removeLast(items.count - 40) }
    }
}

private struct StorageTool: View {
    @State private var rows: [(String, URL, Int64)] = []
    @State private var message = ""
    @State private var pending: URL?
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.storageExplorer)) {
            PrimaryButton(title: "Scan common space hogs", enabled: true) { scan() }
            ForEach(rows, id: \.1.path) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.0).font(.system(size: 13, weight: .semibold))
                        Text(row.1.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(ByteFormat.string(bytes: row.2))
                    Button("Trash") { pending = row.1 }
                }
            }
            Text("Trash moves the item aside. It is not erased until you empty the Trash.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
        }
        .confirmationDialog("Move this to the Trash?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let pending {
                    do {
                        try FileManager.default.trashItem(at: pending, resultingItemURL: nil)
                        message = "Moved to the Trash."
                        rows.removeAll { $0.1 == pending }
                    } catch { message = error.localizedDescription }
                }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    private func scan() {
        let start = Date()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths: [(String, String)] = [
            ("Xcode DerivedData", "Library/Developer/Xcode/DerivedData"),
            ("iOS Simulators", "Library/Developer/CoreSimulator"),
            ("Xcode archives", "Library/Developer/Xcode/Archives"),
            ("Device support", "Library/Developer/Xcode/iOS DeviceSupport"),
            ("Caches", "Library/Caches"),
            ("Logs", "Library/Logs"),
            ("iPhone backups", "Library/Application Support/MobileSync/Backup"),
            ("Downloads", "Downloads")
        ]
        rows = paths.compactMap { label, relative in
            let url = home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return (label, url, FileSize.directory(url))
        }.sorted { $0.2 > $1.2 }
        SatchelLog.toolRun(id: ToolID.storageExplorer.rawValue, inputs: rows.count, outcome: "ok", seconds: RunLog.stamp(start))
    }
}

private struct WiFiTool: View {
    @State private var message = "Looks up the current network, then asks the keychain for its saved password."
    @State private var qr: NSImage?
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.wifiPassword)) {
            Text(message).textSelection(.enabled)
            if let qr { Image(nsImage: qr).interpolation(.none).frame(width: 160, height: 160) }
            PrimaryButton(title: "Show password", enabled: true) { load() }
        }
    }

    private func load() {
        let start = Date()
        let ssid = CWWiFiClient.shared().interface()?.ssid()
            ?? parseSSID(Commands.run("/usr/sbin/networksetup", ["-getairportnetwork", "en0"]).output)
        guard let ssid, !ssid.isEmpty else {
            message = "Could not read the Wi-Fi name. Location permission lets macOS share it."
            return
        }
        let result = Commands.run("/usr/bin/security", ["find-generic-password", "-D", "AirPort network password", "-a", ssid, "-w"])
        if result.status != 0 {
            message = "Network: \(ssid)\nThe password was not found, or the keychain prompt was cancelled.\n\(result.output)"
            SatchelLog.toolRun(id: ToolID.wifiPassword.rawValue, inputs: 1, outcome: "failed", seconds: RunLog.stamp(start))
            return
        }
        let password = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        message = "Network: \(ssid)\nPassword: \(password)"
        qr = qrImage("WIFI:T:WPA;S:\(ssid);P:\(password);;")
        SatchelLog.toolRun(id: ToolID.wifiPassword.rawValue, inputs: 1, outcome: "ok", seconds: RunLog.stamp(start))
    }

    private func parseSSID(_ text: String) -> String? {
        guard let range = text.range(of: ":") else { return nil }
        let name = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func qrImage(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let context = CIContext()
        let extent = output.extent.integral
        guard let cg = context.createCGImage(output, from: extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: extent.width, height: extent.height))
    }
}

private struct UninstallTool: View {
    @State private var app: URL?
    @State private var extras: [URL] = []
    @State private var message = ""
    @State private var confirm = false
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.uninstallApp)) {
            PrimaryButton(title: "Choose an app", enabled: true) { choose() }
            if let app { Text(app.path).font(.system(size: 12)) }
            ForEach(extras, id: \.path) { Text($0.path).font(.system(size: 11)).lineLimit(1) }
            PrimaryButton(title: "Move to Trash", enabled: app != nil) { confirm = true }
            Text(message).foregroundStyle(.secondary)
        }
        .confirmationDialog("Move the app and the files listed above to the Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { trash() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaTypes.apps
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.lastPathComponent == "Satchel.app" {
            message = "Satchel will not uninstall itself."
            return
        }
        if url.path.hasPrefix("/System") {
            message = "System apps are left alone."
            return
        }
        app = url
        let bundle = Bundle(url: url)?.bundleIdentifier
        extras = related(bundle: bundle, name: url.deletingPathExtension().lastPathComponent)
    }

    private func related(bundle: String?, name: String) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Library/Caches", "Library/Preferences", "Library/Application Support", "Library/Containers", "Library/Logs", "Library/Saved Application State"]
        var found: [URL] = []
        for root in roots {
            let folder = home.appendingPathComponent(root)
            guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                let itemName = item.lastPathComponent
                if let bundle, itemName.contains(bundle) { found.append(item) }
                else if itemName == name || itemName == "\(name).plist" { found.append(item) }
            }
        }
        return found
    }

    private func trash() {
        guard let app else { return }
        var count = 0
        for url in [app] + extras {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                count += 1
            } catch { message = error.localizedDescription }
        }
        message = "Moved \(count) items to the Trash."
        SatchelLog.toolRun(id: ToolID.uninstallApp.rawValue, inputs: count, outcome: "ok", seconds: "0s")
        self.app = nil
        extras = []
    }
}

private struct PresentationTool: View {
    @State private var on = false
    @State private var message = "Hides desktop icons, hides the Dock, and keeps the Mac awake until you turn it off."
    @StateObject private var keeper = AwakeKeeper()
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.presentationMode)) {
            Toggle("Presentation mode", isOn: $on)
                .onChange(of: on) { _, value in apply(value) }
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .onDisappear { if on { apply(false) } }
    }

    private func apply(_ enabled: Bool) {
        _ = Commands.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", enabled ? "false" : "true"])
        _ = Commands.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false"])
        _ = Commands.run("/usr/bin/killall", ["Finder"])
        _ = Commands.run("/usr/bin/killall", ["Dock"])
        if enabled { keeper.start(minutes: nil) } else { keeper.stop() }
        message = enabled ? "Desktop icons and the Dock are hidden. Turn this off to put them back." : "Restored."
        SatchelLog.toolRun(id: ToolID.presentationMode.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
    }
}

private struct CleanKeyboardTool: View {
    @State private var message = "The overlay swallows keys in Satchel. Hold Escape to leave, or use the button."
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.cleanKeyboard)) {
            Text(message)
            PrimaryButton(title: "Start cleaning", enabled: true) {
                KeyboardCover.shared.show()
                SatchelLog.toolRun(id: ToolID.cleanKeyboard.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
            }
        }
    }
}

final class KeyboardCover {
    static let shared = KeyboardCover()
    private var panel: NSPanel?
    private var monitor: Any?
    private var escSince: Date?

    func show() {
        guard let screen = NSScreen.main else { return }
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.92)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: CleanOverlay { self.hide() })
        panel.contentView = host
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            if event.keyCode == 53 {
                if event.type == .keyDown {
                    if self.escSince == nil { self.escSince = Date() }
                    if let since = self.escSince, Date().timeIntervalSince(since) > 1.1 { self.hide() }
                } else {
                    self.escSince = nil
                }
            }
            return nil
        }
    }

    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct CleanOverlay: View {
    var close: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("Keyboard paused")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
            Text("Wipe the keys. Hold Escape, or click Done.")
                .foregroundStyle(.white.opacity(0.8))
            Button("Done", action: close)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DeadPixelTool: View {
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.deadPixel)) {
            Text("Fills the screen with solid colors. Click to move through them, or press Escape to leave.")
            PrimaryButton(title: "Start test", enabled: true) {
                DeadPixelCover.shared.show()
                SatchelLog.toolRun(id: ToolID.deadPixel.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
            }
        }
    }
}

final class DeadPixelCover: NSObject {
    static let shared = DeadPixelCover()
    private var panel: NSPanel?
    private var monitor: Any?
    private let colors: [NSColor] = [.black, .white, .red, .green, .blue, .gray]
    private var index = 0

    func show() {
        guard let screen = NSScreen.main else { return }
        index = 0
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = colors[0]
        panel.makeKeyAndOrderFront(nil)
        let click = NSClickGestureRecognizer(target: self, action: #selector(cycle))
        panel.contentView?.addGestureRecognizer(click)
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { self.hide(); return nil }
            self.cycle()
            return nil
        }
    }

    @objc func cycle() {
        index = (index + 1) % colors.count
        panel?.backgroundColor = colors[index]
    }

    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct EjectTool: View {
    @State private var names: [String] = []
    @State private var urls: [URL] = []
    @State private var message = ""
    @State private var confirm = false
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.ejectDisks)) {
            PrimaryButton(title: "List removable disks", enabled: true) { refresh() }
            ForEach(names, id: \.self) { Text($0) }
            PrimaryButton(title: "Eject all", enabled: !urls.isEmpty) { confirm = true }
            Text(message).foregroundStyle(.secondary)
        }
        .confirmationDialog("Eject \(names.joined(separator: ", "))?", isPresented: $confirm) {
            Button("Eject", role: .destructive) { eject() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func refresh() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        urls = volumes.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.volumeIsInternal == false && (values?.volumeIsEjectable == true || values?.volumeIsRemovable == true)
        }
        names = urls.map { (try? $0.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? $0.lastPathComponent }
        message = names.isEmpty ? "No removable disks are mounted." : ""
    }

    private func eject() {
        var ejected = 0
        for url in urls {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                ejected += 1
            } catch { message = error.localizedDescription }
        }
        message = "Ejected \(ejected)."
        SatchelLog.toolRun(id: ToolID.ejectDisks.rawValue, inputs: ejected, outcome: "ok", seconds: "0s")
        refresh()
    }
}

private struct LoginTool: View {
    @State private var files: [URL] = []
    @State private var pending: URL?
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.loginItems)) {
            PrimaryButton(title: "Refresh", enabled: true) { load() }
            ForEach(files, id: \.path) { url in
                HStack {
                    Text(url.deletingPathExtension().lastPathComponent).lineLimit(1)
                    Spacer()
                    Button("Trash") { pending = url }
                }
            }
            Text("These are the property lists in your user LaunchAgents folder. Trashing one stops it from loading at login.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .onAppear { load() }
        .confirmationDialog("Move this launch agent to the Trash?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let pending {
                    try? FileManager.default.trashItem(at: pending, resultingItemURL: nil)
                    SatchelLog.toolRun(id: ToolID.loginItems.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
                }
                pending = nil
                load()
            }
            Button("Cancel", role: .cancel) { pending = nil }
        }
    }

    private func load() {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "plist" } ?? []
    }
}

private struct QuarantineTool: View {
    @State private var app: URL?
    @State private var info = ""
    @State private var confirm = false
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.fixDamaged)) {
            PrimaryButton(title: "Choose an app", enabled: true) { choose() }
            Text(info).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            PrimaryButton(title: "Clear quarantine", enabled: app != nil) { confirm = true }
        }
        .confirmationDialog("Remove the quarantine flag so macOS will try to open this app?", isPresented: $confirm) {
            Button("Clear quarantine", role: .destructive) { clear() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaTypes.apps
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app = url
        info = Commands.run("/usr/bin/codesign", ["-dv", "--verbose=4", url.path]).output
        if info.isEmpty { info = "codesign did not print a signature summary." }
    }

    private func clear() {
        guard let app else { return }
        let result = Commands.run("/usr/bin/xattr", ["-d", "com.apple.quarantine", app.path])
        info = result.status == 0 ? "Quarantine flag removed." : result.output
        SatchelLog.toolRun(id: ToolID.fixDamaged.rawValue, inputs: 1, outcome: result.status == 0 ? "ok" : "failed", seconds: "0s")
    }
}

private struct PermissionTool: View {
    @State private var service = "Microphone"
    @State private var bundle = ""
    @State private var message = ""
    @State private var confirm = false
    private let services = ["Camera", "Microphone", "ScreenCapture", "SpeechRecognition", "AppleEvents", "Photos"]
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.resetPermissions)) {
            Picker("Permission", selection: $service) {
                ForEach(services, id: \.self) { Text($0).tag($0) }
            }
            TextField("Bundle id, optional", text: $bundle)
            PrimaryButton(title: "Reset", enabled: true) { confirm = true }
            Text(message).font(.system(size: 12)).textSelection(.enabled)
        }
        .confirmationDialog("Reset \(service) permission\(bundle.isEmpty ? "" : " for \(bundle)")?", isPresented: $confirm) {
            Button("Reset", role: .destructive) { reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func reset() {
        var args = ["reset", service]
        if !bundle.trimmingCharacters(in: .whitespaces).isEmpty { args.append(bundle) }
        let result = Commands.run("/usr/bin/tccutil", args)
        message = result.output.isEmpty ? "tccutil exited \(result.status)." : result.output
        SatchelLog.toolRun(id: ToolID.resetPermissions.rawValue, inputs: 1, outcome: result.status == 0 ? "ok" : "failed", seconds: "0s")
    }
}

private struct HiddenSettingsTool: View {
    @State private var hidden = false
    @State private var pathBar = false
    @State private var dockDelay = false
    @State private var message = "Read the current values, change the switches, then apply. Finder or the Dock restarts so the change shows up."
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.hiddenSettings)) {
            Toggle("Show hidden files in Finder", isOn: $hidden)
            Toggle("Show the path bar", isOn: $pathBar)
            Toggle("Remove the Dock show delay", isOn: $dockDelay)
            PrimaryButton(title: "Apply", enabled: true) { apply() }
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .onAppear { read() }
    }

    private func apply() {
        write("com.apple.finder", "AppleShowAllFiles", hidden)
        write("com.apple.finder", "ShowPathbar", pathBar)
        if dockDelay {
            _ = Commands.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "0"])
        } else {
            _ = Commands.run("/usr/bin/defaults", ["delete", "com.apple.dock", "autohide-delay"])
        }
        _ = Commands.run("/usr/bin/killall", ["Finder"])
        _ = Commands.run("/usr/bin/killall", ["Dock"])
        message = "Applied. Finder and the Dock will reopen."
        SatchelLog.toolRun(id: ToolID.hiddenSettings.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
    }

    private func read() {
        hidden = Commands.run("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"]).output.contains("1")
        pathBar = Commands.run("/usr/bin/defaults", ["read", "com.apple.finder", "ShowPathbar"]).output.contains("1")
    }

    private func write(_ domain: String, _ key: String, _ value: Bool) {
        _ = Commands.run("/usr/bin/defaults", ["write", domain, key, "-bool", value ? "true" : "false"])
        SatchelLog.toolRun(id: ToolID.hiddenSettings.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
    }
}

private struct MouseTool: View {
    @State private var natural = true
    @State private var speed = 1.5
    @State private var message = "These write the same settings System Settings uses, and can be put back."
    var body: some View {
        ToolPage(tool: ToolRegistry.definition(.mouseFixes)) {
            Toggle("Natural scrolling", isOn: $natural).onChange(of: natural) { _, value in
                _ = Commands.run("/usr/bin/defaults", ["write", "-g", "com.apple.swipescrolldirection", "-bool", value ? "true" : "false"])
                message = "Scroll direction updated. Some apps notice it after they relaunch."
                SatchelLog.toolRun(id: ToolID.mouseFixes.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
            }
            HStack {
                Text("Pointer speed")
                Slider(value: $speed, in: 0.5...3)
            }
            PrimaryButton(title: "Apply pointer speed", enabled: true) {
                _ = Commands.run("/usr/bin/defaults", ["write", "-g", "com.apple.mouse.scaling", "-float", String(format: "%.2f", speed)])
                message = "Pointer speed written."
                SatchelLog.toolRun(id: ToolID.mouseFixes.rawValue, inputs: 1, outcome: "ok", seconds: "0s")
            }
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
