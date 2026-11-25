import Foundation

public enum PermissionKind: String, CaseIterable, Codable, Sendable, Hashable {
    case microphone
    case speechRecognition
    case screenRecording
    case accessibility
    case camera
    case contacts
    case photos
    case fullDiskAccess
    case automation
    case location
    case downloadsFolder
    case desktopFolder
    case documentsFolder
    case removableVolumes
    case appManagement
    case keychain

    public var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .speechRecognition: return "Speech Recognition"
        case .screenRecording: return "Screen Recording"
        case .accessibility: return "Accessibility"
        case .camera: return "Camera"
        case .contacts: return "Contacts"
        case .photos: return "Photos"
        case .fullDiskAccess: return "Full Disk Access"
        case .automation: return "Automation"
        case .location: return "Location Services"
        case .downloadsFolder: return "Downloads Folder"
        case .desktopFolder: return "Desktop Folder"
        case .documentsFolder: return "Documents Folder"
        case .removableVolumes: return "Removable Volumes"
        case .appManagement: return "App Management"
        case .keychain: return "Keychain Access"
        }
    }

    public var settingsURLString: String {
        switch self {
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .camera:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .contacts:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        case .photos:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
        case .fullDiskAccess:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .automation:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .location:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case .downloadsFolder, .desktopFolder, .documentsFolder, .removableVolumes:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case .appManagement:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
        case .keychain:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy"
        }
    }

    /// Whether macOS provides a system request API that can be triggered from code.
    /// Full Disk Access, Files & Folders, App Management, and Keychain prompts have no
    /// general pre-flight request API and instead require System Settings or access prompt recovery.
    public var hasRequestAPI: Bool {
        switch self {
        case .microphone, .speechRecognition, .screenRecording, .accessibility,
             .camera, .contacts, .photos, .automation, .location:
            return true
        case .fullDiskAccess, .downloadsFolder, .desktopFolder, .documentsFolder,
             .removableVolumes, .appManagement, .keychain:
            return false
        }
    }

    /// Whether the system request API invokes a completion callback with the user's decision
    /// so the tool can retry automatically upon grant.
    public var supportsCallbackAutoRetry: Bool {
        switch self {
        case .microphone, .speechRecognition, .camera, .contacts, .photos, .location:
            return true
        case .screenRecording, .accessibility, .automation,
             .fullDiskAccess, .downloadsFolder, .desktopFolder, .documentsFolder,
             .removableVolumes, .appManagement, .keychain:
            return false
        }
    }
}

public enum PermissionStatus: String, CaseIterable, Codable, Sendable, Hashable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

public enum PermissionAction: Equatable, Sendable {
    case proceed
    case request(PermissionKind, autoRetryOnGrant: Bool)
    case showBanner(PermissionKind)
}

public struct ToolPermissionRequirement: Equatable, Sendable, Hashable {
    public let kind: PermissionKind
    public let reason: String
    public let requiredBeforeRun: Bool

    public init(kind: PermissionKind, reason: String, requiredBeforeRun: Bool = true) {
        self.kind = kind
        self.reason = reason
        self.requiredBeforeRun = requiredBeforeRun
    }
}

public enum PermissionGate {
    public static func action(for kind: PermissionKind, status: PermissionStatus) -> PermissionAction {
        switch status {
        case .authorized:
            return .proceed
        case .notDetermined:
            if kind.hasRequestAPI {
                return .request(kind, autoRetryOnGrant: kind.supportsCallbackAutoRetry)
            }
            return .showBanner(kind)
        case .denied, .restricted:
            return .showBanner(kind)
        }
    }

    public static func actionAfterRequest(kind: PermissionKind, granted: Bool) -> PermissionAction {
        granted ? .proceed : .showBanner(kind)
    }
}

public enum ToolPermissionAudit {
    public static func requirements(for id: ToolID) -> [ToolPermissionRequirement] {
        switch id {
        case .recordScreen:
            return [
                ToolPermissionRequirement(
                    kind: .screenRecording,
                    reason: "Satchel needs Screen Recording permission to capture your display as a movie.",
                    requiredBeforeRun: true
                )
            ]
        case .screenshot:
            return [
                ToolPermissionRequirement(
                    kind: .screenRecording,
                    reason: "Satchel needs Screen Recording permission to capture your display.",
                    requiredBeforeRun: true
                ),
                ToolPermissionRequirement(
                    kind: .desktopFolder,
                    reason: "Satchel saves captured screenshots into Desktop/Satchel.",
                    requiredBeforeRun: false
                )
            ]
        case .recordAudio:
            return [
                ToolPermissionRequirement(
                    kind: .microphone,
                    reason: "Satchel needs Microphone permission to record audio from your input device.",
                    requiredBeforeRun: true
                )
            ]
        case .transcribe:
            return [
                ToolPermissionRequirement(
                    kind: .speechRecognition,
                    reason: "Satchel needs Speech Recognition permission to turn audio into text on this Mac.",
                    requiredBeforeRun: true
                )
            ]
        case .wifiPassword:
            return [
                ToolPermissionRequirement(
                    kind: .location,
                    reason: "Satchel needs Location Services permission so macOS allows reading the current Wi-Fi network name.",
                    requiredBeforeRun: true
                ),
                ToolPermissionRequirement(
                    kind: .keychain,
                    reason: "Satchel reads the saved Wi-Fi password from your macOS Keychain when you allow Keychain access.",
                    requiredBeforeRun: false
                )
            ]
        case .organizeDownloads:
            return [
                ToolPermissionRequirement(
                    kind: .downloadsFolder,
                    reason: "Satchel needs access to your Downloads folder to preview and organize files.",
                    requiredBeforeRun: true
                )
            ]
        case .storageExplorer:
            return [
                ToolPermissionRequirement(
                    kind: .fullDiskAccess,
                    reason: "Satchel needs Full Disk Access to measure protected folders such as iPhone backups, Containers, and Downloads.",
                    requiredBeforeRun: true
                )
            ]
        case .uninstallApp:
            return [
                ToolPermissionRequirement(
                    kind: .fullDiskAccess,
                    reason: "Satchel needs Full Disk Access to find related app files in Library/Containers and Application Support.",
                    requiredBeforeRun: true
                ),
                ToolPermissionRequirement(
                    kind: .appManagement,
                    reason: "Satchel needs App Management permission to move another app bundle to the Trash.",
                    requiredBeforeRun: false
                )
            ]
        case .fixDamaged:
            return [
                ToolPermissionRequirement(
                    kind: .appManagement,
                    reason: "Satchel needs App Management permission to clear the quarantine flag on apps inside Applications.",
                    requiredBeforeRun: false
                )
            ]
        case .ejectDisks:
            return [
                ToolPermissionRequirement(
                    kind: .removableVolumes,
                    reason: "Satchel needs Removable Volumes permission to eject external drives.",
                    requiredBeforeRun: false
                )
            ]
        case .loginItems:
            return [
                ToolPermissionRequirement(
                    kind: .fullDiskAccess,
                    reason: "Satchel needs folder access to read and manage property lists in Library/LaunchAgents.",
                    requiredBeforeRun: false
                )
            ]
        case .downloadVideo, .qrCode, .markdownToPDF, .webPageToPDF:
            return [
                ToolPermissionRequirement(
                    kind: .downloadsFolder,
                    reason: "Satchel needs access to your Downloads folder to save output files in Downloads/Satchel.",
                    requiredBeforeRun: false
                )
            ]
        default:
            return []
        }
    }

    public static let permissionedTools: [ToolID] = ToolID.allCases.filter { !requirements(for: $0).isEmpty }

    public static func toolNeedsPermission(_ id: ToolID) -> Bool {
        !requirements(for: id).isEmpty
    }

    public static func reason(for id: ToolID, kind: PermissionKind) -> String {
        if let match = requirements(for: id).first(where: { $0.kind == kind }) {
            return match.reason
        }
        let name = ToolRegistry.byID[id]?.name ?? "this tool"
        return "Satchel needs \(kind.displayName) permission so \(name) can finish."
    }
}
