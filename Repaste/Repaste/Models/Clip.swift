//
//  Clip.swift
//  Repaste
//
//  剪贴板条目 SwiftData 模型（底层 SQLite）
//

import Foundation
import SwiftData

// MARK: - 剪贴板条目模型

/// 剪贴板条目：一条被录制的历史记录，或模板组内的模板条目（groupId 非 nil）
@Model
final class Clip {
    /// 唯一标识
    @Attribute(.unique) var id: UUID

    /// 条目类型（ClipKind.rawValue："text" / "image" / "file" / "link"）
    var kind: String

    /// ≤200 字预览（文本前 200 字 / 图片文件名 / 链接完整 URL / 文件名）
    var preview: String

    /// 图片原图文件名（ImageStore 管理，缩略图名由原图名推导）；文本类为 nil（全文存 payloadText）
    var payloadRef: String?

    /// 文本类全文（含链接原文）；图片 / 文件类为 nil
    var payloadText: String?

    /// 来源 App bundleId；未知为 nil
    var sourceBundleId: String?

    /// 来源 App 显示名；未知为 nil
    var sourceAppName: String?

    /// 来源 App 图标缓存文件名（AppIconStore 管理）
    var sourceIconPath: String?

    /// 字节数（文本为 UTF-8 字节数；图片为原图字节数）
    var byteSize: Int

    /// 录制时间
    var createdAt: Date

    /// 最近一次在主面板被点击使用的时间（nil = 从未使用；「最近操作优先」排序依据）
    var lastUsedAt: Date?

    /// 置顶：不参与淘汰
    var pinned: Bool

    /// 非 nil = 属于某模板组（隐含 pinned，不参与淘汰），值为该组的 id
    var groupId: UUID?

    /// 模板条目组内排序序号（升序展示；仅模板条目使用，历史条目忽略该字段）
    var sortIndex: Int?

    // MARK: 图片附加元数据（仅 image 类有效）

    /// 图片像素宽
    var pixelWidth: Int?

    /// 图片像素高
    var pixelHeight: Int?

    /// 图片格式（"PNG" / "JPEG" 等）
    var format: String?

    // MARK: 便捷属性

    /// 是否为模板条目（属于某模板组，不参与淘汰）
    var isTemplate: Bool { groupId != nil }

    /// 类型枚举（无法识别的存量值按文本处理）
    var kindEnum: ClipKind { ClipKind(rawValue: kind) ?? .text }

    // MARK: 初始化

    init(
        kind: ClipKind,
        preview: String,
        payloadRef: String? = nil,
        payloadText: String? = nil,
        sourceBundleId: String? = nil,
        sourceAppName: String? = nil,
        sourceIconPath: String? = nil,
        byteSize: Int = 0,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        pinned: Bool = false,
        groupId: UUID? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        format: String? = nil,
        sortIndex: Int? = nil
    ) {
        self.id = UUID()
        self.kind = kind.rawValue
        self.preview = preview
        self.payloadRef = payloadRef
        self.payloadText = payloadText
        self.sourceBundleId = sourceBundleId
        self.sourceAppName = sourceAppName
        self.sourceIconPath = sourceIconPath
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.pinned = pinned
        self.groupId = groupId
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.format = format
        self.sortIndex = sortIndex
    }
}
