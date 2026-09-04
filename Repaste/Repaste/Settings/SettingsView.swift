//
//  SettingsView.swift
//  Repaste
//
//  设置窗口（独立窗口）：左侧分类导航（常规 / 呼出 / 历史与隐私）+ 右侧分组卡片；
//  全部改动直改 SettingsStore 即时生效（无保存按钮）；哑光纯黑自绘控件（无系统绿 Toggle / 无 NSAlert）
//

import SwiftUI
import AppKit
import Observation
import Carbon.HIToolbox
import Combine
import UniformTypeIdentifiers

// MARK: - 分类定义

/// 设置分类
enum SettingsSection: String, CaseIterable, Identifiable {
    /// 常规
    case general = "常规"
    /// 呼出
    case summon = "呼出"
    /// 历史与隐私
    case history = "历史与隐私"

    var id: String { rawValue }

    /// 侧栏图标
    var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .summon: return "cursorarrow.and.square.on.square.dashed"
        case .history: return "lock.shield"
        }
    }

    /// 分类标题下的一句描述
    var subtitle: String {
        switch self {
        case .general: return "启动、面板、粘贴去向与链接行为，改动即时生效。"
        case .summon: return "刘海悬停、灵敏度与快捷键。"
        case .history: return "保留策略、隐私保护与本地存储，全部只存本机。"
        }
    }
}

// MARK: - 确认弹窗中心

/// 设置窗口确认弹窗状态：卡片触发、根视图统一渲染。
/// 弹窗浮层挂在设置窗口根视图上（覆盖侧栏与内容区），弹窗天然位于窗口正中（同面板弹窗模式）
@Observable
final class SettingsDialogCenter {
    /// 弹窗种类
    enum Dialog: Equatable {
        case none
        /// 辅助功能授权引导（粘贴目标）
        case auth
        /// 清空历史确认
        case clearHistory
        /// 清空图片确认
        case clearImages
    }

    /// 当前弹窗
    var active: Dialog = .none

    /// 已选「到正在使用的应用」但尚未授权（等待授权中；单选保持选中 + 回退标注）
    var pendingAppTarget = false

    static let shared = SettingsDialogCenter()

    private init() {}

    /// 弹出确认浮层
    func present(_ dialog: Dialog) {
        active = dialog
    }

    /// 确认路径关闭浮层（不触发取消回落）
    func dismiss() {
        active = .none
    }

    /// 取消当前浮层（遮罩点击 / 取消按钮统一走这里；授权弹窗取消回落「到剪贴板」）
    func cancel() {
        if active == .auth { pendingAppTarget = false }
        active = .none
    }
}

// MARK: - 设置窗口主视图

/// 设置窗口主视图：左分类导航 + 右内容区（分类标题 + 分组卡片）
struct SettingsView: View {
    /// 当前选中分类
    @State private var selection: SettingsSection = .general
    /// 确认弹窗中心（卡片触发、根视图统一渲染）
    private let dialogs = SettingsDialogCenter.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(minWidth: 680, minHeight: 460)
        .preferredColorScheme(.dark)
        // 确认弹窗浮层（盖住整个设置窗口，弹窗在窗口正中）
        .overlay {
            dialogOverlay
                .animation(.easeOut(duration: 0.15), value: dialogs.active == .none)
        }
        .background(
            // esc 关闭窗口（隐藏按钮承载 cancelAction 快捷键；红绿灯标题栏由系统保留）
            Button("") { NSApp.keyWindow?.close() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        )
    }

    // MARK: 确认弹窗浮层

    /// 确认浮层：半透明遮罩（点击取消）+ 窗口正中圆角卡片
    @ViewBuilder
    private var dialogOverlay: some View {
        if dialogs.active != .none {
            ZStack {
                Color.black.opacity(0.52)
                    .onTapGesture { dialogs.cancel() }
                dialogCard
            }
            .transition(.opacity)
        }
    }

    /// 按弹窗种类分发内容卡片
    @ViewBuilder
    private var dialogCard: some View {
        switch dialogs.active {
        case .none:
            EmptyView()
        case .auth:
            PanelDialogCard(
                title: "需要辅助功能授权",
                subtitle: "需要你在系统设置中为 Repaste 开启辅助功能，才能直接粘贴到正在使用的应用。",
                cancelTitle: "暂不",
                confirmTitle: "去授权",
                onCancel: {
                    // 暂不：回落「到剪贴板」
                    dialogs.cancel()
                },
                onConfirm: {
                    // 弹系统授权引导；pendingAppTarget 保持，授权回来后（窗口激活复核）自动生效
                    dialogs.dismiss()
                    AutoPaster.requestAuthorization()
                }
            ) { EmptyView() }
        case .clearHistory:
            PanelDialogCard(
                title: "清空历史",
                subtitle: "清空后无法恢复，模板组内容会保留。",
                cancelTitle: "取消",
                confirmTitle: "清空",
                confirmColor: DT.danger,
                onCancel: { dialogs.cancel() },
                onConfirm: {
                    dialogs.dismiss()
                    ClipboardStore.shared.clearHistory()
                }
            ) { EmptyView() }
        case .clearImages:
            PanelDialogCard(
                title: "清空图片",
                subtitle: "将删除全部图片条目与原图文件（模板内图片一并删除），无法恢复。",
                cancelTitle: "取消",
                confirmTitle: "清空",
                confirmColor: DT.danger,
                onCancel: { dialogs.cancel() },
                onConfirm: {
                    dialogs.dismiss()
                    ClipboardStore.shared.clearImages()
                }
            ) { EmptyView() }
        }
    }

    // MARK: 左侧分类导航

    /// 侧栏：宽度自适应内容（仅保留文字两侧必要间距）、surface2 底、右缘 1px 分隔线；选中项 = 白底黑字左对齐胶囊
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSection.allCases) { section in
                sidebarItem(section)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DT.surface2)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DT.stroke).frame(width: 1)
        }
    }

    /// 单个分类导航项：icon + 文字 13pt；选中 = 白底黑字胶囊（水平 12 / 垂直 8）
    private func sidebarItem(_ section: SettingsSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? DT.panel : DT.muted)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DT.panel : DT.fg)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // 所有项撑满侧栏宽度（= 最长项「历史与隐私」的宽度），统一点击区域与选中胶囊尺寸
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(isSelected ? Color.white : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.mattePress)
    }

    // MARK: 右侧内容区

    /// 内容区：#0A0A0A 底、分类标题 16pt + 描述 13pt + 分组卡片（可滚动）
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DT.fgStrong)
                    Text(selection.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(DT.muted)
                }
                sectionCards
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 滚动视口坐标空间（下拉向上/向下展开的翻转判断依据）
        .coordinateSpace(name: "settings-scroll")
        .background(DT.panel)
    }

    /// 当前分类的卡片列表
    @ViewBuilder
    private var sectionCards: some View {
        switch selection {
        case .general: GeneralSettingsCards()
        case .summon: SummonSettingsCards()
        case .history: HistorySettingsCards()
        }
    }
}

// MARK: - 常规分类

/// 常规分类：启动 / 面板 / 粘贴 / 链接 四张卡片
struct GeneralSettingsCards: View {
    @Bindable private var settings = SettingsStore.shared

    /// 默认浏览器候选（跟随系统 + 已安装的常见浏览器；窗口激活时复核）
    @State private var browserOptions: [PickerOption] = Self.loadBrowserOptions()

    var body: some View {
        VStack(spacing: 12) {
            // 启动
            SettingsGroupCard(title: "启动") {
                SettingsRow(title: "启动时读取剪贴板", subtitle: "打开应用时立即导入当前剪贴板内容") {
                    MatteToggle(isOn: settings.readClipboardOnLaunch) {
                        settings.readClipboardOnLaunch.toggle()
                    }
                }
            }

            // 面板
            SettingsGroupCard(title: "面板") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsRow(title: "打开历史时默认显示") {
                        SettingsPicker(
                            options: [
                                PickerOption("all", "全部"),
                                PickerOption("text", "文本"),
                                PickerOption("image", "图片"),
                                PickerOption("link", "链接"),
                            ],
                            selection: $settings.defaultTab
                        )
                    }
                    SettingsRow(title: "来源应用筛选", subtitle: "面板顶部显示来源筛选条") {
                        MatteToggle(isOn: settings.enableAppFilter) {
                            settings.enableAppFilter.toggle()
                        }
                    }
                    SettingsRow(title: "记住上次来源筛选", subtitle: "关闭则每次打开都回到「全部来源」") {
                        MatteToggle(isOn: settings.rememberAppFilter) {
                            settings.rememberAppFilter.toggle()
                        }
                    }
                }
            }

            // 排序：主面板历史列表的排序模式（单选，即时生效）
            SettingsGroupCard(title: "排序", subtitle: "主面板历史列表的排列方式，改动即时生效") {
                VStack(alignment: .leading, spacing: 14) {
                    PasteTargetRow(
                        title: "最近复制优先",
                        subtitle: "仅按内容的原始复制时间排序，最近复制的排在最上面。",
                        isSelected: settings.sortMode == "recent_copied"
                    ) {
                        settings.sortMode = "recent_copied"
                    }
                    PasteTargetRow(
                        title: "最近操作优先",
                        subtitle: "复制与点击使用都会刷新位置，最近一次操作的排在最上面。",
                        isSelected: settings.sortMode == "recent_used"
                    ) {
                        settings.sortMode = "recent_used"
                    }
                }
            }

            // 粘贴（含辅助功能授权引导与回落）
            PasteTargetCard()

            // 链接
            SettingsGroupCard(title: "链接") {
                SettingsRow(title: "默认浏览器", subtitle: "按住 ⌥ 点「打开链接」可临时更换") {
                    SettingsPicker(options: browserOptions, selection: $settings.defaultBrowser)
                }
            }
        }
        .onAppear { browserOptions = Self.loadBrowserOptions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 窗口重新激活时复核已安装浏览器（新装浏览器即时出现在列表）
            browserOptions = Self.loadBrowserOptions()
        }
    }

    /// 跟随系统 + 已安装的常见浏览器（复用 BrowserChooserMenu 的 NSWorkspace 安装检测）
    private static func loadBrowserOptions() -> [PickerOption] {
        BrowserChooserMenu.options().map { PickerOption($0.bundleId ?? "system", $0.name) }
    }
}

// MARK: - 粘贴目标卡片（授权引导 + 回落）

/// 粘贴目标卡片：两个圆形单选（到剪贴板 / 到正在使用的应用）。
/// 选「到正在使用的应用」需辅助功能授权：未授权先弹引导浮层（去授权 / 暂不回落）；
/// 授权检测时机 = 选中的当下 + 窗口重新激活时（didBecomeActive）复核；
/// 未授权期间该项保持视觉选中并标注「未授权，当前回退到剪贴板」，pasteTarget 实际保持 "clipboard"。
struct PasteTargetCard: View {
    @Bindable private var settings = SettingsStore.shared
    /// 确认弹窗中心（授权引导浮层由设置窗口根部渲染）
    private let dialogs = SettingsDialogCenter.shared

    /// 辅助功能授权状态（选中当下与窗口重新激活时复核）
    @State private var axAuthorized = AutoPaster.isAuthorized()

    var body: some View {
        SettingsGroupCard(title: "粘贴", subtitle: "选择使用条目时的粘贴去向，改动即时生效") {
            VStack(alignment: .leading, spacing: 14) {
                PasteTargetRow(
                    title: "到剪贴板",
                    subtitle: "复制选中项至系统剪贴板，后续使用时手动粘贴。",
                    isSelected: selectedTarget == "clipboard"
                ) {
                    selectClipboard()
                }
                PasteTargetRow(
                    title: "到正在使用的应用",
                    subtitle: "将选中项直接粘贴至你正在使用的应用中。",
                    isSelected: selectedTarget == "app",
                    fallbackNote: dialogs.pendingAppTarget && !axAuthorized ? "未授权，当前回退到剪贴板" : nil
                ) {
                    selectApp()
                }
            }
        }
        .onAppear { refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 从系统设置授权回来：复核授权状态，待定选择自动生效
            refreshAuthorization()
        }
    }

    /// 单选选中态：授权前「到正在使用的应用」保持视觉选中（pasteTarget 仍为 clipboard）
    private var selectedTarget: String {
        if settings.pasteTarget == "app" { return "app" }
        if dialogs.pendingAppTarget && !axAuthorized { return "app" }
        return "clipboard"
    }

    // MARK: 动作

    /// 选「到剪贴板」：直接提交
    private func selectClipboard() {
        dialogs.pendingAppTarget = false
        if settings.pasteTarget != "clipboard" {
            settings.pasteTarget = "clipboard"
            EventLog.track(EventLog.pasteTargetChanged, ["to": "clipboard"])
        }
    }

    /// 选「到正在使用的应用」：已授权直接提交；未授权弹引导浮层（不提交）
    private func selectApp() {
        if AutoPaster.isAuthorized() {
            commitAppTarget()
        } else {
            dialogs.pendingAppTarget = true
            dialogs.present(.auth)
        }
    }

    /// 提交「到正在使用的应用」（已授权）
    private func commitAppTarget() {
        dialogs.pendingAppTarget = false
        axAuthorized = true
        settings.accessibilityGranted = true
        if settings.pasteTarget != "app" {
            settings.pasteTarget = "app"
            EventLog.track(EventLog.pasteTargetChanged, ["to": "app"])
        }
    }

    /// 授权复核（选中当下 + 窗口重新激活时）：授权成功 → 待定选择生效；
    /// 已存 "app" 但授权被系统撤销 → 回落 clipboard 并保持标注
    private func refreshAuthorization() {
        let authorized = AutoPaster.isAuthorized()
        axAuthorized = authorized
        if authorized {
            settings.accessibilityGranted = true
            if dialogs.pendingAppTarget { commitAppTarget() }
        } else if settings.pasteTarget == "app" {
            settings.pasteTarget = "clipboard"
            settings.accessibilityGranted = false
            dialogs.pendingAppTarget = true
        }
    }
}

/// 通用单选行（粘贴目标 / 排序模式共用）：圆形单选 + 标题 + 说明（可附未授权回退标注小字）
struct PasteTargetRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    /// 未授权回退标注（仅「到正在使用的应用」等待授权期间传入）
    var fallbackNote: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                RadioCircle(isSelected: isSelected)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(DT.fg)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DT.muted)
                    if let fallbackNote {
                        Text(fallbackNote)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DT.warnText)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.mattePress)
    }
}

// MARK: - 呼出分类

/// 呼出分类：刘海悬停 / 抑制 / 快捷键 三张卡片
struct SummonSettingsCards: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 12) {
            // 刘海悬停
            SettingsGroupCard(title: "刘海悬停") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsRow(title: "刘海悬停呼出") {
                        MatteToggle(isOn: settings.hoverEnabled) {
                            // 关闭时 hover_disabled 事件由 HotZoneWatcher 动态卸载监听时统一记录
                            settings.hoverEnabled.toggle()
                        }
                    }
                    SettingsRow(title: "灵敏度") {
                        SettingsPicker(
                            options: [
                                PickerOption("sensitive", "敏感 50ms"),
                                PickerOption("default", "默认 100ms"),
                                PickerOption("slow", "迟缓 250ms"),
                            ],
                            selection: $settings.hoverSensitivity
                        )
                    }
                }
            }

            // 抑制
            SettingsGroupCard(title: "抑制") {
                SettingsRow(title: "全屏时不触发", subtitle: "前台应用全屏时暂停刘海悬停呼出") {
                    MatteToggle(isOn: settings.suppressFullscreen) {
                        settings.suppressFullscreen.toggle()
                    }
                }
            }

            // 快捷键
            SettingsGroupCard(title: "快捷键") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsRow(title: "呼出快捷键") {
                        ShortcutCaptureButton()
                    }
                    // 面板操作静态说明（等宽小字）
                    VStack(alignment: .leading, spacing: 5) {
                        Text("面板操作")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DT.muted)
                        Text("↑↓ 选择 · ⏎ 粘贴 · ⌘⏎ 打开链接 · ⌘G 存入模板组 · esc 关闭")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DT.muted2)
                    }
                }
            }
        }
    }
}

// MARK: - 历史与隐私分类

/// 历史与隐私分类：历史 / 隐私 / 存储 三张卡片
struct HistorySettingsCards: View {
    private let settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 12) {
            // 历史：保留条数 + 图片保留天数
            SettingsGroupCard(title: "历史") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsRow(title: "保留条数") {
                        SettingsPicker(
                            options: [
                                PickerOption("50", "50 条"),
                                PickerOption("100", "100 条"),
                                PickerOption("200", "200 条"),
                                PickerOption("500", "500 条"),
                            ],
                            selection: Binding(
                                get: { String(settings.maxItems) },
                                set: { settings.maxItems = Int($0) ?? 200 }
                            )
                        )
                    }
                    SettingsRow(title: "图片保留天数", subtitle: "超期原图自动清理，缩略图保留") {
                        SettingsPicker(
                            options: [
                                PickerOption("1", "1 天"),
                                PickerOption("7", "7 天"),
                                PickerOption("30", "30 天"),
                            ],
                            selection: Binding(
                                get: { String(settings.imageTtlDays) },
                                set: { settings.imageTtlDays = Int($0) ?? 7 }
                            )
                        )
                    }
                }
            }

            // 隐私：密码保护只读锁定项 + 忽略应用列表
            PrivacyCard()

            // 存储：概览 + 清空历史 / 清空图片
            StorageCard()
        }
    }
}

// MARK: - 隐私卡片

/// 隐私卡片：「跳过密码类内容」只读锁定项 + 「忽略的应用」列表管理（NSOpenPanel 添加 / × 移除）
struct PrivacyCard: View {
    private let settings = SettingsStore.shared

    var body: some View {
        SettingsGroupCard(title: "隐私") {
            VStack(alignment: .leading, spacing: 14) {
                // 只读锁定项：concealed 内容永不入库（始终开启，不可关闭）
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("跳过密码类内容")
                            .font(.system(size: 13))
                            .foregroundStyle(DT.fg)
                        Text("从密码管理器复制的 concealed 内容永不入库，此保护始终开启")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DT.muted)
                    }
                    Spacer(minLength: 12)
                    // 锁定开关：on 态 + 降不透明度 + 不可交互
                    MatteToggle(isOn: true, action: {})
                        .allowsHitTesting(false)
                        .opacity(0.45)
                }

                // 忽略的应用
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("忽略的应用")
                            .font(.system(size: 13))
                            .foregroundStyle(DT.fg)
                        Text("从下列应用复制的内容不会入库")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DT.muted)
                    }
                    if settings.ignoredBundleIds.isEmpty {
                        Text("暂无忽略的应用")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DT.muted2)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(settings.ignoredBundleIds, id: \.self) { bundleId in
                                IgnoredAppChip(bundleId: bundleId) {
                                    settings.ignoredBundleIds.removeAll { $0 == bundleId }
                                }
                            }
                        }
                    }
                    // ＋ 添加忽略应用（NSOpenPanel 选 .app）
                    Button(action: addIgnoredApp) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DT.muted)
                            Text("添加忽略应用")
                                .font(.system(size: 12))
                                .foregroundStyle(DT.fg)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().strokeBorder(DT.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                    }
                    .buttonStyle(.mattePress)
                }
            }
        }
    }

    /// NSOpenPanel 选 .app（起始目录 /Applications），写入 ignoredBundleIds。
    /// beginSheetModal 窗口级模态（sheet 贴在设置窗口上），不用 runModal——
    /// runModal 起应用级模态事件循环，期间主事件循环被阻塞，刘海面板的
    /// 热区收起定时器与全部事件投递都会停摆
    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.title = "添加忽略应用"
        panel.message = "选择不想录制剪贴板的应用"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        // 设置窗口承载 sheet（点按钮时设置窗口必为 key window）
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK,
                  let url = panel.url,
                  let bundleId = Bundle(url: url)?.bundleIdentifier,
                  !settings.ignoredBundleIds.contains(bundleId) else { return }
            settings.ignoredBundleIds.append(bundleId)
        }
    }
}

/// App 信息辅助：bundleId → 显示名 / 图标（忽略应用 chip 用）
private enum AppInfo {
    /// App 显示名（Bundle 信息优先，回退文件名；未安装返回 nil）
    static func displayName(bundleId: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        if let bundle = Bundle(url: url),
           let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
               ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String),
           !name.isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// App 图标（未安装返回 nil）
    static func icon(bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// 忽略应用 chip：App 图标 + 名称 + × 移除
struct IgnoredAppChip: View {
    let bundleId: String
    let onRemove: () -> Void

    /// × 按钮 hover 态（变 danger 色）
    @State private var hoveringRemove = false

    /// 显示名（未安装回退 bundleId）
    private var displayName: String {
        AppInfo.displayName(bundleId: bundleId) ?? bundleId
    }

    var body: some View {
        HStack(spacing: 7) {
            if let icon = AppInfo.icon(bundleId: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 12))
                    .foregroundStyle(DT.muted)
                    .frame(width: 18, height: 18)
            }
            Text(displayName)
                .font(.system(size: 12))
                .foregroundStyle(DT.fg)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hoveringRemove ? DT.danger : DT.muted)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.mattePress)
            .onHover { hoveringRemove = $0 }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(DT.surface3))
        .overlay(Capsule().strokeBorder(DT.innerCardStroke, lineWidth: 1))
    }
}

// MARK: - 存储卡片

/// 存储卡片：总条数 + 按类型分解（文本 / 图片 / 链接 / 文件）+ 清空历史 / 清空图片（确认浮层由窗口根部渲染）
struct StorageCard: View {
    /// 确认弹窗中心（清空确认浮层由设置窗口根部渲染）
    private let dialogs = SettingsDialogCenter.shared
    /// 存储概览
    @State private var stats = StorageStats()

    /// 按类型分解的条数统计
    struct StorageStats: Equatable {
        var text = 0
        var image = 0
        var link = 0
        var file = 0
        var total: Int { text + image + link + file }
    }

    var body: some View {
        SettingsGroupCard(title: "存储") {
            VStack(alignment: .leading, spacing: 14) {
                // 总条数 + 按类型分解
                Text("共 \(stats.total) 条 · 文本 \(stats.text) · 图片 \(stats.image) · 链接 \(stats.link) · 文件 \(stats.file)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(DT.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsRow(title: "清空历史", subtitle: "删除全部历史条目，模板组内容会保留") {
                    DangerButton(title: "清空") { dialogs.present(.clearHistory) }
                }
                SettingsRow(title: "清空图片", subtitle: "删除全部图片条目与原图文件") {
                    DangerButton(title: "清空") { dialogs.present(.clearImages) }
                }
            }
        }
        .onAppear { refreshStats() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 窗口激活时刷新概览（外部可能已新增 / 清空条目）
            refreshStats()
        }
        .onChange(of: dialogs.active) { _, newValue in
            // 清空确认浮层关闭后刷新概览（确认清空在窗口根部执行）
            if newValue == .none { refreshStats() }
        }
    }

    /// 读取 ClipboardStore 统计全部条目（按类型分解）
    private func refreshStats() {
        var next = StorageStats()
        for clip in ClipboardStore.shared.fetchAllClips() {
            switch clip.kindEnum {
            case .text: next.text += 1
            case .image: next.image += 1
            case .link: next.link += 1
            case .file: next.file += 1
            }
        }
        stats = next
    }
}

// MARK: - 分组卡片与设置行

/// 分组卡片：surface2 底、16 圆角、1px 描边、内 padding 18；
/// 标题 13pt fgStrong 半粗（可附说明）；子树内有展开下拉时提升层级避免被相邻卡片遮挡
struct SettingsGroupCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    /// 子树内有展开的下拉（层级提升用）
    @State private var dropdownOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.fgStrong)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DT.muted)
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DT.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DT.stroke, lineWidth: 1)
        )
        .onPreferenceChange(DropdownOpenKey.self) { dropdownOpen = $0 }
        .zIndex(dropdownOpen ? 10 : 0)
    }
}

/// 设置行：左标签 13pt fg + 说明 11.5pt muted 第二行；控件紧跟标签左侧对齐
/// 子树内有展开的下拉时提升自身层级（zIndex），避免下拉列表溢出后被同卡片内
/// （渲染顺序更晚的）其它行遮挡；与 SettingsGroupCard 的提升配合，兼顾「同卡片行」与「跨卡片」两层遮挡
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let control: () -> Control

    /// 子树内有展开的下拉（自身的下拉，用于行级层级提升）
    @State private var dropdownOpen = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fg)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DT.muted)
                }
            }
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPreferenceChange(DropdownOpenKey.self) { dropdownOpen = $0 }
        .zIndex(dropdownOpen ? 10 : 0)
    }
}

// MARK: - 自绘控件（哑光，无系统绿 Toggle / 系统 Picker）

/// 自绘开关：36×20 胶囊；开 = accent 底白圆点居右，关 = surface3 底灰点居左（无发光）
struct MatteToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule().fill(isOn ? DT.accent : DT.surface3)
                Circle()
                    .fill(isOn ? Color.white : DT.muted)
                    .frame(width: 14, height: 14)
                    .offset(x: isOn ? 8 : -8)
            }
            .frame(width: 36, height: 20)
            .overlay(Capsule().strokeBorder(DT.stroke, lineWidth: 1))
            .animation(.easeInOut(duration: 0.14), value: isOn)
        }
        .buttonStyle(.mattePress)
    }
}

/// 圆形单选：16pt 圆圈；选中 = accent 实心 + 白描边，未选 = stroke 圆圈
struct RadioCircle: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(DT.accent)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
            } else {
                Circle().strokeBorder(DT.strokeStrong, lineWidth: 1.5)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// kbd 键帽：button 底、12 圆角、fg 文字
struct KbdKey: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(DT.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous).fill(DT.button)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous).strokeBorder(DT.stroke, lineWidth: 1)
            )
    }
}

/// 快捷键捕获按钮：点击后监听下一次按键组合并保存；再次点击或按 esc 取消
struct ShortcutCaptureButton: View {
    @Bindable private var settings = SettingsStore.shared

    /// 是否处于捕获模式
    @State private var isCapturing = false
    /// 本地键盘事件监听器
    @State private var localMonitor: Any?

    var body: some View {
        Button {
            isCapturing.toggle()
        } label: {
            Text(isCapturing ? "按下快捷键…" : settings.hotkeyDisplay)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isCapturing ? DT.muted2 : DT.fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 70)
                .background(
                    RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                        .fill(isCapturing ? DT.surface3 : DT.button)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                        .strokeBorder(isCapturing ? DT.accent.opacity(0.6) : DT.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.mattePress)
        .onChange(of: isCapturing) { _, active in
            if active {
                startCapturing()
            } else {
                stopCapturing()
            }
        }
        .onDisappear { stopCapturing() }
    }

    // MARK: 捕获逻辑

    private func startCapturing() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak settings] event in
            guard let settings else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // esc 单独按下：取消捕获，让事件继续传播
            if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
                DispatchQueue.main.async { self.isCapturing = false }
                return event
            }

            // 必须包含至少一个功能修饰键
            let hasModifier = flags.contains(.command) || flags.contains(.option) ||
                              flags.contains(.control) || flags.contains(.shift)
            guard hasModifier else { return nil }

            // 排除纯修饰键按键
            let isModifierOnly = event.keyCode == UInt16(kVK_Shift) ||
                                 event.keyCode == UInt16(kVK_Command) ||
                                 event.keyCode == UInt16(kVK_Option) ||
                                 event.keyCode == UInt16(kVK_Control)
            guard !isModifierOnly else { return nil }

            let carbonMods = HotKeyDisplay.carbonModifiers(from: flags)
            guard carbonMods != 0 else { return nil }

            settings.hotkeyKeyCode = Int(event.keyCode)
            settings.hotkeyModifiers = carbonMods
            DispatchQueue.main.async { self.isCapturing = false }

            return nil
        }
    }

    private func stopCapturing() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isCapturing = false
    }
}

/// 危险操作按钮：danger 描边 + danger 文字（哑光，无系统红底）
struct DangerButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(DT.danger)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                        .strokeBorder(DT.danger.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.mattePress)
    }
}

// MARK: - 自绘下拉选择器

/// 下拉选项（id 为存储值，title 为显示文案）
struct PickerOption: Identifiable {
    let id: String
    let title: String

    init(_ id: String, _ title: String) {
        self.id = id
        self.title = title
    }
}

/// 标记子树内有展开的下拉（卡片据此提升层级，避免下拉被相邻卡片遮挡）
struct DropdownOpenKey: PreferenceKey {
    static var defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// 自绘下拉选择器：InnerCard 风格按钮 + chevron.down；展开 menuSurface 底自绘列表（选中项 ✓、hover 高亮）。
/// 按钮位于视口下半区时自动向上展开（防止超出窗口底边）；点击任意处收起
struct SettingsPicker: View {
    let options: [PickerOption]
    @Binding var selection: String
    /// 按钮宽度（右侧控件统一尺寸）
    var width: CGFloat = 150

    @State private var isOpen = false
    @State private var hoveredId: String?
    /// 展开瞬间按钮在滚动视口中的位置（翻转判断依据）
    @State private var buttonFrame: CGRect = .zero

    /// 按钮高度
    private static let buttonHeight: CGFloat = 32
    /// 下拉单行高度
    private static let rowHeight: CGFloat = 33

    var body: some View {
        pickerButton
            .background(
                // 捕获按钮在滚动视口内的位置（展开方向判断）
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: isOpen) { _, _ in
                            buttonFrame = geo.frame(in: .named("settings-scroll"))
                        }
                }
            )
            .overlay {
                // 全窗口点击层：展开时点任意处收起（位于下拉列表之下）
                if isOpen {
                    Color.clear
                        .frame(width: 1200, height: 900)
                        .contentShape(Rectangle())
                        .onTapGesture { isOpen = false }
                }
            }
            .overlay(alignment: .top) {
                if isOpen { dropdown }
            }
            .preference(key: DropdownOpenKey.self, value: isOpen)
    }

    // MARK: 按钮本体

    /// 当前选中项 + chevron（button 实底 + innerCardStroke 描边 + 12 圆角）
    private var pickerButton: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DT.muted)
            }
            .padding(.horizontal, 11)
            .frame(width: width, height: Self.buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.mattePress)
        .background(
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous).fill(DT.button)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous).strokeBorder(DT.innerCardStroke, lineWidth: 1)
        )
    }

    /// 按钮展示文案（当前选中项标题）
    private var selectedTitle: String {
        options.first { $0.id == selection }?.title ?? ""
    }

    // MARK: 下拉列表

    /// 下拉列表（menuSurface 底、14 圆角；靠近视口底部时向上翻转）
    private var dropdown: some View {
        let opensUpward = buttonFrame.minY > 300
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(options) { option in
                row(option)
            }
        }
        .padding(6)
        .frame(width: max(width, 180), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DT.menuSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DT.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
        .offset(y: opensUpward ? -(dropdownHeight + 6) : Self.buttonHeight + 6)
    }

    /// 下拉高度估算（翻转偏移用）
    private var dropdownHeight: CGFloat {
        CGFloat(options.count) * Self.rowHeight + 12
    }

    /// 单个下拉行：hover 白 10% 高亮；选中项尾随 ✓
    private func row(_ option: PickerOption) -> some View {
        let isHovering = hoveredId == option.id
        let isSelected = selection == option.id
        return Button {
            selection = option.id
            isOpen = false
        } label: {
            HStack(spacing: 8) {
                Text(option.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DT.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DT.accentBright)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? DT.stroke : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.mattePress)
        .onHover { hovering in
            hoveredId = hovering ? option.id : nil
        }
    }
}

// MARK: - 流式布局（忽略应用 chip 换行）

/// 简易流式布局：子项超宽自动换行
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Xcode 预览

/// 设置窗口预览（三分类：常规 / 呼出 / 历史与隐私）
#Preview("设置窗口") {
    SettingsView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
