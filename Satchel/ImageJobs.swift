import AppKit
import CoreImage
import CoreGraphics
import Vision
import UniformTypeIdentifiers

enum ImageJobs {
    static func convert(urls: [URL], ext: String, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let type = ImageFiles.type(for: ext)
        return try await map(urls, progress: progress) { url in
            let image = try ImageFiles.load(url)
            let output = try Outputs.make(nextTo: url, suffix: "-converted", ext: ext)
            try ImageFiles.write(image, to: output, type: type, quality: type == .jpeg || type == .heic ? 0.9 : nil)
            return output
        }
    }

    static func compress(urls: [URL], quality: Double, progress: @escaping (Double) -> Void) async throws -> [URL] {
        try await map(urls, progress: progress) { url in
            let image = try ImageFiles.load(url)
            let ext = url.pathExtension.lowercased()
            let type: UTType = (ext == "png" || ext == "gif") ? .jpeg : ImageFiles.type(for: ext)
            let outExt = type == .jpeg ? "jpg" : (ext.isEmpty ? "jpg" : ext)
            let output = try Outputs.make(nextTo: url, suffix: "-smaller", ext: outExt)
            try ImageFiles.write(image, to: output, type: type, quality: min(0.95, max(0.2, quality)))
            return output
        }
    }

    static func resize(urls: [URL], maxEdge: Int, progress: @escaping (Double) -> Void) async throws -> [URL] {
        try await map(urls, progress: progress) { url in
            let image = try ImageFiles.load(url)
            let scaled = try scale(image, maxEdge: CGFloat(max(1, maxEdge)))
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let output = try Outputs.make(nextTo: url, suffix: "-resized", ext: ext)
            try ImageFiles.write(scaled, to: output, type: ImageFiles.type(for: ext), quality: 0.92)
            return output
        }
    }

    static func rotate(urls: [URL], quarterTurns: Int, flip: Bool, progress: @escaping (Double) -> Void) async throws -> [URL] {
        try await map(urls, progress: progress) { url in
            let image = try ImageFiles.load(url)
            let turns = ((quarterTurns % 4) + 4) % 4
            let swap = turns % 2 == 1
            let canvas = CGSize(
                width: CGFloat(swap ? image.height : image.width),
                height: CGFloat(swap ? image.width : image.height)
            )
            let source = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
            let turned = try draw(image, canvas: canvas) { context, _ in
                context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                context.rotate(by: CGFloat(turns) * -.pi / 2)
                if flip { context.scaleBy(x: -1, y: 1) }
                context.translateBy(x: -source.width / 2, y: -source.height / 2)
                context.draw(image, in: CGRect(origin: .zero, size: source))
            }
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let output = try Outputs.make(nextTo: url, suffix: "-rotated", ext: ext)
            try ImageFiles.write(turned, to: output, type: ImageFiles.type(for: ext), quality: 0.92)
            return output
        }
    }

    static func stripMetadata(urls: [URL], progress: @escaping (Double) -> Void) async throws -> [URL] {
        try await map(urls, progress: progress) { url in
            let image = try ImageFiles.load(url)
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let output = try Outputs.make(nextTo: url, suffix: "-clean", ext: ext)
            try ImageFiles.write(image, to: output, type: ImageFiles.type(for: ext), quality: ext.lowercased() == "png" ? nil : 0.95)
            return output
        }
    }

    static func removeBackground(urls: [URL], background: BackgroundChoice, crop: Bool, progress: @escaping (Double) -> Void) async throws -> [URL] {
        try await map(urls, progress: progress) { url in
            let image = try ImageFiles.load(url)
            let cut = try cutout(image, background: background, cropToSubject: crop)
            let output = try Outputs.make(nextTo: url, suffix: "-cutout", ext: "png")
            try ImageFiles.write(cut, to: output, type: .png, quality: nil)
            return output
        }
    }

    enum FaceStyle: String, CaseIterable, Identifiable {
        case blur, pixel, black
        var id: String { rawValue }
        var label: String {
            switch self {
            case .blur: return "Blur"
            case .pixel: return "Pixelate"
            case .black: return "Cover"
            }
        }
    }

    static func blurFaces(urls: [URL], style: FaceStyle, progress: @escaping (Double) -> Void) async throws -> [URL] {
        try await map(urls, progress: progress) { url in
            let image = try ImageFiles.load(url)
            let result = try coverFaces(image, style: style)
            let output = try Outputs.make(nextTo: url, suffix: "-faces", ext: "jpg")
            try ImageFiles.write(result, to: output, type: .jpeg, quality: 0.92)
            return output
        }
    }

    static func watermark(urls: [URL], text: String, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw ToolError(message: "Type the watermark text first.") }
        return try await map(urls, progress: progress) { url in
            let image = try ImageFiles.load(url)
            let marked = try draw(image) { context, size in
                context.draw(image, in: CGRect(origin: .zero, size: size))
                let fontSize = max(18, size.width / 28)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.85)
                ]
                let string = NSAttributedString(string: label, attributes: attributes)
                let bounds = string.boundingRect(with: CGSize(width: size.width * 0.8, height: 400), options: [.usesLineFragmentOrigin])
                let origin = CGPoint(x: size.width - bounds.width - 24, y: 24)
                context.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: NSColor.black.withAlphaComponent(0.45).cgColor)
                string.draw(at: origin)
            }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let output = try Outputs.make(nextTo: url, suffix: "-marked", ext: ext)
            try ImageFiles.write(marked, to: output, type: ImageFiles.type(for: ext), quality: 0.92)
            return output
        }
    }

    static func beautify(
        url: URL,
        padding: CGFloat,
        radius: CGFloat,
        shadow: Bool,
        aspect: CGSize?,
        background: NSColor
    ) throws -> URL {
        let image = try ImageFiles.load(url)
        let source = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
        let pad = max(0, padding)
        var canvas = CGSize(width: CGFloat(image.width) + pad * 2, height: CGFloat(image.height) + pad * 2)
        if let aspect, aspect.width > 0, aspect.height > 0 {
            let ratio = aspect.width / aspect.height
            if canvas.width / canvas.height > ratio {
                canvas.height = canvas.width / ratio
            } else {
                canvas.width = canvas.height * ratio
            }
        }
        let result = NSImage(size: canvas)
        result.lockFocus()
        background.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        let picture = NSRect(
            x: (canvas.width - CGFloat(image.width)) / 2,
            y: (canvas.height - CGFloat(image.height)) / 2,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        if shadow {
            let shadowRect = picture.insetBy(dx: 8, dy: 8).offsetBy(dx: 0, dy: -10)
            NSColor.black.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: shadowRect, xRadius: radius, yRadius: radius).fill()
        }
        NSBezierPath(roundedRect: picture, xRadius: radius, yRadius: radius).addClip()
        source.draw(in: picture)
        result.unlockFocus()
        guard let cg = result.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ToolError(message: "Could not draw the framed image.")
        }
        let output = try Outputs.make(nextTo: url, suffix: "-framed", ext: "png")
        try ImageFiles.write(cg, to: output, type: .png, quality: nil)
        return output
    }

    static func scan(urls: [URL], progress: @escaping (Double) -> Void) async throws -> [URL] {
        var pages: [CGImage] = []
        for (index, url) in urls.enumerated() {
            let image = try ImageFiles.load(url)
            pages.append(try straighten(image))
            progress(Double(index + 1) / Double(max(1, urls.count)))
        }
        guard !pages.isEmpty else { throw ToolError(message: "Drop a photo of a page.") }
        let output = try Outputs.make(nextTo: urls[0], suffix: "-scan", ext: "pdf")
        try PDFJobs.writeImages(pages, to: output, pageBox: nil)
        return [output]
    }

    enum BackgroundChoice {
        case clear
        case white
        case color(NSColor)
    }

    private static func cutout(_ image: CGImage, background: BackgroundChoice, cropToSubject: Bool) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw ToolError(message: "No subject was found in that picture.")
        }
        let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        let input = CIImage(cgImage: image)
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        mask = mask.transformed(by: CGAffineTransform(
            scaleX: input.extent.width / max(mask.extent.width, 1),
            y: input.extent.height / max(mask.extent.height, 1)
        ))
        let backdrop: CIImage
        switch background {
        case .clear:
            backdrop = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: input.extent)
        case .white:
            backdrop = CIImage(color: .white).cropped(to: input.extent)
        case let .color(color):
            let rgb = color.usingColorSpace(.sRGB) ?? color
            let converted = CIColor(
                red: rgb.redComponent,
                green: rgb.greenComponent,
                blue: rgb.blueComponent,
                alpha: rgb.alphaComponent
            )
            backdrop = CIImage(color: converted).cropped(to: input.extent)
        }
        let blended = input.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: backdrop,
            kCIInputMaskImageKey: mask
        ])
        var output = blended
        if cropToSubject, let bounds = subjectBounds(maskBuffer) {
            let scaleX = input.extent.width / CGFloat(CVPixelBufferGetWidth(maskBuffer))
            let scaleY = input.extent.height / CGFloat(CVPixelBufferGetHeight(maskBuffer))
            let rect = CGRect(
                x: bounds.minX * scaleX,
                y: bounds.minY * scaleY,
                width: bounds.width * scaleX,
                height: bounds.height * scaleY
            ).intersection(input.extent)
            if rect.width > 2, rect.height > 2 {
                output = blended.cropped(to: rect)
            }
        }
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(output, from: output.extent) else {
            throw ToolError(message: "Could not save the cut-out.")
        }
        return cg
    }

    private static func subjectBounds(_ buffer: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        let step = max(1, width / 400)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                if bytes[y * rowBytes + x] > 16 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
    }

    private static func coverFaces(_ image: CGImage, style: FaceStyle) throws -> CGImage {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let faces = request.results ?? []
        guard !faces.isEmpty else { throw ToolError(message: "No faces were found.") }
        let ci = CIImage(cgImage: image)
        var output = ci
        for face in faces {
            let box = face.boundingBox
            let rect = CGRect(
                x: ci.extent.minX + box.origin.x * ci.extent.width,
                y: ci.extent.minY + box.origin.y * ci.extent.height,
                width: box.width * ci.extent.width,
                height: box.height * ci.extent.height
            ).insetBy(dx: -6, dy: -6).intersection(ci.extent)
            guard rect.width > 2, rect.height > 2 else { continue }
            let cropped = ci.cropped(to: rect)
            let replacement: CIImage
            switch style {
            case .blur:
                replacement = cropped.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18]).cropped(to: rect)
            case .pixel:
                replacement = cropped.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 14]).cropped(to: rect)
            case .black:
                replacement = CIImage(color: .black).cropped(to: rect)
            }
            output = replacement.composited(over: output)
        }
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(output, from: ci.extent) else {
            throw ToolError(message: "Could not draw the covered faces.")
        }
        return cg
    }

    private static func straighten(_ image: CGImage) throws -> CGImage {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.5
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1
        request.quadratureTolerance = 25
        request.minimumSize = 0.2
        request.maximumObservations = 1
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let ci = CIImage(cgImage: image)
        guard let rect = request.results?.first else {
            return try contrast(ci)
        }
        func point(_ value: CGPoint) -> CIVector {
            CIVector(x: ci.extent.minX + value.x * ci.extent.width, y: ci.extent.minY + value.y * ci.extent.height)
        }
        let corrected = ci.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": point(rect.topLeft),
            "inputTopRight": point(rect.topRight),
            "inputBottomLeft": point(rect.bottomLeft),
            "inputBottomRight": point(rect.bottomRight)
        ])
        return try contrast(corrected)
    }

    private static func contrast(_ image: CIImage) throws -> CGImage {
        let boosted = image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.15,
            kCIInputSaturationKey: 0,
            kCIInputBrightnessKey: 0.02
        ])
        let context = CIContext(options: nil)
        guard let cg = context.createCGImage(boosted, from: boosted.extent) else {
            throw ToolError(message: "Could not finish the scan.")
        }
        return cg
    }

    private static func scale(_ image: CGImage, maxEdge: CGFloat) throws -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxEdge / max(width, height))
        let size = CGSize(width: max(1, floor(width * scale)), height: max(1, floor(height * scale)))
        return try draw(image, canvas: size) { context, _ in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
    }

    private static func draw(
        _ image: CGImage,
        canvas: CGSize? = nil,
        _ body: (CGContext, CGSize) -> Void
    ) throws -> CGImage {
        let size = canvas ?? CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ToolError(message: "Could not draw the image.")
        }
        body(context, CGSize(width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let result = context.makeImage() else {
            throw ToolError(message: "Could not finish the image.")
        }
        return result
    }

    static func cover(url: URL, rects: [CGRect]) throws -> URL {
        let image = try ImageFiles.load(url)
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ToolError(message: "Could not cover that image.") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        context.setFillColor(NSColor.black.cgColor)
        for rect in rects where rect.width > 1 && rect.height > 1 {
            context.fill(rect)
        }
        guard let out = context.makeImage() else { throw ToolError(message: "Could not cover that image.") }
        let output = try Outputs.make(nextTo: url, suffix: "-redacted", ext: "png")
        try ImageFiles.write(out, to: output, type: .png, quality: nil)
        return output
    }

    private static func map(_ urls: [URL], progress: @escaping (Double) -> Void, _ body: (URL) throws -> URL) async throws -> [URL] {
        guard !urls.isEmpty else { throw ToolError(message: "Drop a picture first.") }
        var outputs: [URL] = []
        for (index, url) in urls.enumerated() {
            outputs.append(try body(url))
            progress(Double(index + 1) / Double(urls.count))
        }
        return outputs
    }
}
