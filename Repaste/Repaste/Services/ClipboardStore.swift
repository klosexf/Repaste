//
//  ClipboardStore.swift
//  Repaste
//
//  数据操作门面：UI 调用的唯一数据入口（后续任务扩展查询 / 筛选）
//

import Foundation
import Observation
import SwiftData

// MARK: - 剪贴板数据门面

/// 数据操作门面（单例）：持有独立 ModelContext，所有数据操作在 MainActor（项目默认隔离）
@Observable
final class ClipboardStore {
    /// 单例
    static let shared = ClipboardStore()

    /// 独立 ModelContext（与共享容器绑定）
    private let context: ModelContext

    private init() {
        context = ModelContext(ModelContainerProvider.shared)
        // 关闭自动保存：所有写操作显式 save，时机可控
        context.autosaveEnabled = false
    }

    // MARK: 写操作

    /// 插入一条剪贴板记录
    func insert(clip: Clip) {
        context.insert(clip)
        save()
    }

    /// 清空全部：历史 + 模板组 + 模板条目 + 图片文件
    func clearAll() {
        deleteClips(FetchDescriptor<Clip>())
        deleteGroups(FetchDescriptor<TemplateGroup>())
        ImageStore.shared.deleteAllFiles()
        save()
    }

    /// 只清历史（保留模板组与模板条目）
    func clearHistory() {
        deleteClips(FetchDescriptor<Clip>(predicate: #Predicate { $0.groupId == nil }))
        save()
    }

    /// 删除全部图片文件与 image 类记录（文本历史保留）
    func clearImages() {
        // 删除全部 image 类记录（含模板内图片条目，连带其文件）
        deleteClips(FetchDescriptor<Clip>(predicate: #Predicate { $0.kind == "image" }))
        // 清空图片目录兜底（清理缩略图与孤儿文件）
        ImageStore.shared.deleteAllFiles()
        save()
    }

    /// 淘汰溢出：未固定非模板条目按时间新→旧保留前 maxItems 条，其余删除（连带图片文件）
    func purgeOverflow(maxItems: Int) {
        let descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.pinned == false && $0.groupId == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let candidates = try? context.fetch(descriptor), candidates.count > maxItems else { return }
        for clip in candidates.dropFirst(maxItems) {
            deleteClipFiles(clip)
            context.delete(clip)
        }
        save()
    }

    // MARK: 查询

    /// 查询全部条目（createdAt 新→旧；面板列表数据快照）
    func fetchAllClips() -> [Clip] {
        let descriptor = FetchDescriptor<Clip>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 查询全部模板组（sortIndex 升序；面板 tab 行用）
    func fetchAllGroups() -> [TemplateGroup] {
        let descriptor = FetchDescriptor<TemplateGroup>(sortBy: [SortDescriptor(\.sortIndex, order: .forward)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: 模板组与模板 CRUD

    /// 创建模板组（sortIndex = 现有最大值 + 1，追加在标签行末尾）
    @discardableResult
    func createGroup(name: String) -> TemplateGroup {
        let descriptor = FetchDescriptor<TemplateGroup>()
        let maxIndex = ((try? context.fetch(descriptor)) ?? []).map(\.sortIndex).max() ?? -1
        let group = TemplateGroup(name: name, sortIndex: maxIndex + 1)
        context.insert(group)
        save()
        return group
    }

    /// 重命名模板组
    func renameGroup(_ group: TemplateGroup, to name: String) {
        group.name = name
        save()
    }

    /// 删除模板组（组内全部模板条目连同图片文件一并删除）
    func deleteGroup(_ group: TemplateGroup) {
        // 先删组内模板条目（连带各自图片文件），再删组本身
        let groupId = group.id
        deleteClips(FetchDescriptor<Clip>(predicate: #Predicate { $0.groupId == groupId }))
        context.delete(group)
        save()
    }

    /// 组内模板条目（sortIndex 升序；无值条目排后面并按 createdAt 新→旧回退）
    func templates(inGroup groupId: UUID) -> [Clip] {
        let descriptor = FetchDescriptor<Clip>(predicate: #Predicate { $0.groupId == groupId })
        let result = (try? context.fetch(descriptor)) ?? []
        return result.sorted { a, b in
            switch (a.sortIndex, b.sortIndex) {
            case let (lhs?, rhs?): return lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt > b.createdAt
            }
        }
    }

    /// 新建文本模板条目（内容即条目：preview 前 200 字、全文存 payloadText、pinned 不参与淘汰）
    @discardableResult
    func addTemplate(text: String, groupId: UUID) -> Clip {
        let clip = Clip(
            kind: .text,
            preview: PasteboardReader.previewText(from: text),
            payloadText: text,
            byteSize: text.utf8.count,
            pinned: true,
            groupId: groupId,
            sortIndex: nextSortIndex(inGroup: groupId)
        )
        context.insert(clip)
        save()
        return clip
    }

    /// 复制历史条目为模板（图片类落一份独立文件副本，避免与历史条目共享 payloadRef）
    @discardableResult
    func addTemplate(copying source: Clip, groupId: UUID) -> Clip {
        // 图片类：复制原图 + 缩略图文件，模板持有独立文件（删除互不影响）
        var payloadRef = source.payloadRef
        if source.kindEnum == .image, let ref = source.payloadRef,
           let data = try? Data(contentsOf: ImageStore.shared.fileURL(name: ref)) {
            let (newRef, _) = ImageStore.shared.save(data: data, format: source.format ?? "PNG")
            payloadRef = newRef
        }
        let clip = Clip(
            kind: source.kindEnum,
            preview: source.preview,
            payloadRef: payloadRef,
            payloadText: source.payloadText,
            byteSize: source.byteSize,
            pinned: true,
            groupId: groupId,
            pixelWidth: source.pixelWidth,
            pixelHeight: source.pixelHeight,
            format: source.format,
            sortIndex: nextSortIndex(inGroup: groupId)
        )
        context.insert(clip)
        save()
        return clip
    }

    /// 模板重排序：按传入顺序重写 sortIndex（0…n-1）并持久化
    func reorderTemplates(_ orderedTemplates: [Clip]) {
        for (index, clip) in orderedTemplates.enumerated() {
            clip.sortIndex = index
        }
        save()
    }

    /// 组内下一个可用 sortIndex（空组返回 0）
    private func nextSortIndex(inGroup groupId: UUID) -> Int {
        (templates(inGroup: groupId).compactMap(\.sortIndex).max() ?? -1) + 1
    }

    /// 删除单条条目（连带图片文件；面板 ⌫ / 行内菜单调用）
    func delete(clip: Clip) {
        deleteClipFiles(clip)
        context.delete(clip)
        save()
    }

    /// 最近一条历史条目（非模板，含置顶；按时间新→旧取第一条，去重比对用）
    func latestClip() -> Clip? {
        var descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.groupId == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// 刷新条目时间戳到当前时刻（重复复制相同内容时置顶展示）
    func touch(clip: Clip) {
        clip.createdAt = Date()
        save()
    }

    /// 记录条目最近一次在主面板被点击使用的时刻（「最近操作优先」排序依据）
    func markUsed(clip: Clip) {
        clip.lastUsedAt = Date()
        save()
    }

    /// 切换置顶（就地翻转 pinned 并持久化；列表排序由面板重排）
    func togglePin(clip: Clip) {
        clip.pinned.toggle()
        save()
    }

    // MARK: 私有

    /// 批量删除条目（连带删除各自关联的图片文件）
    private func deleteClips(_ descriptor: FetchDescriptor<Clip>) {
        guard let clips = try? context.fetch(descriptor) else { return }
        for clip in clips {
            deleteClipFiles(clip)
            context.delete(clip)
        }
    }

    /// 批量删除模板组
    private func deleteGroups(_ descriptor: FetchDescriptor<TemplateGroup>) {
        guard let groups = try? context.fetch(descriptor) else { return }
        for group in groups {
            context.delete(group)
        }
    }

    /// 删除条目关联的图片文件（原图 + 缩略图）
    private func deleteClipFiles(_ clip: Clip) {
        guard let ref = clip.payloadRef else { return }
        ImageStore.shared.delete(names: [ref])
    }

    /// 保存变更（失败静默：数据操作不阻塞 UI 主流程）
    private func save() {
        try? context.save()
    }
}
