import Foundation

public enum ToolCategory: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case video
    case audio
    case images
    case docs
    case text
    case files
    case mac
    case dev

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .images: return "Images"
        case .docs: return "Docs"
        case .text: return "Text & Speech"
        case .files: return "Files"
        case .mac: return "Mac"
        case .dev: return "Dev"
        }
    }

    public var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .images: return "photo"
        case .docs: return "doc.text"
        case .text: return "text.quote"
        case .files: return "folder"
        case .mac: return "desktopcomputer"
        case .dev: return "curlybraces"
        }
    }

    public var tagline: String {
        switch self {
        case .video: return "Trim, convert, resize, and shrink clips"
        case .audio: return "Record, cut, and convert sound"
        case .images: return "Edit, convert, and clean up pictures"
        case .docs: return "Merge, sign, redact, and export PDFs"
        case .text: return "Transcribe, translate, and reshape text"
        case .files: return "Rename, zip, and sort what you keep"
        case .mac: return "Free up space and fix everyday snags"
        case .dev: return "Format, decode, and generate without leaving the Mac"
        }
    }
}

public enum ToolStatus: String, Codable, Sendable, Hashable {
    case working
    case placeholder
}

public enum ToolID: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    // Video
    case downloadVideo = "download-video"
    case burnSubtitles = "burn-subtitles"
    case changeSpeed = "change-speed"
    case extractFrames = "extract-frames"
    case recordScreen = "record-screen"
    case compressVideo = "compress-video"
    case convertVideo = "convert-video"
    case resizeVideo = "resize-video"
    case cropRotateVideo = "crop-rotate-video"
    case mediaInfo = "media-info"
    case trimVideo = "trim-video"
    case mergeVideos = "merge-videos"
    case muteVideo = "mute-video"
    case replaceAudio = "replace-audio"
    case videoToGIF = "video-to-gif"
    // Audio
    case cleanAudio = "clean-audio"
    case recordAudio = "record-audio"
    case trimAudio = "trim-audio"
    case extractAudio = "extract-audio"
    case convertAudio = "convert-audio"
    // Images
    case screenshot = "screenshot"
    case blurFaces = "blur-faces"
    case beautifyScreenshot = "beautify-screenshot"
    case removeBackground = "remove-background"
    case convertImages = "convert-images"
    case compressImages = "compress-images"
    case resizeImages = "resize-images"
    case rotateImages = "rotate-images"
    case removeMetadata = "remove-metadata"
    case colorPicker = "color-picker"
    case redactImage = "redact-image"
    case annotateScreenshot = "annotate-screenshot"
    case watermark = "watermark"
    // Docs
    case scanDocument = "scan-document"
    case redactPDF = "redact-pdf"
    case fillForms = "fill-forms"
    case searchablePDF = "searchable-pdf"
    case pdfToWord = "pdf-to-word"
    case signPDF = "sign-pdf"
    case mergePDFs = "merge-pdfs"
    case splitPDF = "split-pdf"
    case organizePDF = "organize-pdf"
    case deletePages = "delete-pages"
    case extractPages = "extract-pages"
    case imagesToPDF = "images-to-pdf"
    case cropPDF = "crop-pdf"
    case compressPDF = "compress-pdf"
    case addPassword = "add-password"
    case removePassword = "remove-password"
    case pdfToImages = "pdf-to-images"
    case convertDocuments = "convert-documents"
    case wordToPDF = "word-to-pdf"
    case powerpointToPDF = "powerpoint-to-pdf"
    case excelToPDF = "excel-to-pdf"
    case webPageToPDF = "webpage-to-pdf"
    case markdownToPDF = "markdown-to-pdf"
    // Text
    case transcribe = "transcribe"
    case summarize = "summarize"
    case extractText = "extract-text"
    case captureText = "capture-text"
    case translate = "translate"
    case textToSpeech = "text-to-speech"
    case askDocument = "ask-document"
    case wordCounter = "word-counter"
    case caseConverter = "case-converter"
    // Files
    case qrCode = "qr-code"
    case batchRename = "batch-rename"
    case findDuplicates = "find-duplicates"
    case zipUnzip = "zip-unzip"
    case organizeDownloads = "organize-downloads"
    // Mac
    case networkSpeed = "network-speed"
    case clipboardHistory = "clipboard-history"
    case storageExplorer = "storage-explorer"
    case wifiPassword = "wifi-password"
    case diskSpeed = "disk-speed"
    case batteryHealth = "battery-health"
    case keepAwake = "keep-awake"
    case uninstallApp = "uninstall-app"
    case presentationMode = "presentation-mode"
    case cleanKeyboard = "clean-keyboard"
    case deadPixel = "dead-pixel"
    case ejectDisks = "eject-disks"
    case loginItems = "login-items"
    case fixDamaged = "fix-damaged"
    case resetPermissions = "reset-permissions"
    case hiddenSettings = "hidden-settings"
    case displayControl = "display-control"
    case mouseFixes = "mouse-fixes"
    // Developer
    case jsonFormatter = "json-formatter"
    case base64 = "base64"
    case hashGenerator = "hash-generator"
    case uuidGenerator = "uuid-generator"
    case jwtDecoder = "jwt-decoder"
    case timestamp = "timestamp"
    case diffChecker = "diff-checker"
    case regexTester = "regex-tester"
    case cleanLinks = "clean-links"
    case coordinatePicker = "coordinate-picker"
    case unicodeInspector = "unicode-inspector"
    case loremIpsum = "lorem-ipsum"
    case passwordGenerator = "password-generator"
    case csvJSON = "csv-json"

    public var id: String { rawValue }
}

public struct ToolDefinition: Identifiable, Hashable, Codable, Sendable {
    public var id: ToolID
    public var name: String
    public var category: ToolCategory
    public var summary: String
    public var symbol: String
    public var status: ToolStatus
    public var keywords: [String]
    public var spansTwoColumns: Bool

    public init(
        id: ToolID,
        name: String,
        category: ToolCategory,
        summary: String,
        symbol: String,
        status: ToolStatus,
        keywords: [String],
        spansTwoColumns: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.symbol = symbol
        self.status = status
        self.keywords = keywords
        self.spansTwoColumns = spansTwoColumns
    }
}

public enum ToolRegistry {
    public static let all: [ToolDefinition] = ToolCatalog.definitions

    public static let byID: [ToolID: ToolDefinition] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    public static func definition(_ id: ToolID) -> ToolDefinition {
        guard let tool = byID[id] else {
            preconditionFailure("Missing tool \(id.rawValue)")
        }
        return tool
    }

    public static func tools(in category: ToolCategory) -> [ToolDefinition] {
        all.filter { $0.category == category }
    }

    public static func counts() -> [ToolCategory: Int] {
        var result: [ToolCategory: Int] = [:]
        for tool in all {
            result[tool.category, default: 0] += 1
        }
        return result
    }
}
