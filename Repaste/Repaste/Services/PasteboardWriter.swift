//
//  PasteboardWriter.swift
//  Repaste
//
//  剪贴板写回器：把 Clip 条目按类型原样写回系统剪贴板（写后防自吞）
//

import AppKit
import Foundation

// MARK: - 剪贴板写回器

/// 剪贴板写回器：按条目类型写回系统剪贴板
/// - text / link：纯文本写回（链接也写 URL 原文，不转富文本）
/// - image：原图存盘数据写 .tiff + .png 双类型；原图被 TTL 清理时降级用缩略图数据
/// - file：写 .fileURL 类型（NSURL(fileURLWithPath:)）
/// 写完统一调用 ClipboardMonitor.markExternalWrite() 防止刚写回的条目再次入库置顶
enum PasteboardWriter {
    enum BatchImageError: Error { case missingOriginal(Int) }

    static func write(images: [Clip]) throws {
        let sources = try images.enumerated().map { index, clip in
            guard clip.kindEnum == .image, let ref = clip.payloadRef,
                  ImageStore.shared.hasOriginal(name: ref),
                  let data = try? Data(contentsOf: ImageStore.shared.fileURL(name: ref)) else {
                throw BatchImageError.missingOriginal(index + 1)
            }
            return ImageBatchPasteboard.Source(data: data, fileExtension: (ref as NSString).pathExtension)
        }
        try ImageBatchPasteboard.write(sources, to: .general,
            cacheRoot: ImageStore.shared.copiedImagesRoot, ttlDays: SettingsStore.shared.imageTtlDays)
        ClipboardMonitor.shared.markExternalWrite()
    }

    /// One merged plain-text payload, with the same self-recording suppression as a single item.
    @discardableResult
    static func write(text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents()
        let success = pasteboard.setString(text, forType: .string)
        ClipboardMonitor.shared.markExternalWrite()
        return success
    }

    /// 写回条目（prepareForNewContents 清空旧类型后按类型写入）
    static func write(clip: Clip) {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents()

        switch clip.kindEnum {
        case .text, .link:
            // 纯文本写回（链接也写原文）
            if let text = clip.payloadText {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            writeImage(clip: clip, to: pasteboard)
        case .file:
            // payloadText 记绝对路径；写 .fileURL 类型（目标 App / Finder ⌘V 直接可用）
            if let path = clip.payloadText, !path.isEmpty {
                pasteboard.writeObjects([NSURL(fileURLWithPath: path)])
            }
        }

        // 防自吞：写回后下一次轮询跳过，避免刚使用的条目再次入库置顶
        ClipboardMonitor.shared.markExternalWrite()
    }

    // MARK: 图片写回

    /// 图片写回：优先原图存盘数据；原图被清理（TTL / 清除图片）时降级用缩略图数据
    private static func writeImage(clip: Clip, to pasteboard: NSPasteboard) {
        guard let ref = clip.payloadRef else { return }

        // 原图在盘：直接用存盘数据（保真，不经过缩放）
        if ImageStore.shared.hasOriginal(name: ref),
           let data = try? Data(contentsOf: ImageStore.shared.fileURL(name: ref)) {
            applyImageData(data, format: clip.format, to: pasteboard)
            return
        }

        // 原图已清理：降级用缩略图数据（缩略图本身是 PNG 文件）
        let thumbURL = ImageStore.shared.fileURL(name: ImageStore.thumbName(for: ref))
        if let thumbData = try? Data(contentsOf: thumbURL) {
            applyImageData(thumbData, format: "PNG", to: pasteboard)
            return
        }

        // 兜底：NSImage 加载（缩略图文件也缺失时至少写 TIFF）
        if let image = ImageStore.shared.load(name: ImageStore.thumbName(for: ref))
            ?? ImageStore.shared.load(name: ref),
           let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// 图片数据 → .tiff + .png 双类型写回
    /// TIFF 是 macOS 剪贴板最兼容的图片类型；PNG 类型 PNG 原图直接写原始数据、
    /// 其他格式经 NSBitmapImageRep 转 PNG（PasteboardReader 检测 .png 时直接命中）
    private static func applyImageData(_ data: Data, format: String?, to pasteboard: NSPasteboard) {
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        if format?.uppercased() == "PNG" {
            pasteboard.setData(data, forType: .png)
        } else if let rep = NSBitmapImageRep(data: data),
                  let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
    }
}
