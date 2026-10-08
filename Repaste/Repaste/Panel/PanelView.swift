//
//  PanelView.swift
//  Repaste
//
//  面板主视图：搜索头部 / 标签页 / 来源条 / 暂停提示 / 列表
//  （刘海下拉与快捷键居中双入口共用的核心列表；哑光纯黑设计）
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 面板主视图

/// 面板主视图（宽 500、panelRadius 圆角、DT.panel 底色；高度自适应内容，超出内部滚动）
struct PanelView: View {
    let viewModel: PanelViewModel

    /// 面板命名坐标系（⋮ 按钮锚点 frame 的参照系，菜单弹出定位用）
    static let coordinateSpaceName = "panel"

    /// 搜索框聚焦
    @FocusState private var searchFocused: Bool

    /// 减弱动态效果（Reduce Motion）：浮层动效退化为纯淡入淡出
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 面板当前高度（onGeometryChange 持续更新；菜单上下翻转与预览图片高度约束用）
    @State private var panelHeight: CGFloat = 450

    /// 来源条横向滚动位置（右侧箭头点击滚动用）
    @State private var sourceScrollPos = ScrollPosition(edge: .leading)
    /// 来源条滚动状态（当前偏移 + 最大可滚动距离；箭头显隐用）
    @State private var sourceScrollState = HScrollState()
    /// 标签页行横向滚动位置（滚轮映射用）
    @State private var tabScrollPos = ScrollPosition(edge: .leading)
    /// 标签页行滚动状态
    @State private var tabScrollState = HScrollState()

    /// 列表区最大高度（固定区约 90~125 + 列表 360 ≈ 面板最大 450，受 PanelController 上限约束）
    private static let listMaxHeight: CGFloat = 360
    /// 列表区最小高度（内容少时保底，避免面板过扁）
    private static let listMinHeight: CGFloat = 180

    // MARK: 浮层动效（菜单 / 弹窗 / 预览；Reduce Motion 退化为纯淡入淡出）

    /// 菜单弹出动画（snappy 轻弹；reduce motion 快速淡入淡出）
    private var menuAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.18, extraBounce: 0.08)
    }

    /// 菜单弹出 transition：自锚点角（右上）缩放浮现
    private var menuTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing))
    }

    /// 弹窗动画
    private var dialogAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.22, extraBounce: 0.1)
    }

    /// 弹窗卡片 transition：居中缩放浮现
    private var dialogTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.96))
    }

    /// 图片预览动画
    private var previewAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.2, extraBounce: 0.06)
    }

    /// 图片预览 transition：轻微缩放浮现
    private var previewTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.97))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            tabBar
            if viewModel.showsSourceBar {
                sourceBar
            }
            if viewModel.showsPausedBanner {
                pausedBanner
            }
            listArea
            if viewModel.isMultiSelecting {
                MultiCopyFooter(viewModel: viewModel)
            }
        }
        .frame(width: DT.panelWidth)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .panelShapeBackground(isNotch: viewModel.isNotchMode)
        .allowsHitTesting(!viewModel.isBatchPreviewPresented)
        .accessibilityHidden(viewModel.isBatchPreviewPresented)
        // ⋮ 更多菜单浮层（zIndex 低于图片预览与 toast；点菜单外任意处关闭）。
        // .id(overlayTeardownToken)：浮层归空 0.7s 后代次递增强制拆除浮层子树——
        // 移除 transition 偶发卡住时视图残留（不可见但吞点击），身份重建保证彻底移除
        .overlay(alignment: .topLeading) {
            moreMenuOverlay
                .animation(menuAnimation, value: viewModel.moreMenuClip == nil)
                .id(viewModel.overlayTeardownToken)
        }
        // 模板行 ⋮ 菜单浮层（同历史菜单，点菜单外任意处关闭）
        .overlay(alignment: .topLeading) {
            templateMenuOverlay
                .animation(menuAnimation, value: viewModel.templateMenuClip == nil)
                .id(viewModel.overlayTeardownToken)
        }
        // 浏览器选择浮层（⌥ 点「打开链接」触发，点浮层外任意处关闭）
        .overlay(alignment: .topLeading) {
            browserChooserOverlay
                .animation(menuAnimation, value: viewModel.browserChooserClip == nil)
                .id(viewModel.overlayTeardownToken)
        }
        // 图片放大查看浮层（遮罩盖住整个面板，zIndex 高于列表与菜单）
        .overlay {
            previewOverlay
                .animation(previewAnimation, value: viewModel.previewingClip == nil)
                .id(viewModel.overlayTeardownToken)
        }
        // 弹窗浮层（面板内居中：半透明遮罩 + 圆角卡片；zIndex 高于菜单与预览）
        .overlay {
            dialogOverlay
                .animation(dialogAnimation, value: viewModel.activeDialog == nil)
                .id(viewModel.overlayTeardownToken)
        }
        .overlay {
            if viewModel.isBatchPreviewPresented {
                ZStack {
                    Color.black.opacity(0.55)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.closeBatchPreview() }
                    MultiCopyPreview(viewModel: viewModel, availableHeight: panelHeight)
                }
            }
        }
        // toast 轻提示（面板顶部浮现，最上层）
        .overlay(alignment: .top) {
            toastOverlay
                .animation(.easeOut(duration: 0.22), value: viewModel.toast)
                .id(viewModel.overlayTeardownToken)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            panelHeight = height
        }
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.searchFocusRequest) { _, _ in
            searchFocused = true
        }
        .onChange(of: viewModel.overlayStateFlags) { oldValue, newValue in
            // 浮层状态迁移全记录（开与关）：与点击投递日志对齐时间线，
            // 定位「点击无动作」时是哪个浮层状态在拦截
            EventLog.track(EventLog.panelOverlayChanged, ["from": oldValue, "to": newValue])
            // 浮层全部归空后调度强制拆除：清除移除 transition 偶发卡住的残留视图
            if newValue.isEmpty {
                viewModel.scheduleOverlayTeardown()
            }
        }
        // 诊断探针：SwiftUI 手势层活性检测（任何点击都应触发）。
        // 与 panel_mouse_delivered 构成三层漏斗：死态时 mouse_delivered 有而本事件无
        // = 手势路由层卡死；两者都有但无动作 = 命中区域错位或残留遮罩拦截
        .simultaneousGesture(TapGesture().onEnded {
            EventLog.track(EventLog.panelSwiftUITap, ["ovl": viewModel.overlayStateFlags])
        })
        .onChange(of: viewModel.activeDialog) { _, newValue in
            // 弹窗关闭后焦点回到搜索框（键盘导航不中断）
            if newValue == nil { searchFocused = true }
        }
        .onKeyPress { press in
            handleKeyPress(press)
        }
    }

    // MARK: 头部行（搜索框 + 设置 / 退出按钮）

    private var headerRow: some View {
        HStack(spacing: 9) {
            searchField
            iconButton(icon: "gearshape", help: "设置") {
                // 面板 NSHostingView 不在 Scene 环境内，经桥接调用 openWindow(id: "settings")
                AppWindowBridge.shared.openSettings()
            }
            iconButton(icon: "power", help: "退出") {
                // 退出确认弹窗（面板内浮层，非系统 NSAlert；「退出」= 终止应用）
                viewModel.showQuitConfirm()
            }
        }
        .padding(.horizontal, 12)
        // notch 模式顶边贴合屏幕顶，头部行下移一个刘海 / 菜单栏高度，避免与刘海并排
        .padding(.top, 10 + viewModel.notchTopInset)
        .padding(.bottom, 8)
    }

    /// 搜索框（InnerCard 样式、圆角 12、高 34、聚焦即筛；非空时尾随清空按钮）
    private var searchField: some View {
        @Bindable var model = viewModel

        return InnerCard {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.muted2)
                TextField("搜索…", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fg)
                    .focused($searchFocused)
                    .onSubmit {
                        if model.isMultiSelecting && NSEvent.modifierFlags.contains(.command) {
                            model.copySelectedBatch()
                        } else {
                            model.useSelected()
                        }
                    }
                if !model.searchText.isEmpty {
                    clearSearchButton
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
        }
    }

    /// 清空搜索按钮（xmark 小圆钮；清空后焦点回到搜索框，连续输入不中断）
    private var clearSearchButton: some View {
        Button {
            viewModel.searchText = ""
            searchFocused = true
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DT.muted)
                .frame(width: 18, height: 18)
                .background(Circle().fill(DT.surface3))
                .contentShape(Circle())
        }
        .buttonStyle(.mattePress)
        .help("清空搜索")
    }

    /// 28×28 图标按钮（button 实底、8 圆角）
    private func iconButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(DT.fg)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DT.button)
                )
        }
        .buttonStyle(.mattePress)
        .help(help)
    }

    // MARK: 标签页行

    /// 标签页数据项
    private struct TabItem: Identifiable {
        let tab: PanelTab
        let title: String

        var id: String {
            switch tab {
            case .all: return "all"
            case .text: return "text"
            case .image: return "image"
            case .link: return "link"
            case .group(let id): return "group-\(id.uuidString)"
            }
        }
    }

    /// 标签页列表：全部 / 文本 / 图片 / 链接 + 各模板组名
    private var tabItems: [TabItem] {
        var items = [
            TabItem(tab: .all, title: "全部"),
            TabItem(tab: .text, title: "文本"),
            TabItem(tab: .image, title: "图片"),
            TabItem(tab: .link, title: "链接"),
        ]
        for group in viewModel.groups {
            items.append(TabItem(tab: .group(group.id), title: group.name))
        }
        return items
    }

    /// 横向标签页行（隐藏滚动条；当前 tab 用 PillChip 选中态白底黑字胶囊；间距 6）
    private var tabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabItems) { item in
                        Button {
                            viewModel.selectedTab = item.tab
                        } label: {
                            PillChip(title: item.title, isSelected: viewModel.selectedTab == item.tab)
                        }
                        .buttonStyle(.mattePress)
                    }
                    // 新建模板组入口仍与模板标签一起滚动。
                    Button {
                        viewModel.showNewGroupDialog()
                    } label: {
                        Text("＋")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DT.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.mattePress)
                    .help("新建模板组")
                }
                .padding(.leading, 14)
            }
            .modifier(HorizontalWheelScroll(position: $tabScrollPos, state: $tabScrollState))
            Button { viewModel.toggleMultiSelection() } label: {
                Label(viewModel.isMultiSelecting ? "取消" : "多选",
                      systemImage: viewModel.isMultiSelecting ? "xmark" : "checklist")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(viewModel.isMultiSelecting ? DT.accentBright : DT.fg)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(DT.button))
            }
            .buttonStyle(.mattePress)
            .fixedSize()
            .padding(.trailing, 14)
        }
        .padding(.bottom, 9)
    }

    // MARK: 来源条

    /// 来源条（横向滚动 chip 行：全部来源 + 各来源 App 图标 16×16 + 名称 + 计数；点击切换 / 再点取消）
    /// （滚轮竖直滚动映射为横向滚动；右侧箭头前进 / 左侧箭头返回，到头自动隐藏）
    private var sourceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                sourceChip(
                    icon: nil,
                    title: "全部来源",
                    count: viewModel.sourceTotal,
                    isSelected: viewModel.selectedSourceFilter == nil
                ) {
                    viewModel.selectSource(nil)
                }
                ForEach(viewModel.sourceCounts) { source in
                    sourceChip(
                        icon: source.iconPath.flatMap { AppIconStore.shared.load(fileName: $0) },
                        title: source.name,
                        count: source.count,
                        isSelected: viewModel.selectedSourceFilter == source.key
                    ) {
                        viewModel.selectSource(source.key)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .modifier(HorizontalWheelScroll(position: $sourceScrollPos, state: $sourceScrollState))
        // 右侧前进箭头（未到最右端时显示；渐变衬底避免与末尾 chip 文字冲突）
        .overlay(alignment: .trailing) {
            if sourceScrollState.canScrollForward {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, DT.panel], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 30)
                        .allowsHitTesting(false)
                    sourceArrowButton(icon: "chevron.right", help: "查看更多来源") {
                        nudgeSourceBar(by: 200)
                    }
                    .padding(.trailing, 5)
                }
                .transition(.opacity)
            }
        }
        // 左侧返回箭头（已离开最左端时显示）
        .overlay(alignment: .leading) {
            if sourceScrollState.canScrollBackward {
                HStack(spacing: 0) {
                    sourceArrowButton(icon: "chevron.left", help: "查看前面的来源") {
                        nudgeSourceBar(by: -200)
                    }
                    .padding(.leading, 5)
                    LinearGradient(colors: [DT.panel, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 30)
                        .allowsHitTesting(false)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: sourceScrollState)
        .padding(.bottom, 9)
    }

    /// 来源条箭头点击滚动（步长 200，动画过渡；范围由 HScrollState 夹紧）
    private func nudgeSourceBar(by delta: CGFloat) {
        let target = min(sourceScrollState.maxX, max(0, sourceScrollState.offsetX + delta))
        withAnimation(.easeOut(duration: 0.18)) {
            sourceScrollPos = ScrollPosition(point: CGPoint(x: target, y: 0))
        }
    }

    /// 来源条滚动箭头（22×22 圆形按钮、button 实底、无高光）
    private func sourceArrowButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DT.fg)
                .frame(width: 22, height: 22)
                .background(Circle().fill(DT.button))
        }
        .buttonStyle(.mattePress)
        .help(help)
    }

    /// 来源 chip（选中态白底黑字胶囊；未知来源用中性问号图标）
    private func sourceChip(
        icon: NSImage?,
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else if title == "全部来源" {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? DT.panel : DT.muted2)
                } else {
                    // 未知来源：中性问号图标
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? DT.panel : DT.muted2)
                }
                Text(title)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? DT.muted2 : DT.muted)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(isSelected ? DT.panel : DT.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? Color.white : DT.surface3)
            )
        }
        .buttonStyle(.mattePress)
    }

    // MARK: 录制暂停提示条

    /// 「剪贴板记录已暂停」提示条（recordingEnabled == false 时显示，黄色 warn 色小字条 + 右侧「恢复」按钮：
    /// 在发现问题的地方顺手解决问题，不必绕道菜单栏/设置）
    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DT.warn)
                .frame(width: 7, height: 7)
            Text("剪贴板记录已暂停，新复制的内容不会进入历史")
                .font(.system(size: 12))
                .foregroundStyle(DT.warn)
            Spacer(minLength: 0)
            resumeButton
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DT.warn.opacity(0.16))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// 「恢复」按钮（白底黑字小胶囊，与选中态 chip 同语言）
    private var resumeButton: some View {
        Button {
            viewModel.resumeRecording()
        } label: {
            Text("恢复")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DT.panel)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.mattePress)
        .help("恢复剪贴板记录")
    }

    // MARK: 列表区

    /// 列表区：模板组 tab 渲染模板区，其余渲染历史列表 / 空态（高度自适应，超出内部滚动）
    private var listArea: some View {
        Group {
            if viewModel.isGroupTab {
                templateArea
            } else if viewModel.filteredClips.isEmpty {
                emptyState
            } else {
                clipList
            }
        }
        .frame(minHeight: Self.listMinHeight, maxHeight: Self.listMaxHeight)
    }

    // MARK: 模板组内容区

    /// 模板组 tab 内容区：组管理行 + 模板列表（可拖拽排序）+ 底部操作区（固定，不在滚动区内）
    private var templateArea: some View {
        VStack(spacing: 0) {
            if !viewModel.isMultiSelecting { groupManageRow }
            if viewModel.filteredClips.isEmpty {
                templateEmptyState
            } else {
                templateList
            }
            if !viewModel.isMultiSelecting { templateFooter }
        }
    }

    /// 组管理行：右对齐小文字按钮「重命名 / 删除组」（仅模板组 tab 显示）
    private var groupManageRow: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            SmallTextButton(title: "重命名") {
                viewModel.showRenameGroupDialog()
            }
            SmallTextButton(title: "删除组") {
                viewModel.showDeleteGroupDialog()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// 模板列表（行可拖拽排序；键盘选中滚动跟随；搜索同样生效）
    private var templateList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(viewModel.filteredClips.enumerated()), id: \.element.id) { index, clip in
                        TemplateRow(
                            clip: clip,
                            isSelected: viewModel.selectionIndex == index,
                            isMultiSelecting: viewModel.isMultiSelecting,
                            batchNumber: viewModel.batchSelection.position(of: clip.id),
                            isBatchSelectable: viewModel.canBatchSelect(clip),
                            batchUnavailableReason: viewModel.batchUnavailableReason(clip),
                            searchText: viewModel.searchText,
                            onUse: {
                                viewModel.selectionIndex = index
                                viewModel.activateRow(clip)
                            },
                            onMore: { anchor in
                                viewModel.openTemplateMenu(clip: clip, anchor: anchor)
                            }
                        )
                        .id(clip.id)
                        // 拖拽排序：拖起记录条目 id；悬停到目标行即时重排
                        .onDrag {
                            guard !viewModel.isMultiSelecting else { return NSItemProvider() }
                            viewModel.draggingTemplateId = clip.id
                            return NSItemProvider(object: clip.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.utf8PlainText], delegate: TemplateDropDelegate(target: clip, viewModel: viewModel))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            // 松手落在行间空白处也提交排序（dragTemplateEnded 幂等）
            .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { _ in
                viewModel.dragTemplateEnded()
                return true
            }
            .onChange(of: viewModel.selectionIndex) { _, newValue in
                guard let index = newValue,
                      viewModel.filteredClips.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(viewModel.filteredClips[index].id, anchor: .center)
                }
            }
        }
    }

    /// 模板组空态：无模板（引导新建）与搜索无结果两种
    private var templateEmptyState: some View {
        let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 10) {
            Image(systemName: isSearching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(DT.muted2)
            Text(isSearching ? "没有匹配的结果" : "还没有模板")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DT.fg)
            Text(isSearching ? "试试换个关键词" : "点「＋ 新建模板」添加常用内容")
                .font(.system(size: 12))
                .foregroundStyle(DT.muted)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 模板 tab 底部操作区（固定在列表下方）：左「＋ 新建模板」（仅内容宽度）+ 右条目计数
    private var templateFooter: some View {
        HStack(spacing: 8) {
            SolidButton(title: "＋ 新建模板") {
                viewModel.showNewTemplateDialog()
            }
            Spacer(minLength: 0)
            Text("\(viewModel.currentGroupTemplateCount) 条")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DT.muted2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// 行列表（卡片间 6 间距、水平 padding 14；键盘选中滚动跟随）
    private var clipList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(viewModel.filteredClips.enumerated()), id: \.element.id) { index, clip in
                        ClipRow(
                            clip: clip,
                            isSelected: viewModel.selectionIndex == index,
                            isMultiSelecting: viewModel.isMultiSelecting,
                            batchNumber: viewModel.batchSelection.position(of: clip.id),
                            isBatchSelectable: viewModel.canBatchSelect(clip),
                            batchUnavailableReason: viewModel.batchUnavailableReason(clip),
                            searchText: viewModel.searchText,
                            onUse: {
                                viewModel.selectionIndex = index
                                viewModel.activateRow(clip)
                            },
                            onOpenPreview: {
                                viewModel.openPreview(clip: clip)
                            },
                            onSourceTap: { viewModel.selectSource($0) },
                            onOpenLink: {
                                viewModel.openLink(clip: clip, kind: "inline")
                            },
                            onChooseBrowser: { anchor in
                                viewModel.openBrowserChooser(clip: clip, anchor: anchor)
                            },
                            onMore: { anchor in
                                viewModel.openMoreMenu(clip: clip, anchor: anchor)
                            }
                        )
                        .id(clip.id)
                        // 新条目实时滑入（复制新内容 → 面板可见时从顶部滑入；删除时淡出）
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .onChange(of: viewModel.selectionIndex) { _, newValue in
                guard let index = newValue,
                      viewModel.filteredClips.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(viewModel.filteredClips[index].id, anchor: .center)
                }
            }
        }
    }

    // MARK: 空态

    /// 空态：无任何历史（大空态）与有历史但筛选无结果（小空态）两种
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.hasNoHistory ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(DT.muted2)
            Text(viewModel.hasNoHistory ? "还没有任何记录" : "没有匹配的结果")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DT.fg)
            Text(viewModel.hasNoHistory ? "复制点什么试试，内容会自动出现在这里" : "试试换个关键词或来源")
                .font(.system(size: 12))
                .foregroundStyle(DT.muted)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: ⋮ 更多菜单浮层

    /// 菜单浮层：透明点击层（点菜单外关闭）+ 菜单本体（按锚点定位，向下弹出、空间不足向上翻转）
    private var moreMenuOverlay: some View {
        ZStack(alignment: .topLeading) {
            // 点击层：拦截面板内所有点击（含列表滚动），点任意处关闭菜单。
            // - 用 Button(.plain) 而非 onTapGesture：裸手势在 NSHostingView 上与
            //   浮层移除 transition 存在竞态（mouseUp 与视图移除竞争），偶发手势图
            //   卡死后吞掉面板内所有后续点击；Button 走 AppKit 完整点击语义更稳
            // - 常驻树中并以 allowsHitTesting 绑定菜单开闭，而非 if 条件移除：
            //   移除 transition 播放期间（spring settle ~0.5s）视图仍参与命中测试，
            //   退场中的全尺寸透明层会吞掉菜单刚关闭后落在面板内的一切点击
            //   （表现为再点 ⋮ 无反应、需点两次）
            dismissLayer { viewModel.closeMoreMenu() }
                .allowsHitTesting(viewModel.moreMenuClip != nil)
            if let clip = viewModel.moreMenuClip {
                let position = menuPosition(
                    anchor: viewModel.moreMenuAnchor,
                    menuWidth: ClipMoreMenu.menuWidth,
                    menuHeight: ClipMoreMenu.estimatedHeight(for: clip)
                )
                ClipMoreMenu(clip: clip) { action in
                    viewModel.closeMoreMenu()
                    handleMenuAction(action, for: clip)
                }
                .offset(x: position.x, y: position.y)
                .transition(menuTransition)
            }
        }
    }

    // MARK: 模板行 ⋮ 菜单浮层

    /// 模板菜单浮层：透明点击层（点菜单外关闭）+ 菜单本体（使用 / 复制 / 删除）
    /// 点击层常驻 + allowsHitTesting 绑定开闭（同 moreMenuOverlay：避免退场动画期间
    /// 透明层残留命中测试，吞掉菜单关闭后立即到来的点击）
    private var templateMenuOverlay: some View {
        ZStack(alignment: .topLeading) {
            dismissLayer { viewModel.closeTemplateMenu() }
                .allowsHitTesting(viewModel.templateMenuClip != nil)
            if let clip = viewModel.templateMenuClip {
                TemplateRowMenu(clip: clip) { action in
                    viewModel.closeTemplateMenu()
                    handleTemplateMenuAction(action, for: clip)
                }
                .offset(
                    x: templateMenuPosition.x,
                    y: templateMenuPosition.y
                )
                .transition(menuTransition)
            }
        }
    }

    /// 模板菜单弹出位置（与历史菜单同规则）
    private var templateMenuPosition: CGPoint {
        guard let clip = viewModel.templateMenuClip else { return .zero }
        return menuPosition(
            anchor: viewModel.templateMenuAnchor,
            menuWidth: TemplateRowMenu.menuWidth,
            menuHeight: TemplateRowMenu.estimatedHeight(for: clip)
        )
    }

    // MARK: 浏览器选择浮层（⌥ 点「打开链接」）

    /// 浏览器选择浮层：透明点击层（点浮层外关闭）+ 菜单本体（按「打开链接」按钮锚点定位，含上下翻转）
    /// 点击层常驻 + allowsHitTesting 绑定开闭（同 moreMenuOverlay，防退场动画期间吞点击）
    @ViewBuilder
    private var browserChooserOverlay: some View {
        ZStack(alignment: .topLeading) {
            dismissLayer { viewModel.closeBrowserChooser() }
                .allowsHitTesting(viewModel.browserChooserClip != nil)
            if let clip = viewModel.browserChooserClip {
                let options = BrowserChooserMenu.options()
                let position = menuPosition(
                    anchor: viewModel.browserChooserAnchor,
                    menuWidth: BrowserChooserMenu.menuWidth,
                    menuHeight: BrowserChooserMenu.estimatedHeight(options: options)
                )
                BrowserChooserMenu(clip: clip) { bundleId in
                    viewModel.closeBrowserChooser()
                    viewModel.openLink(clip: clip, browserBundleId: bundleId, kind: "menu")
                }
                .offset(x: position.x, y: position.y)
                .transition(menuTransition)
            }
        }
    }

    /// 菜单弹出位置（通用）：右缘对齐锚点、锚点下方 6px；超出面板高度则向上翻转；整体钳制在面板内
    private func menuPosition(anchor: CGRect, menuWidth: CGFloat, menuHeight: CGFloat) -> CGPoint {
        // 水平：右缘对齐按钮（钳制在面板内）
        var x = anchor.maxX - menuWidth
        x = min(max(x, 10), DT.panelWidth - menuWidth - 10)

        // 垂直：默认按钮下方 6px；菜单底会超出面板则翻转到按钮上方
        var y = anchor.maxY + 6
        if y + menuHeight > panelHeight - 10 {
            y = anchor.minY - 6 - menuHeight
        }
        y = max(y, 10)
        return CGPoint(x: x, y: y)
    }

    /// 分发菜单动作到状态机
    private func handleMenuAction(_ action: ClipMenuAction, for clip: Clip) {
        switch action {
        case .plainCopy:
            viewModel.copyPlainText(clip: clip)
        case .viewImage:
            viewModel.openPreview(clip: clip)
        case .saveToGroup:
            viewModel.requestSaveToGroup(clip: clip)
        case .togglePin:
            viewModel.togglePin(clip: clip)
        case .delete:
            viewModel.delete(clip: clip)
        }
    }

    /// 分发模板菜单动作到状态机
    private func handleTemplateMenuAction(_ action: TemplateMenuAction, for clip: Clip) {
        switch action {
        case .use:
            viewModel.use(clip: clip)
        case .copy:
            viewModel.copyTemplate(clip: clip)
        case .delete:
            viewModel.deleteTemplate(clip: clip)
        }
    }

    // MARK: 弹窗浮层

    /// 浮层关闭点击层（全尺寸透明 Button）：所有「点遮罩关闭」统一入口。
    /// 见 moreMenuOverlay 注释——Button 替代 onTapGesture 防手势竞态
    private func dismissLayer(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 纯鼠标关闭手段，且三个菜单浮层的实例常驻树中，
        // 需避免不可见按钮进入键盘 Tab 焦点链（键盘用户由 esc 逐层关闭兜底）
        .accessibilityHidden(true)
    }

    /// 弹窗浮层：半透明遮罩（点击取消）+ 居中圆角卡片
    @ViewBuilder
    private var dialogOverlay: some View {
        if let dialog = viewModel.activeDialog {
            ZStack {
                Color.black.opacity(0.5)
                dismissLayer { viewModel.cancelDialog() }
                dialogCard(for: dialog)
                    .transition(dialogTransition)
            }
            .transition(.opacity)
        }
    }

    /// 按弹窗类型分发内容卡片
    @ViewBuilder
    private func dialogCard(for dialog: PanelDialog) -> some View {
        switch dialog {
        case .newGroup:
            NewGroupDialogContent(viewModel: viewModel)
        case .newTemplate(let groupId):
            NewTemplateDialogContent(viewModel: viewModel, groupId: groupId)
        case .saveToGroup(let clipId):
            if let clip = viewModel.clips.first(where: { $0.id == clipId }) {
                SaveToGroupDialogContent(viewModel: viewModel, clip: clip)
            } else {
                // 条目已不存在（如待删除提交后）：只剩遮罩无卡片会呈现「面板死态」，自动关闭
                Color.clear.onAppear { viewModel.cancelDialog() }
            }
        case .renameGroup(let groupId):
            RenameGroupDialogContent(viewModel: viewModel, groupId: groupId)
        case .deleteGroup(let groupId):
            DeleteGroupDialogContent(viewModel: viewModel, groupId: groupId)
        case .quitConfirm:
            QuitDialogContent(viewModel: viewModel)
        }
    }

    // MARK: 图片放大查看浮层

    /// 图片放大查看浮层（previewingClip 非空时显示；遮罩盖住整个面板）
    @ViewBuilder
    private var previewOverlay: some View {
        if let clip = viewModel.previewingClip {
            ImagePreviewOverlay(
                clip: clip,
                maxImageHeight: previewMaxImageHeight,
                onClose: { viewModel.closePreview() },
                onCopyImage: { viewModel.copyPreviewImage(clip: clip) }
            )
            .transition(previewTransition)
        }
    }

    /// 预览图片最大高度：屏幕可见高度 70%，且不超过面板高度扣除操作区（约 150）
    private var previewMaxImageHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 600
        return max(200, min(screenHeight * 0.7, panelHeight - 150))
    }

    // MARK: toast 轻提示

    /// toast 浮层：面板顶部居中，紫色 ✓ + 主标题 + 副标题 + 可选动作按钮（如删除后「撤销」），紫边辉光黑底
    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = viewModel.toast {
            HStack(spacing: 6) {
                Text("✓")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DT.success)
                Text(toast.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DT.fgStrong)
                if let subtitle = toast.subtitle, !subtitle.isEmpty {
                    Text("·")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DT.muted2)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DT.muted)
                        .lineLimit(1)
                        // 空间不足时副标题最先被截断（低优先级先压缩），保住标题与动作按钮
                        .layoutPriority(-1)
                }
                if let actionTitle = toast.actionTitle, let action = toast.action {
                    Button {
                        action()
                    } label: {
                        Text(actionTitle)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(DT.accentBright)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(DT.accent.opacity(0.18)))
                            // 动作按钮文字永不压缩（避免「撤销」被截成「…」）
                            .fixedSize()
                    }
                    .buttonStyle(.mattePress)
                    .help(actionTitle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DT.toastBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DT.accentLine, lineWidth: 1)
            )
            .shadow(color: Color(red: 139 / 255, green: 107 / 255, blue: 255 / 255, opacity: 0.22), radius: 20)
            .shadow(color: .black.opacity(0.55), radius: 40, y: 12)
            .padding(.top, 58)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: -8)),
                    removal: .opacity.combined(with: .offset(y: -8))
                )
            )
        }
    }

    // MARK: 键盘导航

    /// 键盘事件处理：弹窗打开时 esc 取消（其余交给弹窗输入框）；
    /// ↑↓ 移动选中、⏎ 使用、⌘⏎ 打开链接、⌘G 存入模板组、⌫ 删除、esc 逐层关闭（预览 / 菜单 / 搜索 / 面板）
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if viewModel.isBatchPreviewPresented {
            if press.key == .escape {
                viewModel.closeBatchPreview()
                return .handled
            }
            if press.key == .return && press.modifiers.contains(.command) {
                viewModel.copySelectedBatch()
                return .handled
            }
            return .ignored
        }
        // 弹窗打开：esc = 取消；Enter 由弹窗内输入框 onSubmit 提交主操作，其余按键透传
        if viewModel.activeDialog != nil {
            if press.key == .escape {
                viewModel.cancelDialog()
                return .handled
            }
            return .ignored
        }
        // ⌘G：存入模板组（作用于键盘选中条目；与 ⋮ 菜单等价入口）
        if press.modifiers.contains(.command), press.characters.lowercased() == "g" {
            if let index = viewModel.selectionIndex, viewModel.filteredClips.indices.contains(index) {
                viewModel.requestSaveToGroup(clip: viewModel.filteredClips[index])
            }
            return .handled
        }
        switch press.key {
        case .upArrow:
            viewModel.moveSelection(-1)
            return .handled
        case .downArrow:
            viewModel.moveSelection(1)
            return .handled
        case .return:
            if press.modifiers.contains(.command) {
                if viewModel.isMultiSelecting {
                    viewModel.copySelectedBatch()
                    return .handled
                }
                // ⌘⏎ 打开链接：选中条目为链接类打开整串 URL；文本类打开首个 http(s) 链接；其他类型忽略
                if let index = viewModel.selectionIndex, viewModel.filteredClips.indices.contains(index) {
                    viewModel.openLink(clip: viewModel.filteredClips[index], kind: "hotkey")
                }
                return .handled
            }
            viewModel.useSelected()
            return .handled
        case .delete:
            if viewModel.isMultiSelecting {
                if let index = viewModel.selectionIndex, viewModel.filteredClips.indices.contains(index) {
                    viewModel.removeBatchItem(viewModel.filteredClips[index].id)
                }
            } else {
                viewModel.deleteSelected()
            }
            return .handled
        case .escape:
            // 逐层关闭：图片预览 → ⋮ 菜单 → 模板菜单 → 浏览器选择浮层 → 清空搜索 → 关闭面板
            if viewModel.previewingClip != nil {
                viewModel.closePreview()
            } else if viewModel.moreMenuClip != nil {
                viewModel.closeMoreMenu()
            } else if viewModel.templateMenuClip != nil {
                viewModel.closeTemplateMenu()
            } else if viewModel.browserChooserClip != nil {
                viewModel.closeBrowserChooser()
            } else if viewModel.isMultiSelecting {
                viewModel.cancelMultiSelection()
            } else if !viewModel.searchText.isEmpty {
                viewModel.searchText = ""
            } else {
                PanelController.shared.hide()
            }
            return .handled
        default:
            return .ignored
        }
    }
}

// MARK: - 小文字按钮

/// 小文字按钮（muted 小字，hover 提亮；模板 tab 组管理行用）
private struct SmallTextButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(isHovering ? DT.fg : DT.muted)
        }
        .buttonStyle(.mattePress)
        .onHover { isHovering = $0 }
    }
}

// MARK: - 面板底形状

/// 面板底：centered 模式四角 panelRadius 圆角；
/// notch 模式顶部平边（贴合菜单栏下沿，顶部无圆角）；无边框描边
private struct PanelShapeBackground: ViewModifier {
    let isNotch: Bool

    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isNotch ? 0 : DT.panelRadius,
            bottomLeadingRadius: DT.panelRadius,
            bottomTrailingRadius: DT.panelRadius,
            topTrailingRadius: isNotch ? 0 : DT.panelRadius,
            style: .continuous
        )
        return content
            .background(shape.fill(DT.panel))
            .clipShape(shape)
    }
}

extension View {
    /// 应用面板底形状（notch 顶部平边 / centered 四角圆角 + panel 底色，无边框）
    func panelShapeBackground(isNotch: Bool) -> some View {
        modifier(PanelShapeBackground(isNotch: isNotch))
    }
}

// MARK: - 横向滚动增强（macOS）

/// 横向条滚动状态（当前偏移 + 最大可滚动距离；箭头显隐与滚轮换算用）
private struct HScrollState: Equatable {
    var offsetX: CGFloat = 0
    var maxX: CGFloat = 0

    /// 已离开最左端，可向左返回
    var canScrollBackward: Bool { offsetX > 0.5 }
    /// 未到最右端，可向右前进
    var canScrollForward: Bool { offsetX < maxX - 0.5 }
}

/// 竖直滚轮 → 横向滚动桥接（macOS 鼠标滚轮默认无法驱动横向 ScrollView）
/// 通过本地事件监视器拦截自身范围内的竖直滚轮事件；横滑（deltaX 主导）不受影响，原样放行
private struct VerticalWheelBridge: NSViewRepresentable {
    /// deltaY 向上为正；precise = 触控板等精细增量（按点数计，无需放大）
    var onWheel: (_ deltaY: CGFloat, _ precise: Bool) -> Void

    final class BridgeView: NSView {
        var onWheel: ((CGFloat, Bool) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window,
                      abs(event.deltaY) > abs(event.deltaX) else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                self.onWheel?(event.deltaY, event.hasPreciseScrollingDeltas)
                return nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.onWheel = onWheel
        return view
    }

    func updateNSView(_ view: BridgeView, context: Context) {
        view.onWheel = onWheel
    }
}

/// 横向滚动增强：scrollPosition 绑定 + 滚动几何跟踪 + 竖直滚轮映射为横向滚动
/// （来源条 / 标签页行共用；触控板横滑走系统原生行为）
private struct HorizontalWheelScroll: ViewModifier {
    @Binding var position: ScrollPosition
    @Binding var state: HScrollState

    /// 非精细滚轮（普通鼠标）每格滚动的点数
    private static let wheelStep: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: HScrollState.self) { geo in
                HScrollState(
                    offsetX: geo.contentOffset.x,
                    maxX: max(0, geo.contentSize.width - geo.containerSize.width)
                )
            } action: { _, newValue in
                state = newValue
            }
            .background(
                VerticalWheelBridge { deltaY, precise in
                    // 滚轮向上 → 回到左侧；向下（含触控板自然滚动）→ 前进到右侧
                    let delta = -deltaY * (precise ? 1 : Self.wheelStep)
                    let target = min(state.maxX, max(0, state.offsetX + delta))
                    position = ScrollPosition(point: CGPoint(x: target, y: 0))
                }
            )
    }
}

// MARK: - Xcode 预览

/// 面板预览（居中模式四角圆角；notch 模式需真机/模拟运行——NSPanel 只在运行时由 PanelController 创建）
#Preview("主面板 · 居中") {
    PanelView(viewModel: {
        let vm = PanelViewModel()
        vm.isNotchMode = false
        return vm
    }())
        .padding(40)
        .background(
            LinearGradient(colors: [Color(hex: 0x18181E), Color(hex: 0x0A0A0E)],
                           startPoint: .top, endPoint: .bottom)
        )
        .preferredColorScheme(.dark)
}

/// 面板预览（刘海下拉模式：顶边平直，模拟贴菜单栏下沿）
#Preview("主面板 · 刘海") {
    VStack(spacing: 0) {
        // 模拟菜单栏
        Rectangle()
            .fill(Color.black)
            .frame(height: 28)
            .overlay(alignment: .leading) {
                Text("  Finder  文件  编辑")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
        PanelView(viewModel: PanelViewModel())
    }
    .background(
        LinearGradient(colors: [Color(hex: 0x18181E), Color(hex: 0x0A0A0E)],
                       startPoint: .top, endPoint: .bottom)
    )
    .preferredColorScheme(.dark)
}

/// Color(hex:) 便捷构造（仅预览用）
private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
