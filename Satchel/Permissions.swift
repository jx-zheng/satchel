import AppKit
import ApplicationServices
import AVFoundation
import Contacts
import CoreGraphics
import CoreServices
import CoreLocation
import Darwin
import Photos
import Speech
import SwiftUI
import SatchelCore

struct PermissionIssue: Equatable, Identifiable {
    let id = UUID()
    let tool: ToolID
    let kind: PermissionKind
    let reason: String
    let settingsURL: URL?

    static func == (lhs: PermissionIssue, rhs: PermissionIssue) -> Bool {
        lhs.tool == rhs.tool && lhs.kind == rhs.kind && lhs.reason == rhs.reason && lhs.settingsURL == rhs.settingsURL
    }
}

@MainActor
struct PermissionDriver {
    var status: (PermissionKind) -> PermissionStatus
    var request: (PermissionKind) async -> Bool
    var openSettings: (URL) -> Void

    static let live = PermissionDriver(
        status: { PermissionProbe.status(for: $0) },
        request: { await PermissionProbe.request($0) },
        openSettings: { url in NSWorkspace.shared.open(url) }
    )

    static func simulated(
        statuses: [PermissionKind: PermissionStatus],
        requestGrants: [PermissionKind: Bool] = [:],
        onRequest: ((PermissionKind) -> Void)? = nil,
        onOpenSettings: ((URL) -> Void)? = nil
    ) -> PermissionDriver {
        PermissionDriver(
            status: { kind in statuses[kind] ?? .authorized },
            request: { kind in
                onRequest?(kind)
                return requestGrants[kind] ?? false
            },
            openSettings: { url in
                onOpenSettings?(url)
            }
        )
    }
}

@MainActor
final class PermissionCoordinator: ObservableObject {
    @Published var issue: PermissionIssue?
    let tool: ToolID
    private let driver: PermissionDriver
    private var retryAction: (() -> Void)?

    init(tool: ToolID, driver: PermissionDriver = .live) {
        self.tool = tool
        self.driver = driver
    }

    func ensure(_ kind: PermissionKind, retry: (() -> Void)? = nil) async -> Bool {
        if let retry { self.retryAction = retry }
        let current = driver.status(kind)
        switch PermissionGate.action(for: kind, status: current) {
        case .proceed:
            issue = nil
            return true
        case let .request(requestedKind, _):
            let granted = await driver.request(requestedKind)
            switch PermissionGate.actionAfterRequest(kind: requestedKind, granted: granted) {
            case .proceed:
                issue = nil
                return true
            case let .showBanner(bannerKind):
                presentDenied(bannerKind, retry: retry)
                return false
            case .request:
                presentDenied(requestedKind, retry: retry)
                return false
            }
        case let .showBanner(bannerKind):
            presentDenied(bannerKind, retry: retry)
            return false
        }
    }

    func presentDenied(_ kind: PermissionKind, customReason: String? = nil, retry: (() -> Void)? = nil) {
        if let retry { self.retryAction = retry }
        let reason = customReason ?? ToolPermissionAudit.reason(for: tool, kind: kind)
        issue = PermissionIssue(
            tool: tool,
            kind: kind,
            reason: reason,
            settingsURL: URL(string: kind.settingsURLString)
        )
    }

    @discardableResult
    func handleError(_ error: Error, targetURL: URL? = nil, retry: (() -> Void)? = nil) -> Bool {
        guard let kind = PermissionClassifier.classify(error: error, targetURL: targetURL) else {
            return false
        }
        presentDenied(kind, retry: retry)
        return true
    }

    func clear() {
        issue = nil
    }

    func openSettings() {
        guard let url = issue?.settingsURL else { return }
        driver.openSettings(url)
    }

    func retry() {
        issue = nil
        retryAction?()
    }
}

enum PermissionClassifier {
    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoPermissionError || ns.code == NSFileWriteNoPermissionError) {
            return true
        }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES)) {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error, isPermissionError(underlying) {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("operation not permitted")
            || text.contains("permission")
            || text.contains("not authorized")
            || text.contains("user declined")
            || text.contains("tcc")
    }

    static func isScreenCaptureDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && ns.code == -3801 {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("declined") || text.contains("tcc") || text.contains("screen recording") || text.contains("not authorized")
    }

    static func isKeychainDenied(status: Int32, output: String) -> Bool {
        guard status != 0 else { return false }
        let lower = output.lowercased()
        return lower.contains("user interaction is not allowed")
            || lower.contains("denied")
            || lower.contains("canceled")
            || lower.contains("cancelled")
            || lower.contains("errsecauthfailed")
            || lower.contains("-128")
            || lower.contains("-25293")
    }

    static func folderKind(for url: URL) -> PermissionKind? {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == "\(home)/Downloads" || path.hasPrefix("\(home)/Downloads/") {
            return .downloadsFolder
        }
        if path == "\(home)/Desktop" || path.hasPrefix("\(home)/Desktop/") {
            return .desktopFolder
        }
        if path == "\(home)/Documents" || path.hasPrefix("\(home)/Documents/") {
            return .documentsFolder
        }
        if path.hasPrefix("/Volumes/") {
            return .removableVolumes
        }
        return nil
    }

    static func classify(error: Error, targetURL: URL? = nil) -> PermissionKind? {
        if isScreenCaptureDenied(error) {
            return .screenRecording
        }
        guard isPermissionError(error) else { return nil }
        if let targetURL {
            if let folder = folderKind(for: targetURL) {
                return folder
            }
            if targetURL.pathExtension.lowercased() == "app" || targetURL.path.hasPrefix("/Applications/") {
                return .appManagement
            }
        }
        return .fullDiskAccess
    }
}

@MainActor
enum PermissionProbe {
    private static let promptedPrefix = "satchel.permission.prompted."

    private static func hasPrompted(_ kind: PermissionKind) -> Bool {
        UserDefaults.standard.bool(forKey: promptedPrefix + kind.rawValue)
    }

    private static func markPrompted(_ kind: PermissionKind) {
        UserDefaults.standard.set(true, forKey: promptedPrefix + kind.rawValue)
    }

    static func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: return .notDetermined
            case .restricted: return .restricted
            case .denied: return .denied
            case .authorized: return .authorized
            @unknown default: return .denied
            }
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined: return .notDetermined
            case .restricted: return .restricted
            case .denied: return .denied
            case .authorized: return .authorized
            @unknown default: return .denied
            }
        case .speechRecognition:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .notDetermined: return .notDetermined
            case .restricted: return .restricted
            case .denied: return .denied
            case .authorized: return .authorized
            @unknown default: return .denied
            }
        case .screenRecording:
            if CGPreflightScreenCaptureAccess() {
                return .authorized
            }
            return hasPrompted(.screenRecording) ? .denied : .notDetermined
        case .accessibility:
            if AXIsProcessTrusted() {
                return .authorized
            }
            return hasPrompted(.accessibility) ? .denied : .notDetermined
        case .contacts:
            let auth = CNContactStore.authorizationStatus(for: .contacts)
            switch auth {
            case .notDetermined: return .notDetermined
            case .restricted: return .restricted
            case .denied: return .denied
            case .authorized: return .authorized
            @unknown default: return auth.rawValue == 4 ? .authorized : .denied
            }
        case .photos:
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .notDetermined: return .notDetermined
            case .restricted: return .restricted
            case .denied: return .denied
            case .authorized, .limited: return .authorized
            @unknown default: return .denied
            }
        case .location:
            return LocationPermissionRequester.currentStatus()
        case .automation:
            return automationStatus(askUserIfNeeded: false)
        case .fullDiskAccess:
            return fullDiskAccessStatus()
        case .downloadsFolder:
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            return folderStatus(for: url)
        case .desktopFolder:
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            return folderStatus(for: url)
        case .documentsFolder:
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
            return folderStatus(for: url)
        case .removableVolumes, .appManagement, .keychain:
            return .authorized
        }
    }

    static func request(_ kind: PermissionKind) async -> Bool {
        switch kind {
        case .microphone:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .camera:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .speechRecognition:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { auth in
                    continuation.resume(returning: auth == .authorized)
                }
            }
        case .screenRecording:
            markPrompted(.screenRecording)
            return CGRequestScreenCaptureAccess()
        case .accessibility:
            markPrompted(.accessibility)
            return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .contacts:
            return (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        case .photos:
            let result = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return result == .authorized || result == .limited
        case .location:
            let requester = LocationPermissionRequester()
            return await requester.request()
        case .automation:
            return automationStatus(askUserIfNeeded: true) == .authorized
        case .fullDiskAccess, .downloadsFolder, .desktopFolder, .documentsFolder,
             .removableVolumes, .appManagement, .keychain:
            return status(for: kind) == .authorized
        }
    }

    static func fullDiskAccessStatus() -> PermissionStatus {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Safari/Bookmarks.plist",
            "\(home)/Library/Messages/chat.db"
        ]
        var sawDenied = false
        for path in candidates {
            let fd = Darwin.open(path, O_RDONLY)
            if fd >= 0 {
                Darwin.close(fd)
                return .authorized
            }
            let code = errno
            if code == EPERM || code == EACCES {
                sawDenied = true
            }
        }
        return sawDenied ? .denied : .authorized
    }

    static func folderStatus(for url: URL) -> PermissionStatus {
        guard FileManager.default.fileExists(atPath: url.path) else { return .authorized }
        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            return .authorized
        } catch {
            return PermissionClassifier.isPermissionError(error) ? .denied : .authorized
        }
    }

    private static func automationStatus(askUserIfNeeded: Bool) -> PermissionStatus {
        let bundleID = "com.apple.finder"
        guard let data = bundleID.data(using: .utf8) else { return .notDetermined }
        var desc = AEAddressDesc()
        let created = data.withUnsafeBytes { bytes -> OSErr in
            AECreateDesc(DescType(typeApplicationBundleID), bytes.baseAddress, bytes.count, &desc)
        }
        guard created == 0 else { return .notDetermined }
        defer { AEDisposeDesc(&desc) }
        let result = AEDeterminePermissionToAttemptTarget(
            &desc,
            AEEventClass(kCoreEventClass),
            AEEventID(kAEOpenApplication),
            Boolean(askUserIfNeeded ? 1 : 0)
        )
        switch result {
        case 0:
            return .authorized
        case OSStatus(-1743): // errAEEventNotPermitted
            return .denied
        case OSStatus(-1744), OSStatus(-600): // errAEEventWouldRequireUserConsent / procNotFound
            return .notDetermined
        default:
            return .denied
        }
    }
}

@MainActor
private final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    static func currentStatus() -> PermissionStatus {
        guard CLLocationManager.locationServicesEnabled() else { return .denied }
        let status = CLLocationManager().authorizationStatus
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorizedAlways:
            return .authorized
        @unknown default:
            return status.rawValue == 4 ? .authorized : .denied
        }
    }

    func request() async -> Bool {
        let current = Self.currentStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }
        return await withCheckedContinuation { continuation in
            let manager = CLLocationManager()
            self.manager = manager
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.finish(granted: false)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let current = Self.currentStatus()
            guard current != .notDetermined else { return }
            self.finish(granted: current == .authorized)
        }
    }

    private func finish(granted: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.delegate = nil
        manager = nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: granted)
    }
}

struct PermissionBanner: View {
    let issue: PermissionIssue
    var onOpenSettings: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(issue.kind.displayName) permission required")
                        .font(.callout.weight(.semibold))
                    Text(issue.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !issue.kind.hasRequestAPI {
                        Text("Turn it on for Satchel in System Settings, then click Retry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Open System Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permission-banner-\(issue.kind.rawValue)")
    }
}

struct PermissionBannerSlot: View {
    @Environment(\.satchelSimulatedPermissionDenied) private var simulatedDenied
    @ObservedObject var coordinator: PermissionCoordinator

    var body: some View {
        if let issue = displayedIssue {
            PermissionBanner(
                issue: issue,
                onOpenSettings: { coordinator.openSettings() },
                onRetry: { coordinator.retry() }
            )
        }
    }

    private var displayedIssue: PermissionIssue? {
        if let issue = coordinator.issue {
            return issue
        }
        if let simulatedDenied {
            return PermissionIssue(
                tool: coordinator.tool,
                kind: simulatedDenied,
                reason: ToolPermissionAudit.reason(for: coordinator.tool, kind: simulatedDenied),
                settingsURL: URL(string: simulatedDenied.settingsURLString)
            )
        }
        return nil
    }
}

@MainActor
enum PermissionGateProbe {
    static func verifyAll() async throws {
        let tools = ToolPermissionAudit.permissionedTools
        guard !tools.isEmpty else {
            throw ToolError(message: "permissionedTools was empty")
        }

        for tool in tools {
            let requirements = ToolPermissionAudit.requirements(for: tool)
            guard !requirements.isEmpty else {
                throw ToolError(message: "\(tool.rawValue) had empty requirements")
            }

            for req in requirements {
                // 1. notDetermined -> request path (if hasRequestAPI) or banner (if no request API)
                var requestedKinds: [PermissionKind] = []
                var openedURLs: [URL] = []
                let denyDriver = PermissionDriver.simulated(
                    statuses: [req.kind: .notDetermined],
                    requestGrants: [req.kind: false],
                    onRequest: { requestedKinds.append($0) },
                    onOpenSettings: { openedURLs.append($0) }
                )
                let denyCoord = PermissionCoordinator(tool: tool, driver: denyDriver)
                let allowedOnDeny = await denyCoord.ensure(req.kind)
                if allowedOnDeny {
                    throw ToolError(message: "\(tool.rawValue) unexpectedly proceeded when \(req.kind.rawValue) was notDetermined and declined")
                }
                if req.kind.hasRequestAPI {
                    guard requestedKinds == [req.kind] else {
                        throw ToolError(message: "\(tool.rawValue) did not call request API for \(req.kind.rawValue)")
                    }
                } else {
                    guard requestedKinds.isEmpty else {
                        throw ToolError(message: "\(tool.rawValue) unexpectedly called request API for \(req.kind.rawValue)")
                    }
                }
                guard let issue = denyCoord.issue,
                      issue.kind == req.kind,
                      !issue.reason.isEmpty,
                      let expectedURL = URL(string: req.kind.settingsURLString),
                      issue.settingsURL == expectedURL else {
                    throw ToolError(message: "\(tool.rawValue) did not populate banner issue for \(req.kind.rawValue)")
                }
                denyCoord.openSettings()
                guard openedURLs == [expectedURL] else {
                    throw ToolError(message: "\(tool.rawValue) did not deep-link to \(req.kind.settingsURLString)")
                }

                // 2. notDetermined with grant (auto-proceeds for requestable APIs)
                if req.kind.hasRequestAPI {
                    var grantRequests: [PermissionKind] = []
                    let grantDriver = PermissionDriver.simulated(
                        statuses: [req.kind: .notDetermined],
                        requestGrants: [req.kind: true],
                        onRequest: { grantRequests.append($0) }
                    )
                    let grantCoord = PermissionCoordinator(tool: tool, driver: grantDriver)
                    let allowedOnGrant = await grantCoord.ensure(req.kind)
                    guard allowedOnGrant, grantCoord.issue == nil, grantRequests == [req.kind] else {
                        throw ToolError(message: "\(tool.rawValue) did not proceed after grant for \(req.kind.rawValue)")
                    }
                }

                // 3. denied and restricted -> banner path + retry flips to proceed when authorized
                for blockedStatus in [PermissionStatus.denied, PermissionStatus.restricted] {
                    var currentStatus = blockedStatus
                    var blockedRequests: [PermissionKind] = []
                    let dynamicDriver = PermissionDriver(
                        status: { _ in currentStatus },
                        request: { kind in
                            blockedRequests.append(kind)
                            return false
                        },
                        openSettings: { _ in }
                    )
                    let coord = PermissionCoordinator(tool: tool, driver: dynamicDriver)
                    var retried = false
                    let allowed = await coord.ensure(req.kind, retry: { retried = true })
                    guard !allowed, blockedRequests.isEmpty, coord.issue?.kind == req.kind else {
                        throw ToolError(message: "\(tool.rawValue) failed \(blockedStatus.rawValue) check for \(req.kind.rawValue)")
                    }
                    currentStatus = .authorized
                    coord.retry()
                    guard retried, coord.issue == nil else {
                        throw ToolError(message: "\(tool.rawValue) retry hook failed for \(req.kind.rawValue)")
                    }
                    let allowedAfterRetry = await coord.ensure(req.kind)
                    guard allowedAfterRetry, coord.issue == nil else {
                        throw ToolError(message: "\(tool.rawValue) did not succeed after becoming authorized for \(req.kind.rawValue)")
                    }
                }
            }
        }

        // 4. Verify Info.plist contains every required NS*UsageDescription key
        let requiredKeys = [
            "NSMicrophoneUsageDescription",
            "NSSpeechRecognitionUsageDescription",
            "NSCameraUsageDescription",
            "NSScreenCaptureUsageDescription",
            "NSLocationUsageDescription",
            "NSLocationWhenInUseUsageDescription",
            "NSDesktopFolderUsageDescription",
            "NSDocumentsFolderUsageDescription",
            "NSDownloadsFolderUsageDescription",
            "NSRemovableVolumesUsageDescription",
            "NSAppleEventsUsageDescription",
            "NSContactsUsageDescription",
            "NSPhotoLibraryUsageDescription"
        ]
        for key in requiredKeys {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ToolError(message: "Missing Info.plist usage description key: \(key)")
            }
        }

        // 5. Verify banner renders cleanly in NSHostingView without layout failure
        let sampleIssue = PermissionIssue(
            tool: .storageExplorer,
            kind: .fullDiskAccess,
            reason: ToolPermissionAudit.reason(for: .storageExplorer, kind: .fullDiskAccess),
            settingsURL: URL(string: PermissionKind.fullDiskAccess.settingsURLString)
        )
        let banner = PermissionBanner(issue: sampleIssue, onOpenSettings: {}, onRetry: {})
            .frame(width: 640)
        let host = NSHostingView(rootView: banner)
        host.layoutSubtreeIfNeeded()
        guard host.fittingSize.height > 40 else {
            throw ToolError(message: "PermissionBanner rendered with invalid height \(host.fittingSize.height)")
        }
    }
}
