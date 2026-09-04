//
//  PanelViewModel.swift
//  Repaste
//
//  面板状态机：标签页 / 搜索 / 来源筛选 / 键盘选中 + 过滤排序计算
//

import AppKit
import Foundation
import Observation
import SwiftUI

// MARK: - 面板标签页

/// 面板标签页（group 为模板组 tab）
enum PanelTab: Equatable {
    case all
    case text
    case image
    case link
    /// 模板组（值为 TemplateGroup.id）
    case group(UUID)

    /// 从设置 defaultTab 字符串解析（无法识别的值按 all 处理）
    static func fromSettings(_ raw: String) -> PanelTab {
        switch raw {
        case "text": return .text
        case "image": return .image
        case "link": return .link
        default: return .all
        }
    }
}

// MARK: - 来源计数条目

/// 来源条目：当前 Tab+搜索条件下来自某 App 的条数（供来源条）
struct SourceCount: Identifiable, Equatable {
    /// bundleId 或 "unknown"
    let key: String
    /// 显示名（未知来源 = "未知来源"）
    let name: String
    /// 条数
    let count: Int
    /// 来源 App 图标缓存文件名（nil = 未知来源，UI 用中性问号图标）
    let iconPath: String?

    var id: String { key }
}

// MARK: - 面板弹窗

/// 面板内浮层弹窗（全部为半透明遮罩 + 圆角卡片，不用系统 NSAlert）
enum PanelDialog: Equatable {
    /// 新建模板组（标签行「＋」触发）
    case newGroup
    /// 新建模板（模板 tab 底部「＋ 新建模板」触发；值为目标组 id）
    case newTemplate(UUID)
    /// 存入模板组（⋮ 菜单 / ⌘G 触发；值为源历史条目 id）
    case saveToGroup(UUID)
    /// 重命名模板组（值为组 id）
    case renameGroup(UUID)
    /// 删除模板组（值为组 id）
    case deleteGroup(UUID)
    /// 退出确认（头部 ⏻ 按钮触发）
    case quitConfirm
}

// MARK: - Toast 数据

/// 面板顶部 toast：主标题 + 可选副标题（如条目预览摘要）+ 可选动作按钮（如删除后「撤销」）
struct Toast: Equatable {
    let title: String
    let subtitle: String?
    /// 动作按钮文字（nil = 无按钮）
    let actionTitle: String?
    /// 动作回调（仅按钮点击触发；toast 自动消失不触发）
    let action: (() -> Void)?

    /// 闭包不参与相等比较（内容一致即视为同一个 toast）
    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.actionTitle == rhs.actionTitle
    }
}

// MARK: - 面板状态机

/// 面板状态机（@Observable）：持有筛选状态与数据快照，输出过滤排序后的列表；
/// 刘海下拉与快捷键居中双入口共用
@Observable
final class PanelViewModel {
    /// 未知来源 key（来源条 / 行内来源标签共用；对应 Clip.sourceBundleId == nil）
    static let unknownSourceKey = "unknown"

    // MARK: 筛选状态

    /// 当前标签页
    var selectedTab: PanelTab = .all {
        didSet { resetSelection() }
    }

    /// 搜索关键词（preview / payloadText 包含匹配，大小写不敏感）
    var searchText: String = "" {
        didSet { resetSelection() }
    }

    /// 来源筛选（bundleId 或 "unknown"；nil = 全部来源）
    var selectedSourceFilter: String? {
        didSet { resetSelection() }
    }

    /// 键盘选中行下标（filteredClips 下标；nil = 无选中）
    var selectionIndex: Int?

    /// 展示模式（notch 顶部圆角为 0；由 PanelController.show 写入）
    var isNotchMode = true

    /// notch 模式顶部安全区高度（菜单栏 / 刘海高度，头部行下移避开刘海；
    /// centered 模式为 0；由 PanelController.show 写入）
    var notchTopInset: CGFloat = 0

    /// 搜索框聚焦请求计数（面板打开时置焦点，保证键盘事件到达）
    var searchFocusRequest = 0

    // MARK: ⋮ 菜单 / 图片预览 / toast 状态

    /// ⋮ 菜单目标条目（nil = 菜单关闭）
    var moreMenuClip: Clip?
    /// ⋮ 按钮在面板坐标系中的锚点 frame（菜单弹出位置依据）
    var moreMenuAnchor: CGRect = .zero

    /// 正在放大查看的图片条目（nil = 预览关闭；仅图片类）
    var previewingClip: Clip?

    // MARK: 弹窗状态

    /// 当前打开的弹窗（nil = 无弹窗；面板内浮层，非系统 NSAlert）
    private(set) var activeDialog: PanelDialog?

    /// 弹窗输入：模板组名称（新建组 / 重命名 / 存入时当场新建共用）
    var groupNameInput: String = ""

    /// 弹窗输入：模板内容（新建模板；内容即条目，不命名）
    var templateContentInput: String = ""

    /// 存入模板组弹窗：选中的目标组 id（nil = 「＋ 新建模板组…」当场新建）
    var saveToGroupTargetId: UUID?

    /// 拖拽排序中的模板条目 id（nil = 未在拖拽）
    var draggingTemplateId: UUID?

    /// 模板行 ⋮ 菜单目标条目（nil = 菜单关闭）
    var templateMenuClip: Clip?
    /// 模板行 ⋮ 按钮在面板坐标系中的锚点 frame
    var templateMenuAnchor: CGRect = .zero

    /// 当前 toast（nil = 无 toast；默认 1.3s 自动消失，带动作按钮的 4s）
    private(set) var toast: Toast?
    /// toast 自动消失任务（新 toast 到来时取消旧任务）
    private var toastDismissTask: Task<Void, Never>?

    // MARK: 删除撤销

    /// 待删除条目（撤销窗口内条目仍在数据库、UI 已隐藏；窗口结束才真正落库删除）
    private var pendingDeletes: [UUID: Clip] = [:]
    /// 每条待删除条目的延迟提交任务（撤销时取消）
    private var pendingDeleteTasks: [UUID: Task<Void, Never>] = [:]
    /// 删除撤销窗口时长（toast 停留时长与延迟提交一致）
    private static let deleteUndoWindow: TimeInterval = 4

    // MARK: 数据快照

    /// 全部条目快照（每次 reload 重新 fetch，避免持有已删除模型导致渲染崩溃）
    private(set) var clips: [Clip] = []

    /// 全部模板组（sortIndex 升序；供 tab 行）
    private(set) var groups: [TemplateGroup] = []

    /// 数据门面与设置中心
    private let store = ClipboardStore.shared
    private let settings = SettingsStore.shared

    // MARK: 实时刷新

    /// 剪贴板历史变化监听 token（ClipboardMonitor 入库/置顶后广播）
    private var historyObserver: NSObjectProtocol?

    /// 监听历史变化：面板可见时实时 reload（新条目带动画滑入列表顶部）
    init() {
        historyObserver = Self.makeHistoryObserver(self)
    }

    deinit {
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
    }

    /// 历史变化观察者工厂（独立静态方法，避免 init 闭包直接捕获 self 的并发警告）
    private static func makeHistoryObserver(_ weakTarget: PanelViewModel) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .clipboardHistoryDidUpdate,
            object: nil,
            queue: .main
        ) { [weak weakTarget] _ in
            // 绑定为不可变值再进 Task，避免「捕获可变变量」的并发警告
            guard let target = weakTarget else { return }
            // queue: .main 不保证 MainActor 隔离，经 MainActor Task 派发
            Task { @MainActor in
                target.refreshIfVisible()
            }
        }
    }

    /// 面板可见时带动画刷新列表（复制新内容 → 0.5s 内滑入列表顶部）
    @MainActor
    private func refreshIfVisible() {
        guard PanelController.shared.isPanelVisible else { return }
        withAnimation(.snappy(duration: 0.3, extraBounce: 0.1)) {
            reload()
        }
    }

    // MARK: 数据加载

    /// 重新拉取数据（打开面板 / 删除条目后调用；待删除条目从快照中剔除，UI 即时隐藏）
    func reload() {
        let fetched = store.fetchAllClips()
        clips = pendingDeletes.isEmpty ? fetched : fetched.filter { pendingDeletes[$0.id] == nil }
        groups = store.fetchAllGroups()
    }

    /// 面板打开时恢复设置：tab 取 defaultTab、来源筛选按 rememberAppFilter 恢复、重置搜索与键盘选中
    func prepareForDisplay() {
        // 提交全部待删除条目（面板重开后不再保留撤销窗口）
        commitAllPendingDeletes()
        reload()
        selectedTab = PanelTab.fromSettings(settings.defaultTab)
        searchText = ""
        // rememberAppFilter 关闭时不恢复上次来源筛选
        selectedSourceFilter = settings.rememberAppFilter ? settings.lastSourceFilter : nil
        // 浮层状态复位（菜单 / 图片预览 / 弹窗 / toast / 浏览器选择浮层）
        moreMenuClip = nil
        previewingClip = nil
        activeDialog = nil
        templateMenuClip = nil
        draggingTemplateId = nil
        browserChooserClip = nil
        toast = nil
        toastDismissTask?.cancel()
        resetSelection()
        searchFocusRequest += 1
    }

    /// 面板关闭时持久化：rememberAppFilter 开启时保存当前来源筛选；待删除条目一并提交
    /// （toast 随面板消失、撤销入口不复存在）
    func persistOnHide() {
        commitAllPendingDeletes()
        if settings.rememberAppFilter {
            settings.lastSourceFilter = selectedSourceFilter
        }
    }

    // MARK: 过滤计算

    /// 当前 tab 是否为模板组 tab（此时来源条整体隐藏）
    var isGroupTab: Bool {
        if case .group = selectedTab { return true }
        return false
    }

    /// 当前选中的模板组（非组 tab 返回 nil）
    var currentGroup: TemplateGroup? {
        guard case .group(let id) = selectedTab else { return nil }
        return groups.first { $0.id == id }
    }

    /// 当前组 id（非组 tab 为 nil）
    var currentGroupId: UUID? {
        guard case .group(let id) = selectedTab else { return nil }
        return id
    }

    /// 当前组内模板条数（供模板 tab 底部「N 条」计数）
    var currentGroupTemplateCount: Int {
        guard let id = currentGroupId else { return 0 }
        return clips.filter { $0.groupId == id }.count
    }

    /// 来源条是否显示（开关开启且非模板组 tab；关闭时忽略来源过滤）
    var showsSourceBar: Bool {
        settings.enableAppFilter && !isGroupTab
    }

    /// 「录制已暂停」提示条是否显示
    var showsPausedBanner: Bool {
        !settings.recordingEnabled
    }

    /// 恢复剪贴板记录（暂停提示条「恢复」按钮）：写回开关即生效（监控引擎每次变化实时读取）
    func resumeRecording() {
        settings.recordingEnabled = true
        showToast("已恢复记录")
    }

    /// 过滤排序后的列表：
    /// 非模板条目（groupId == nil）+ Tab 类型过滤 + 搜索（preview/payloadText 包含，大小写不敏感）
    /// + 来源过滤（bundleId 相等或都是未知）；
    /// 排序：模板组 tab 按组内 sortIndex 升序（拖拽排序的持久化依据）；
    /// 其余 pinned 置顶（同组内时间降序）——
    /// - 最近复制优先（recent_copied）：按 createdAt 降序
    /// - 最近操作优先（recent_used）：按 max(createdAt, lastUsedAt) 降序（点击使用即置顶）
    var filteredClips: [Clip] {
        var result = tabAndSearchFiltered

        // 来源过滤（模板组 tab 不适用；开关关闭时忽略）
        if !isGroupTab, settings.enableAppFilter, let filter = selectedSourceFilter {
            result = result.filter { clip in
                if filter == Self.unknownSourceKey {
                    return clip.sourceBundleId == nil
                }
                return clip.sourceBundleId == filter
            }
        }

        // 排序：模板组 tab 按 sortIndex 升序；其余 pinned 置顶 + 按排序模式时间降序
        let groupTab = isGroupTab
        let recentUsedFirst = settings.sortMode == "recent_used"
        return result.sorted { a, b in
            if groupTab { return Self.templateOrder(a, b) }
            if a.pinned != b.pinned { return a.pinned }
            if recentUsedFirst { return Self.activityDate(a) > Self.activityDate(b) }
            return a.createdAt > b.createdAt
        }
    }

    /// Tab + 搜索过滤结果（不含来源过滤；供来源计数与「全部来源」总数）
    private var tabAndSearchFiltered: [Clip] {
        // Tab 类型过滤（模板组 tab 显示组内条目；其余显示非模板条目）
        var result: [Clip]
        switch selectedTab {
        case .all:
            result = clips.filter { $0.groupId == nil }
        case .text:
            result = clips.filter { $0.groupId == nil && $0.kindEnum == .text }
        case .image:
            result = clips.filter { $0.groupId == nil && $0.kindEnum == .image }
        case .link:
            result = clips.filter { $0.groupId == nil && $0.kindEnum == .link }
        case .group(let id):
            result = clips.filter { $0.groupId == id }
        }

        // 搜索：preview / payloadText 包含，大小写不敏感
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            result = result.filter { clip in
                clip.preview.localizedCaseInsensitiveContains(keyword)
                    || (clip.payloadText?.localizedCaseInsensitiveContains(keyword) ?? false)
            }
        }
        return result
    }

    /// 来源计数（当前 Tab+搜索条件下的来源条目；模板组 tab 时为空）
    var sourceCounts: [SourceCount] {
        guard showsSourceBar else { return [] }
        var counts: [String: (name: String, count: Int, iconPath: String?)] = [:]
        var order: [String] = []
        for clip in tabAndSearchFiltered {
            let key = clip.sourceBundleId ?? Self.unknownSourceKey
            if let existing = counts[key] {
                counts[key] = (existing.name, existing.count + 1, existing.iconPath)
            } else {
                counts[key] = (clip.sourceAppName ?? "未知来源", 1, clip.sourceIconPath)
                order.append(key)
            }
        }
        // 计数降序；同计数保持首次出现顺序
        return order.enumerated()
            .sorted { lhs, rhs in
                let l = counts[lhs.element]!, r = counts[rhs.element]!
                return l.count == r.count ? lhs.offset < rhs.offset : l.count > r.count
            }
            .map { _, key in
                let value = counts[key]!
                return SourceCount(key: key, name: value.name, count: value.count, iconPath: value.iconPath)
            }
    }

    /// 「全部来源」计数（当前 Tab+搜索条件下的总条数）
    var sourceTotal: Int {
        tabAndSearchFiltered.count
    }

    /// 是否完全没有历史（非模板条目为 0 → 大空态文案）
    var hasNoHistory: Bool {
        !clips.contains { $0.groupId == nil }
    }

    /// 面板高度相关状态指纹（列表规模 / 来源条与提示条显隐 / 模板组数量 / 模板 tab 底部操作区显隐变化时改变；
    /// 供 PanelController 观察并重算面板高度）
    var contentSizeRevision: Int {
        filteredClips.count &* 31
            &+ (showsSourceBar ? 1 : 0)
            &+ (showsPausedBanner ? 2 : 0)
            &+ (isGroupTab ? 4 : 0)
            &+ groups.count
    }

    /// 组内模板排序比较（sortIndex 升序；无值条目排后面并按 createdAt 新→旧回退）
    /// nonisolated：纯比较函数（只读模型快照字段），供 sorted(by:) 非隔离参数引用
    nonisolated private static func templateOrder(_ a: Clip, _ b: Clip) -> Bool {
        switch (a.sortIndex, b.sortIndex) {
        case let (lhs?, rhs?): return lhs < rhs
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.createdAt > b.createdAt
        }
    }

    /// 条目最近一次活动时间（「最近操作优先」排序依据）：
    /// max(createdAt, lastUsedAt)；从未被使用则回退复制时间
    /// nonisolated：纯比较函数（只读模型快照字段），供 sorted(by:) 非隔离参数引用
    nonisolated private static func activityDate(_ clip: Clip) -> Date {
        if let used = clip.lastUsedAt, used > clip.createdAt { return used }
        return clip.createdAt
    }

    // MARK: 动作

    /// 使用条目（点击行 / ⏎ / 模板点击共用）：按 pasteTarget 走「写剪贴板」或「直接粘贴到目标 App」
    /// - clipboard（默认，零权限）：写回剪贴板 → toast「已写入剪贴板」，面板保持展开（可连续取用多条）
    /// - app：需辅助功能授权；未授权自动回落 clipboard + toast；已授权写剪贴板 → 收面板 → 80ms 后向目标 App 发 ⌘V
    func use(clip: Clip) {
        let pasteTarget = settings.pasteTarget
        let eventName = clip.isTemplate ? EventLog.templateUsed : EventLog.itemUsed
        EventLog.track(eventName, ["kind": clip.kind, "paste_target": pasteTarget])

        // 记录使用时刻（「最近操作优先」模式下点击即置顶；带动画重排列表）
        withAnimation(.snappy(duration: 0.3, extraBounce: 0.1)) {
            store.markUsed(clip: clip)
        }
        // 默认流：写剪贴板 → toast「已写入剪贴板」→ 面板保持展开
        guard pasteTarget == "app" else {
            PasteboardWriter.write(clip: clip)
            showToast("已写入剪贴板", subtitle: toastSubtitle(for: clip))
            return
        }

        // app 流未授权辅助功能：自动回落 clipboard 模式（写剪贴板 + toast，面板保持展开）
        guard AutoPaster.isAuthorized() else {
            settings.pasteTarget = "clipboard"
            settings.accessibilityGranted = false
            EventLog.track(EventLog.autoPasteDenied, ["kind": clip.kind, "reason": "unauthorized"])
            PasteboardWriter.write(clip: clip)
            showToast("未授权，已写入剪贴板", subtitle: toastSubtitle(for: clip))
            return
        }
        settings.accessibilityGranted = true

        // 前台无有效粘贴目标（frontmost 为空或本 App）：降级 toast「已写入剪贴板，按 ⌘V 粘贴」，面板保持打开
        guard AutoPaster.hasValidPasteTarget() else {
            EventLog.track(EventLog.autoPasteDenied, ["kind": clip.kind, "reason": "no_target"])
            PasteboardWriter.write(clip: clip)
            showToast("已写入剪贴板", subtitle: "按 ⌘V 粘贴")
            return
        }

        // 已授权：内容先进剪贴板 → 收面板 → 延迟 80ms（等面板收起、焦点回到目标 App）→ 发 ⌘V
        PasteboardWriter.write(clip: clip)
        PanelController.shared.hide()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            if !AutoPaster.pasteToFocusedApp() {
                // 极端竞态（目标 App 在延迟期间退出等）：事件记录即可，面板已在收起动画中
                EventLog.track(EventLog.autoPasteDenied, ["kind": clip.kind, "reason": "send_failed"])
            }
        }
    }

    // MARK: 链接跳转

    /// 打开条目链接（行内「打开链接」按钮；kind: menu / inline / hotkey）：
    /// 链接类打开整串 URL；文本类打开首个 http(s) 链接；其他类型忽略。面板不收起（可连续开多个）
    func openLink(clip: Clip, kind: String) {
        guard let url = Self.openableURL(in: clip) else { return }
        open(url: url, browserBundleId: nil, kind: kind)
    }

    /// 用指定浏览器打开条目链接（⌥ 浏览器选择浮层点选；bundleId nil = 跟随系统默认浏览器）
    func openLink(clip: Clip, browserBundleId: String?, kind: String) {
        guard let url = Self.openableURL(in: clip) else { return }
        open(url: url, browserBundleId: browserBundleId, kind: kind)
    }

    /// 链接打开落地：显式指定浏览器（⌥ 浮层）> defaultBrowser 设置 > 系统默认；
    /// 目标浏览器未安装时回退系统默认打开；记 linkOpened（面板保持展开）
    private func open(url: URL, browserBundleId: String?, kind: String) {
        EventLog.track(EventLog.linkOpened, ["kind": kind])
        let target = browserBundleId ?? (settings.defaultBrowser == "system" ? nil : settings.defaultBrowser)
        if let target,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
            let configuration = NSWorkspace.OpenConfiguration()
            Task { try? await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// 条目可打开的 http(s) URL：链接类取 payloadText 整串；文本类取全文首个链接；其他类型 nil
    static func openableURL(in clip: Clip) -> URL? {
        if clip.kindEnum == .link {
            return httpURL(clip.payloadText ?? clip.preview)
        }
        guard clip.kindEnum == .text, let text = clip.payloadText else { return nil }
        return firstURL(in: text)
    }

    /// 字符串整体是否为合法 http/https URL（scheme 限定，防御 file: / 其他 scheme 一键打开）
    static func httpURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// 文本中首个 http(s) URL（简单正则匹配 + 剔除尾部标点；找不到返回 nil）
    static func firstURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = urlRegex.firstMatch(in: text, range: range),
              let raw = Range(match.range, in: text) else { return nil }
        // 尾部常见标点（句末逗号句号、右括号引号等，含中文全角标点）不属于 URL
        let candidate = String(text[raw])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?…)]}\"'»›），。；：！？】》」』"))
        return httpURL(candidate)
    }

    /// http(s) URL 简单匹配正则（编译一次复用）
    private static let urlRegex = try! NSRegularExpression(pattern: "https?://[^\\s]+")

    // MARK: 浏览器选择浮层（⌥ 点「打开链接」）

    /// 浏览器选择浮层目标条目（nil = 浮层关闭）
    var browserChooserClip: Clip?
    /// 浏览器选择浮层锚点（「打开链接」按钮在面板坐标系中的 frame）
    var browserChooserAnchor: CGRect = .zero

    /// 打开浏览器选择浮层（⌥ 点「打开链接」触发；记录目标条目与按钮锚点 frame）
    func openBrowserChooser(clip: Clip, anchor: CGRect) {
        browserChooserClip = clip
        browserChooserAnchor = anchor
    }

    /// 关闭浏览器选择浮层
    func closeBrowserChooser() {
        browserChooserClip = nil
    }

    /// 删除条目（⌫ / 行内菜单删除；不弹确认，toast 内 4s 可撤销）
    func delete(clip: Clip) {
        EventLog.track(EventLog.clipDeleted, ["kind": clip.kind])
        beginPendingDelete(clip)
    }

    /// 置顶切换：翻转 pinned + 持久化（SwiftData 显式 save）+ 列表重排（pinned 置顶已有）+ 选中跟随
    func togglePin(clip: Clip) {
        store.togglePin(clip: clip)
        EventLog.track(EventLog.pinToggled, ["kind": clip.kind, "pinned": clip.pinned ? "true" : "false"])
        reload()
        // 键盘选中跟随该条目（置顶后跳到列表顶部，取消固定后回到时间序位置）
        selectionIndex = filteredClips.firstIndex(where: { $0.id == clip.id })
    }

    /// 无格式复制（仅文本类）：纯文本写回剪贴板（prepareForNewContents 清空富文本类型，
    /// 只声明 .string，富文本剥离天然成立）+ 防自吞 + toast 轻提示
    func copyPlainText(clip: Clip) {
        guard clip.kindEnum == .text, let text = clip.payloadText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents()
        pasteboard.setString(text, forType: .string)
        ClipboardMonitor.shared.markExternalWrite()
        EventLog.track(EventLog.plainCopyUsed, ["kind": clip.kind])
        showToast("已无格式写入", subtitle: toastSubtitle(for: clip))
    }

    /// 请求存入模板组（菜单「存入模板组…」/ ⌘G 等价入口）：打开弹窗，
    /// 默认选中第一个已有组（无组时默认「＋ 新建模板组…」）
    func requestSaveToGroup(clip: Clip) {
        saveToGroupTargetId = groups.first?.id
        groupNameInput = ""
        activeDialog = .saveToGroup(clip.id)
    }

    // MARK: 弹窗动作

    /// 取消当前弹窗（esc / 取消按钮 / 点遮罩）
    func cancelDialog() {
        activeDialog = nil
    }

    /// 打开「退出确认」弹窗（头部 ⏻ 按钮触发）
    func showQuitConfirm() {
        activeDialog = .quitConfirm
    }

    /// 确认退出：终止应用（历史记录保留本机，下次启动照常读取）
    func confirmQuit() {
        NSApplication.shared.terminate(nil)
    }

    /// 打开「新建模板组」弹窗（标签行「＋」触发）
    func showNewGroupDialog() {
        groupNameInput = ""
        activeDialog = .newGroup
    }

    /// 确认新建模板组：创建 → 追加到标签行末尾（sortIndex 最大 +1）→ 自动切换到新 tab
    func confirmNewGroup() {
        let name = groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let group = store.createGroup(name: name)
        EventLog.track(EventLog.groupCreated, ["name": name])
        groupNameInput = ""
        activeDialog = nil
        reload()
        selectedTab = .group(group.id)
    }

    /// 打开「新建模板」弹窗（模板 tab 底部「＋ 新建模板」触发；归属即当前组）
    func showNewTemplateDialog() {
        guard let groupId = currentGroupId else { return }
        templateContentInput = ""
        activeDialog = .newTemplate(groupId)
    }

    /// 确认新建模板：内容即条目（不命名）
    func confirmNewTemplate() {
        guard case .newTemplate(let groupId) = activeDialog else { return }
        let content = templateContentInput
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.addTemplate(text: content, groupId: groupId)
        templateContentInput = ""
        activeDialog = nil
        reload()
        resetSelection()
    }

    /// 确认存入模板组：目标组可选已有或当场新建；以该历史条目内容复制出一条模板
    func confirmSaveToGroup() {
        guard case .saveToGroup(let clipId) = activeDialog,
              let clip = clips.first(where: { $0.id == clipId }) else { return }
        // 解析目标组：已有组直接用；选了「＋ 新建模板组…」则当场创建
        var targetId = saveToGroupTargetId
        if targetId == nil {
            let name = groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let group = store.createGroup(name: name)
            targetId = group.id
            EventLog.track(EventLog.groupCreated, ["name": name])
        }
        guard let groupId = targetId else { return }
        store.addTemplate(copying: clip, groupId: groupId)
        EventLog.track(EventLog.itemToGroup, ["kind": clip.kind])
        groupNameInput = ""
        activeDialog = nil
        reload()
        let groupName = groups.first { $0.id == groupId }?.name ?? ""
        showToast("已存入模板组", subtitle: groupName)
    }

    /// 打开「重命名模板组」弹窗（预填旧名）
    func showRenameGroupDialog() {
        guard let group = currentGroup else { return }
        groupNameInput = group.name
        activeDialog = .renameGroup(group.id)
    }

    /// 确认重命名模板组
    func confirmRenameGroup() {
        guard case .renameGroup(let groupId) = activeDialog,
              let group = groups.first(where: { $0.id == groupId }) else { return }
        let name = groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if name != group.name {
            store.renameGroup(group, to: name)
            reload()
        }
        groupNameInput = ""
        activeDialog = nil
    }

    /// 打开「删除模板组」确认弹窗（组内模板一并删除）
    func showDeleteGroupDialog() {
        guard let group = currentGroup else { return }
        activeDialog = .deleteGroup(group.id)
    }

    /// 确认删除模板组：组内模板条目连同文件一并删除，切回「全部」tab
    func confirmDeleteGroup() {
        guard case .deleteGroup(let groupId) = activeDialog,
              let group = groups.first(where: { $0.id == groupId }) else { return }
        store.deleteGroup(group)
        groupNameInput = ""
        activeDialog = nil
        if case .group(let selectedId) = selectedTab, selectedId == groupId {
            selectedTab = .all
        }
        reload()
    }

    // MARK: 模板行 ⋮ 菜单

    /// 打开模板行 ⋮ 菜单（记录目标条目与按钮锚点 frame）
    func openTemplateMenu(clip: Clip, anchor: CGRect) {
        templateMenuClip = clip
        templateMenuAnchor = anchor
    }

    /// 关闭模板行 ⋮ 菜单
    func closeTemplateMenu() {
        templateMenuClip = nil
    }

    /// 复制模板内容（文本写回剪贴板；图片类走已有图片复制链路）+ 防自吞 + toast
    func copyTemplate(clip: Clip) {
        if clip.kindEnum == .image {
            copyPreviewImage(clip: clip)
            return
        }
        guard let text = clip.payloadText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents()
        pasteboard.setString(text, forType: .string)
        ClipboardMonitor.shared.markExternalWrite()
        EventLog.track(EventLog.plainCopyUsed, ["kind": clip.kind])
        showToast("已写入剪贴板", subtitle: toastSubtitle(for: clip))
    }

    /// 删除模板条目（只删该条模板，不动历史；同样走待删除 + 撤销机制）
    func deleteTemplate(clip: Clip) {
        EventLog.track(EventLog.clipDeleted, ["kind": clip.kind])
        beginPendingDelete(clip)
    }

    // MARK: 删除撤销

    /// 进入待删除状态：列表立即隐藏 + 撤销 toast + 延迟提交（窗口结束才真正落库删除，连带图片文件）
    private func beginPendingDelete(_ clip: Clip) {
        // 重复触发（同一 toast 窗口内再次删除同一条目）直接忽略
        guard pendingDeletes[clip.id] == nil else { return }
        pendingDeletes[clip.id] = clip
        reload()
        // 修正键盘选中下标（越界时收敛到列表末端）
        let count = filteredClips.count
        if count == 0 {
            selectionIndex = nil
        } else {
            selectionIndex = min(selectionIndex ?? 0, count - 1)
        }
        showToast(
            "已删除",
            subtitle: toastSubtitle(for: clip),
            duration: Self.deleteUndoWindow,
            actionTitle: "撤销"
        ) { [weak self] in
            self?.undoDelete(clipId: clip.id)
        }
        pendingDeleteTasks[clip.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.deleteUndoWindow))
            guard !Task.isCancelled else { return }
            self?.commitDelete(clipId: clip.id)
        }
    }

    /// 撤销删除：条目从未真正落库删除，恢复展示、选中跟随，轻提示确认
    func undoDelete(clipId: UUID) {
        pendingDeleteTasks.removeValue(forKey: clipId)?.cancel()
        guard pendingDeletes.removeValue(forKey: clipId) != nil else { return }
        reload()
        selectionIndex = filteredClips.firstIndex(where: { $0.id == clipId })
        showToast("已恢复")
    }

    /// 提交单条删除（撤销窗口结束）：真正落库删除；UI 无变化（条目此前已隐藏）
    private func commitDelete(clipId: UUID) {
        pendingDeleteTasks.removeValue(forKey: clipId)
        guard let clip = pendingDeletes.removeValue(forKey: clipId) else { return }
        store.delete(clip: clip)
    }

    /// 提交全部待删除条目（面板隐藏 / 重新展示等撤销入口消失的时机）
    private func commitAllPendingDeletes() {
        guard !pendingDeletes.isEmpty else { return }
        for id in pendingDeletes.keys {
            pendingDeleteTasks.removeValue(forKey: id)?.cancel()
        }
        let clips = pendingDeletes.values
        pendingDeletes.removeAll()
        for clip in clips {
            store.delete(clip: clip)
        }
    }

    // MARK: 模板拖拽排序

    /// 拖拽进入目标行：把拖拽条目移动到目标位置（仅内存重写 sortIndex，松手才持久化）
    func dragTemplateEntered(target: Clip) {
        guard let draggingId = draggingTemplateId,
              draggingId != target.id,
              let dragging = clips.first(where: { $0.id == draggingId }),
              case .group(let groupId) = selectedTab else { return }
        // 以全量组内列表为基准移动（搜索过滤时拖拽仍按全量顺序重排）
        var ordered = clips.filter { $0.groupId == groupId }.sorted(by: Self.templateOrder)
        guard let from = ordered.firstIndex(where: { $0.id == dragging.id }),
              let to = ordered.firstIndex(where: { $0.id == target.id }),
              from != to else { return }
        ordered.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.easeOut(duration: 0.15)) {
            for (index, clip) in ordered.enumerated() {
                clip.sortIndex = index
            }
        }
    }

    /// 拖拽松手：按当前组内展示顺序持久化 sortIndex
    func dragTemplateEnded() {
        defer { draggingTemplateId = nil }
        guard case .group(let groupId) = selectedTab else { return }
        store.reorderTemplates(clips.filter { $0.groupId == groupId }.sorted(by: Self.templateOrder))
        reload()
    }

    /// 打开 ⋮ 菜单（记录目标条目与按钮锚点 frame）
    func openMoreMenu(clip: Clip, anchor: CGRect) {
        moreMenuClip = clip
        moreMenuAnchor = anchor
    }

    /// 关闭 ⋮ 菜单
    func closeMoreMenu() {
        moreMenuClip = nil
    }

    /// 打开图片放大查看（仅图片类；esc / 点遮罩 / 关闭按钮关闭）
    func openPreview(clip: Clip) {
        guard clip.kindEnum == .image else { return }
        previewingClip = clip
        EventLog.track(EventLog.imageViewed, ["kind": clip.kind])
    }

    /// 关闭图片放大查看
    func closePreview() {
        previewingClip = nil
    }

    /// 浮层拆除代次（自愈机制）：PanelView 监测 overlayStateFlags 归空后调用调度，
    /// 0.7s 后（移除 transition 应已结束）递增——浮层容器以 .id(overlayTeardownToken) 挂载，
    /// 身份变化强制 SwiftUI 拆除整个浮层子树。移除 transition 偶发卡住时视图会残留
    /// 在树中（不可见但全尺寸遮罩吞点击，重开面板才恢复），代次递增保证残留被彻底拆除
    var overlayTeardownToken = 0
    /// 拆除调度任务
    private var overlayTeardownTask: Task<Void, Never>?

    /// 调度浮层强制拆除（所有浮层归空 0.7s 后执行；期间有浮层打开则放弃本次，避免打断展示）
    func scheduleOverlayTeardown() {
        overlayTeardownTask?.cancel()
        overlayTeardownTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            guard moreMenuClip == nil, templateMenuClip == nil, browserChooserClip == nil,
                  previewingClip == nil, activeDialog == nil, toast == nil else { return }
            overlayTeardownToken &+= 1
        }
    }

    /// 复制图片（预览内）：原图数据写回剪贴板（TIFF 标准类型 + PNG 原始数据）+ 防自吞
    func copyPreviewImage(clip: Clip) {
        guard let ref = clip.payloadRef,
              ImageStore.shared.hasOriginal(name: ref),
              let data = try? Data(contentsOf: ImageStore.shared.fileURL(name: ref)) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents()
        // TIFF 是 macOS 剪贴板最兼容的图片类型；PNG 原图数据额外声明（PasteboardReader 检测 .png 时直接命中）
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        if clip.format?.uppercased() == "PNG" {
            pasteboard.setData(data, forType: .png)
        }
        ClipboardMonitor.shared.markExternalWrite()
        EventLog.track(EventLog.plainCopyUsed, ["kind": clip.kind])
        showToast("已写入剪贴板", subtitle: toastSubtitle(for: clip))
    }

    /// 切换来源筛选（再点一次取消；供来源条与行内来源标签）
    func selectSource(_ key: String?) {
        selectedSourceFilter = (selectedSourceFilter == key) ? nil : key
        if selectedSourceFilter != nil {
            EventLog.track(EventLog.appFilterUsed, ["source": selectedSourceFilter ?? ""])
        }
    }

    // MARK: toast

    /// 显示 toast 轻提示（面板顶部自动消失；新提示覆盖旧提示）
    /// - Parameters:
    ///   - duration: 自动消失时长（默认 1.3s；带撤销动作的删除提示为 4s）
    ///   - actionTitle / action: 可选动作按钮（如删除后「撤销」；按钮点击才触发，自动消失不触发）
    func showToast(
        _ title: String,
        subtitle: String? = nil,
        duration: TimeInterval = 1.3,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        toast = Toast(title: title, subtitle: subtitle, actionTitle: actionTitle, action: action)
        toastDismissTask?.cancel()
        // 必须 @MainActor：本类未隔离，裸 Task 会跑在后台线程，
        // 后台线程修改 SwiftUI 观察的状态会破坏视图/手势系统（表现为按钮突然全部无响应）
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// 诊断用：当前浮层状态标记（M=更多菜单 T=模板菜单 B=浏览器选择 P=图片预览
    /// D=弹窗 o=toast g=模板拖拽中；空串 = 全部关闭）。
    /// 随每次点击投递日志输出 + PanelView onChange 记录状态迁移，
    /// 用于定位「点击投递到窗口但无动作」时是哪个浮层状态在拦截
    var overlayStateFlags: String {
        var flags = ""
        if moreMenuClip != nil { flags += "M" }
        if templateMenuClip != nil { flags += "T" }
        if browserChooserClip != nil { flags += "B" }
        if previewingClip != nil { flags += "P" }
        if activeDialog != nil { flags += "D" }
        if toast != nil { flags += "o" }
        if draggingTemplateId != nil { flags += "g" }
        return flags
    }

    /// 生成 toast 副标题：条目预览截断，最长 40 字符
    private func toastSubtitle(for clip: Clip) -> String {
        let text = clip.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 40
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "…"
        }
        return text.isEmpty ? clip.kindEnum.kindLabel : text
    }

    // MARK: 键盘导航

    /// 上下移动键盘选中（滚动跟随由视图层 scrollTo 实现）
    func moveSelection(_ delta: Int) {
        let count = filteredClips.count
        guard count > 0 else { return }
        let current = selectionIndex ?? 0
        selectionIndex = min(max(current + delta, 0), count - 1)
    }

    /// 使用键盘选中条目（⏎）
    func useSelected() {
        guard let index = selectionIndex, filteredClips.indices.contains(index) else { return }
        use(clip: filteredClips[index])
    }

    /// 删除键盘选中条目（⌫）
    func deleteSelected() {
        guard let index = selectionIndex, filteredClips.indices.contains(index) else { return }
        delete(clip: filteredClips[index])
    }

    // MARK: 私有

    /// 重置键盘选中（筛选状态变化后回到首行）
    private func resetSelection() {
        selectionIndex = filteredClips.isEmpty ? nil : 0
    }
}
