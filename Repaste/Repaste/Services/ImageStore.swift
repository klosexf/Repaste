//
//  ImageStore.swift
//  Repaste
//
//  图片文件存储：原图 + 40×40 等比缩略图落盘管理
//

import AppKit
import Foundation

// MARK: - 图片存储

/// 图片文件存储（单例）
/// 根目录：Application Support/Repaste/images/（自动创建）
/// 命名约定：原图 = <UUID>.<ext>；缩略图 = <UUID>-thumb.png（由原图名推导，最长边 40px）
final class ImageStore {
    /// 单例
    static let shared = ImageStore()

    /// 根目录
    private let root: URL
    var copiedImagesRoot: URL { root.deletingLastPathComponent().appendingPathComponent("copied-images", isDirectory: true) }

    /// 缩略图最大边长（等比缩放，小图不放大）
    private static let thumbMaxDimension: CGFloat = 40

    /// 内存缓存：解码后的 NSImage 按文件名缓存（NSCache 线程安全，主线程 load 与后台解码共用）。
    /// 避免滚动列表 / 重复打开预览时对同一文件反复 `NSImage(contentsOf:)` 解码。
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Repaste/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: 保存

    /// 保存图片数据：原图写盘 + 生成 40×40 等比缩略图写盘
    /// - Parameters:
    ///   - data: 图片原始数据
    ///   - format: 图片格式（"PNG" / "JPEG" 等，用于原图后缀）
    /// - Returns: (原图文件名, 缩略图文件名)
    @discardableResult
    func save(data: Data, format: String) -> (originalName: String, thumbName: String) {
        let originalName = "\(UUID().uuidString).\(Self.fileExtension(for: format))"
        let thumbName = Self.thumbName(for: originalName)

        // 原图写盘（失败静默：hasOriginal 为 false，UI 用缩略图降级显示）
        try? data.write(to: root.appendingPathComponent(originalName))

        // 缩略图写盘（失败静默：仅影响列表加载性能，UI 回退加载原图）
        if let thumbData = Self.thumbnailData(from: data, maxDimension: Self.thumbMaxDimension) {
            try? thumbData.write(to: root.appendingPathComponent(thumbName))
        }

        return (originalName, thumbName)
    }

    // MARK: 读取

    /// 磁盘解码图片并走内存缓存（线程安全；主线程 load 与后台解码均可调用）
    nonisolated static func decodeCached(fileName: String, url: URL) -> NSImage? {
        let key = fileName as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 加载图片（传入原图或缩略图文件名均可；命中内存缓存避免重复解码）
    func load(name: String) -> NSImage? {
        Self.decodeCached(fileName: name, url: root.appendingPathComponent(name))
    }

    /// 移除指定文件的缓存（删除文件后避免残留解码结果）
    nonisolated static func invalidateCache(_ name: String) {
        cache.removeObject(forKey: name as NSString)
    }

    /// 文件完整 URL
    func fileURL(name: String) -> URL {
        root.appendingPathComponent(name)
    }

    /// 原图是否仍在盘上（purgeExpired 清理原图后为 false，UI 用缩略图降级显示）
    func hasOriginal(name: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
    }

    // MARK: 删除

    /// 删除指定原图及其对应缩略图
    func delete(names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
            try? FileManager.default.removeItem(at: root.appendingPathComponent(Self.thumbName(for: name)))
            Self.invalidateCache(name)
            Self.invalidateCache(Self.thumbName(for: name))
        }
    }

    /// 清空图片目录（全部原图与缩略图，供「清除图片」调用）
    func deleteAllFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in files {
            try? FileManager.default.removeItem(at: url)
        }
        Self.cache.removeAllObjects()
        try? FileManager.default.removeItem(at: copiedImagesRoot)
    }

    // MARK: TTL 清理

    /// 删除 mtime 超过 TTL 的原图（缩略图保留，用于降级显示）
    /// - Parameter ttlDays: 保留天数
    func purgeExpired(ttlDays: Int) {
        let activeCopies = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        ImageBatchPasteboard.purgeExpiredCache(at: copiedImagesRoot, keeping: activeCopies, ttlDays: ttlDays)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let ttl = TimeInterval(ttlDays) * 24 * 60 * 60
        let now = Date()
        for url in files {
            // 跳过缩略图（保留用于降级显示）
            if url.lastPathComponent.contains("-thumb") { continue }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            if now.timeIntervalSince(mtime) > ttl {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: 命名推导

    /// 原图文件名 → 缩略图文件名（<UUID>.png → <UUID>-thumb.png）
    static func thumbName(for originalName: String) -> String {
        let base = (originalName as NSString).deletingPathExtension
        return "\(base)-thumb.png"
    }

    /// 图片格式字符串 → 文件后缀（未知格式默认 png）
    private static func fileExtension(for format: String) -> String {
        switch format.uppercased() {
        case "PNG": return "png"
        case "JPEG", "JPG": return "jpg"
        case "GIF": return "gif"
        case "TIFF", "TIF": return "tif"
        case "HEIC": return "heic"
        case "BMP": return "bmp"
        default: return "png"
        }
    }

    /// 生成等比缩略图 PNG 数据（最长边 ≤ maxDimension，小图不放大）
    private static func thumbnailData(from data: Data, maxDimension: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let source = image.size
        guard source.width > 0, source.height > 0 else { return nil }

        let scale = min(1, maxDimension / max(source.width, source.height))
        let target = NSSize(
            width: max(1, (source.width * scale).rounded()),
            height: max(1, (source.height * scale).rounded())
        )

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = target

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target))

        return rep.representation(using: .png, properties: [:])
    }
}
