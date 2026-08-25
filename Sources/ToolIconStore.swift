import AppKit
import Foundation
import UniformTypeIdentifiers

enum ToolIconStoreError: LocalizedError {
    case unsupportedImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedImage: return "无法读取所选图像。"
        case .encodingFailed: return "无法保存所选图像。"
        }
    }
}

/// 自定义图标只保存为 Application Support 中由本应用生成的 PNG，不保留原始外部路径或网络 URL。
struct ToolIconStore {
    static let shared = ToolIconStore()
    static let supportedContentTypes: [UTType] = [.png, .jpeg, .heic, .tiff]

    let directoryURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL = ToolIconStore.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func storeImage(from sourceURL: URL) throws -> String {
        guard sourceURL.isFileURL,
              let image = NSImage(contentsOf: sourceURL) else {
            throw ToolIconStoreError.unsupportedImage
        }
        let pngData = try normalizedPNGData(from: image)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString.lowercased()).png"
        try pngData.write(to: directoryURL.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    func image(named filename: String?) -> NSImage? {
        guard let url = url(for: filename) else { return nil }
        return NSImage(contentsOf: url)
    }

    func removeImage(named filename: String?) {
        guard let url = url(for: filename) else { return }
        try? fileManager.removeItem(at: url)
    }

    func url(for filename: String?) -> URL? {
        guard let filename,
              filename == (filename as NSString).lastPathComponent,
              filename.hasSuffix(".png"),
              !filename.isEmpty else {
            return nil
        }
        return directoryURL.appendingPathComponent(filename)
    }

    private func normalizedPNGData(from image: NSImage) throws -> Data {
        let maximumDimension: CGFloat = 512
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw ToolIconStoreError.unsupportedImage
        }

        let scale = min(maximumDimension / sourceSize.width, maximumDimension / sourceSize.height, 1)
        let renderedSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = NSPoint(
            x: (maximumDimension - renderedSize.width) / 2,
            y: (maximumDimension - renderedSize.height) / 2
        )
        let canvas = NSImage(size: NSSize(width: maximumDimension, height: maximumDimension))
        canvas.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: origin, size: renderedSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1
        )
        canvas.unlockFocus()

        guard let tiffData = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ToolIconStoreError.encodingFailed
        }
        return pngData
    }

    private static func defaultDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("TermiPad", isDirectory: true)
            .appendingPathComponent("ToolIcons", isDirectory: true)
    }
}
