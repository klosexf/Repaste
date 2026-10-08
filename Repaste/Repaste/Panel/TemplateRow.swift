//
//  TemplateRow.swift
//  Repaste
//
//  模板条目行 + 模板行 ⋮ 菜单 + 拖拽排序代理
//  （模板组 tab 内平铺的简洁列表行：内容两行截断 + 右侧 ⋮；无类型标签列）
//

import SwiftUI

// MARK: - 模板行菜单动作

/// 模板行 ⋮ 菜单动作（由 PanelView 分发到 PanelViewModel）
enum TemplateMenuAction {
    /// 使用（写剪贴板 + 收起面板）
    case use
    /// 复制（写剪贴板，面板不收起）
    case copy
    /// 删除（只删该模板条目，不动历史）
    case delete
}

// MARK: - 模板条目行

/// 模板条目行（整行点击 = 使用；右侧 ⋮ 菜单；支持拖拽排序由外层挂载）
struct TemplateRow: View {
    let clip: Clip
    /// 是否键盘选中（surface3 高亮）
    let isSelected: Bool
    var isMultiSelecting = false
    var batchNumber: Int? = nil
    var isBatchSelectable = true
    var batchUnavailableReason = "不支持多选"
    /// 搜索关键词（命中片段高亮）
    let searchText: String
    /// 使用模板（点击整行）
    let onUse: () -> Void
    /// ⋮ 菜单（参数 = 按钮在面板坐标系中的锚点 frame，供菜单弹出定位）
    let onMore: (CGRect) -> Void

    /// 行 hover 状态
    @State private var isHovering = false
    /// ⋮ 按钮在面板坐标系中的锚点 frame（滚动时随布局更新）
    @State private var moreButtonFrame: CGRect = .zero

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isMultiSelecting {
                BatchSelectionBadge(number: batchNumber, isEnabled: isBatchSelectable)
                    .padding(.top, 3)
            }
            // 内容两行截断（模板都是静态文本，无类型标签列；搜索命中段高亮）
            SearchHighlight.text(clip.preview, keyword: searchText)
                .font(.system(size: 13))
                .foregroundStyle(DT.fg)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 3)
            if !isMultiSelecting { moreButton }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                .fill(rowBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                .strokeBorder(batchNumber != nil ? DT.accent.opacity(0.6) : .clear, lineWidth: 1)
        }
        .opacity(isMultiSelecting && !isBatchSelectable ? 0.4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous))
        .onTapGesture(perform: onUse)
        .accessibilityElement(children: isMultiSelecting ? .ignore : .contain)
        .accessibilityLabel(clip.preview)
        .accessibilityValue(isMultiSelecting ? (batchNumber.map { "已选，第 \($0) 项" } ?? (isBatchSelectable ? "未选中" : batchUnavailableReason)) : "")
        .help(isMultiSelecting && !isBatchSelectable ? batchUnavailableReason : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onUse() }
        .onHover { isHovering = $0 }
    }

    // MARK: 行背景

    /// 选中 = surface3；hover = surface2；否则透明
    private var rowBackground: Color {
        if batchNumber != nil { return DT.accent.opacity(0.12) }
        if isSelected { return DT.surface3 }
        if isHovering { return DT.surface2 }
        return .clear
    }

    // MARK: 右侧操作按钮

    /// ⋮ 按钮（28×28、button 底；与 ClipRow 同款 ellipsis 图标——旋转 90° 竖排三点，点击弹出模板菜单，携带按钮锚点 frame）
    private var moreButton: some View {
        Button {
            onMore(moreButtonFrame)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DT.fg)
                .rotationEffect(.degrees(90))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DT.button)
                )
        }
        .buttonStyle(.mattePress)
        // 持续跟踪按钮在面板坐标系中的 frame（列表滚动时同步更新，供菜单弹出定位）
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(PanelView.coordinateSpaceName))
        } action: { frame in
            moreButtonFrame = frame
        }
    }
}

// MARK: - 模板行 ⋮ 菜单浮层

/// 模板行 ⋮ 菜单浮层（自绘哑光黑：使用 / 复制 / 删除；与 ClipMoreMenu 同风格）
struct TemplateRowMenu: View {
    /// 目标模板条目
    let clip: Clip
    /// 菜单项动作回调
    let onAction: (TemplateMenuAction) -> Void

    /// 当前 hover 的动作（高亮对应项）
    @State private var hoveredAction: TemplateMenuAction?

    /// 菜单宽度（比 ⋮ 历史菜单窄一档）
    static let menuWidth: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            item(.use, icon: "doc.on.clipboard", title: "使用")
            item(.copy, icon: "doc.on.doc", title: "复制")
            separator
            item(.delete, icon: "trash", title: "删除", isDanger: true)
        }
        .padding(6)
        .frame(width: Self.menuWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DT.menuSurface)
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
    }

    // MARK: 菜单项

    /// 单个菜单项：图标 + 文字左对齐；hover 高亮（危险项红色）
    private func item(
        _ action: TemplateMenuAction,
        icon: String,
        title: String,
        isDanger: Bool = false
    ) -> some View {
        let isHovering = hoveredAction == action
        return Button {
            onAction(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isDanger ? DT.danger : DT.muted)
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isDanger ? DT.danger : DT.fg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? (isDanger ? DT.dangerSoft : DT.stroke) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.mattePress)
        .onHover { hovering in
            // 仅 hover 高亮，无需动画（哑光即时反馈）
            hoveredAction = hovering ? action : nil
        }
    }

    /// 分隔线（白 8%，两侧留边）
    private var separator: some View {
        Rectangle()
            .fill(DT.stroke)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }

    // MARK: 高度估算

    /// 菜单高度估算（供弹出方向上下翻转判断；行高 33、分隔线 11、容器 padding 12）
    static func estimatedHeight(for clip: Clip) -> CGFloat {
        12 + 3 * 33 + 11
    }
}

// MARK: - 拖拽排序代理

/// 模板拖拽排序代理：进入目标行即时重排（内存），松手持久化新顺序
struct TemplateDropDelegate: DropDelegate {
    /// 拖拽悬停的目标行条目
    let target: Clip
    /// 面板状态机（重排与持久化动作的承接方）
    let viewModel: PanelViewModel

    func dropEntered(info: DropInfo) {
        guard !viewModel.isMultiSelecting else { return }
        viewModel.dragTemplateEntered(target: target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: viewModel.isMultiSelecting ? .cancel : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard !viewModel.isMultiSelecting else { return false }
        viewModel.dragTemplateEnded()
        return true
    }
}
