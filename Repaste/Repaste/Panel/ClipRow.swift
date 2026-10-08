//
//  ClipRow.swift
//  Repaste
//
//  列表单行卡片：文本 / 图片 / 链接三类形态（整行可点 = 使用；无彩色竖线）
//

import SwiftUI

// MARK: - 相对时间

/// 相对时间格式化：刚刚 / N 分钟前 / N 小时前 / 昨天 / N 天前（>7 天显示日期）
enum RelativeTime {
    /// 跨年日期格式化器（缓存复用）
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()

    /// 相对时间文本
    static func string(from date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return "昨天" }
        if interval < 7 * 86400 { return "\(Int(interval / 86400)) 天前" }
        // >7 天显示日期（同年省略年份）
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
        }
        return dateFormatter.string(from: date)
    }
}

// MARK: - 搜索命中高亮

/// 搜索命中高亮：文本中命中关键词的片段染成 accentBright（大小写 / 音调不敏感）；
/// 关键词为空或未命中返回普通 Text（基础样式完全交给调用方视图修饰）
enum SearchHighlight {
    static func text(_ text: String, keyword: String) -> Text {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Text(text) }

        // 逐段切分：未命中段不带属性（继承视图修饰），命中段显式 accentBright
        var result = AttributedString()
        var remaining = Substring(text)
        var found = false
        while let range = remaining.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) {
            found = true
            if range.lowerBound > remaining.startIndex {
                result += AttributedString(String(remaining[remaining.startIndex..<range.lowerBound]))
            }
            var hit = AttributedString(String(remaining[range]))
            hit.foregroundColor = DT.accentBright
            result += hit
            remaining = remaining[range.upperBound...]
        }
        guard found else { return Text(text) }
        result += AttributedString(String(remaining))
        return Text(result)
    }
}

// MARK: - 单行卡片

/// 单行卡片（三类形态：文本 / 图片 / 链接；整行点击 = 使用；图片缩略图点击 = 放大查看）
struct ClipRow: View {
    let clip: Clip
    /// 是否键盘选中（surface3 高亮）
    let isSelected: Bool
    var isMultiSelecting = false
    var batchNumber: Int? = nil
    var isBatchSelectable = true
    var batchUnavailableReason = "不支持多选"
    /// 搜索关键词（命中片段高亮）
    let searchText: String
    /// 使用条目（点击整行）
    let onUse: () -> Void
    /// 放大查看图片（点击缩略图；仅图片卡）
    let onOpenPreview: () -> Void
    /// 点击行内来源标签（key = bundleId 或 "unknown"，等同来源条筛选）
    let onSourceTap: (String) -> Void
    /// 打开链接（链接 / 文本卡统一的「打开链接」按钮普通点击；默认浏览器打开）
    let onOpenLink: () -> Void
    /// 按住 ⌥ 点「打开链接」：弹出浏览器选择浮层（参数 = 按钮在面板坐标系中的锚点 frame）
    let onChooseBrowser: (CGRect) -> Void
    /// ⋮ 菜单（参数 = ⋮ 按钮在面板坐标系中的锚点 frame，供菜单弹出定位）
    let onMore: (CGRect) -> Void

    /// 行 hover 状态
    @State private var isHovering = false
    /// 行内来源标签 hover 状态
    @State private var isSourceHovering = false
    /// 「打开链接」次级按钮 hover 状态
    @State private var isLinkHovering = false
    /// 图片缩略图 hover 状态（显示放大角标）
    @State private var isThumbHovering = false
    /// 来源图标（onAppear 加载一次，避免重复读盘）
    @State private var sourceIcon: NSImage?
    /// 图片缩略图（onAppear 加载一次）
    @State private var thumbnail: NSImage?
    /// ⋮ 按钮在面板坐标系中的锚点 frame（滚动时随布局更新）
    @State private var moreButtonFrame: CGRect = .zero
    /// 「打开链接」按钮在面板坐标系中的锚点 frame（⌥ 点击弹浏览器选择浮层定位用）
    @State private var linkButtonFrame: CGRect = .zero

    /// 千分位格式化器（>1000 字时使用）
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isMultiSelecting {
                BatchSelectionBadge(number: batchNumber, isEnabled: isBatchSelectable)
                    .padding(.top, 2)
            }
            // 置顶标记（中性 muted：状态标记，不占用警示橙与类型色语义）
            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DT.muted)
                    .padding(.top, 4)
            }

            // 左侧类型标签（kindLabel 文字 + kindColor 色）
            Text(clip.kindEnum.kindLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(clip.kindEnum.kindColor)
                .frame(width: 30, alignment: .leading)
                .padding(.top, 2)

            // 左侧缩略图（仅图片卡，40×40 圆角 8）
            if clip.kindEnum == .image {
                thumbnailView
                    .padding(.top, 1)
                    .allowsHitTesting(!isMultiSelecting)
            }

            // 内容区（三类形态）
            contentView
                .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧操作区（⋮ 按钮；链接打开已统一为元信息行内「打开链接」按钮）
            if !isMultiSelecting {
                moreButton
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        .onAppear(perform: loadImages)
    }

    // MARK: 行背景

    /// 选中 = surface3；hover = surface2；否则透明（无彩色竖线）
    private var rowBackground: Color {
        if batchNumber != nil { return DT.accent.opacity(0.12) }
        if isSelected { return DT.surface3 }
        if isHovering { return DT.surface2 }
        return .clear
    }

    // MARK: 内容区（三类形态）

    @ViewBuilder
    private var contentView: some View {
        switch clip.kindEnum {
        case .image:
            // 图片卡：preview（文件名）fgStrong + 元信息（来源 + 时间 + 「1280×800 · PNG」）
            VStack(alignment: .leading, spacing: 5) {
                SearchHighlight.text(clip.preview, keyword: searchText)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fgStrong)
                    .lineLimit(1)
                metaRow(extras: imageDimensionText.map { [$0] } ?? [])
            }
        case .link:
            // 链接卡：域名加粗 fgStrong（防钓鱼设计）+ 路径 muted 小字 + 来源 + 时间
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.link)
                    SearchHighlight.text(hostText, keyword: searchText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DT.fgStrong)
                        .lineLimit(1)
                }
                // 元信息行末尾统一「打开链接」按钮（与文本卡同位置同样式）
                metaRow(extras: [], showsOpenLink: containsOpenableLink)
            }
        case .text, .file:
            // 文本卡：preview 两行截断 fg 色 + 元信息（来源 + 时间 + 字数 + 富文本标记 + 可选「打开链接」）
            VStack(alignment: .leading, spacing: 5) {
                SearchHighlight.text(clip.preview, keyword: searchText)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fg)
                    .lineLimit(2)
                metaRow(extras: textExtras, showsOpenLink: containsOpenableLink)
            }
        }
    }

    // MARK: 元信息行（统一 muted 12pt）

    /// 元信息行：来源（可点，等同来源条筛选）+ 相对时间 + 附加段（字数 / 富文本 / 图片尺寸）
    /// + 可选「打开链接」按钮（条目含 http(s) 链接时统一展示在行末）
    private func metaRow(extras: [String], showsOpenLink: Bool = false) -> some View {
        HStack(spacing: 7) {
            sourceLabel
                .allowsHitTesting(!isMultiSelecting)
            dot
            Text(RelativeTime.string(from: clip.createdAt))
            ForEach(extras, id: \.self) { text in
                dot
                Text(text)
            }
            if showsOpenLink && !isMultiSelecting {
                dot
                openLinkButton
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(DT.muted)
    }

    /// 条目是否含可打开的 http(s) 链接（链接卡取整串、文本卡取首个链接；检出即出「打开链接」按钮）
    private var containsOpenableLink: Bool {
        PanelViewModel.openableURL(in: clip) != nil
    }

    /// 「打开链接 ↗」行内按钮（accent 紫色，hover 提亮 accentBright）：
    /// 普通点击 = 默认浏览器打开链接；按住 ⌥ 点击 = 弹浏览器选择浮层
    /// （onTapGesture 捕获点击时刻的 NSEvent.modifierFlags，系统 Button 不暴露修饰键）
    private var openLinkButton: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
            Text("打开链接")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isLinkHovering ? DT.accentBright : DT.accent)
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) {
                onChooseBrowser(linkButtonFrame)
            } else {
                onOpenLink()
            }
        }
        .onHover { isLinkHovering = $0 }
        // 持续跟踪按钮在面板坐标系中的 frame（列表滚动时同步更新，供浏览器浮层弹出定位）
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(PanelView.coordinateSpaceName))
        } action: { frame in
            linkButtonFrame = frame
        }
    }

    /// 行内来源标签（可点切筛选；未知来源用中性问号图标）
    private var sourceLabel: some View {
        HStack(spacing: 5) {
            if let sourceIcon {
                Image(nsImage: sourceIcon)
                    .resizable()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(DT.muted2)
            }
            Text(clip.sourceAppName ?? "未知来源")
        }
        .foregroundStyle(isSourceHovering ? DT.fg : DT.muted)
        .contentShape(Rectangle())
        .onTapGesture { onSourceTap(sourceKey) }
        .onHover { isSourceHovering = $0 }
    }

    /// 来源筛选 key（bundleId 或 "unknown"）
    private var sourceKey: String {
        clip.sourceBundleId ?? PanelViewModel.unknownSourceKey
    }

    /// 元信息分隔小圆点
    private var dot: some View {
        Circle()
            .fill(DT.muted2.opacity(0.55))
            .frame(width: 3, height: 3)
    }

    // MARK: 图片缩略图

    /// 40×40 缩略图（优先缩略图，缺失回退原图；再缺失显示占位块）：
    /// 点击直接放大查看（行点击仍是「使用」，两个意图分开）；hover 显示放大角标
    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(DT.surface3)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // 内层手势优先于整行 onTapGesture
        .onTapGesture(perform: onOpenPreview)
        .onHover { isThumbHovering = $0 }
        .help("点击查看大图")
        .overlay(alignment: .bottomTrailing) {
            if isThumbHovering {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.black.opacity(0.6)))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isThumbHovering)
    }

    // MARK: 链接卡专属

    /// 链接 URL（payloadText 存完整 URL 原文）
    private var linkURL: URL? {
        URL(string: clip.payloadText ?? clip.preview)
    }

    /// 域名（加粗展示，防钓鱼设计）
    private var hostText: String {
        linkURL?.host ?? (clip.payloadText ?? clip.preview)
    }

    /// 路径 + query（弱化小字；根路径显示 "/"）
    private var pathText: String {
        guard let url = linkURL else { return "" }
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            path += "?\(query)"
        }
        return path
    }

    // MARK: 右侧操作按钮

    /// ⋮ 按钮（SF Symbol ellipsis 旋转 90°，与头部图标按钮同规格：13pt · DT.fg · 28×28 button 底；点击弹出更多菜单，携带按钮锚点 frame）
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

    // MARK: 元数据文本

    /// 文本卡附加段：字数（>1000 千分位）+ 富文本标记（format == "rtf"）
    private var textExtras: [String] {
        guard clip.kindEnum == .text else { return [] }
        var parts = ["\(formattedCharCount) 字"]
        if clip.format == "rtf" {
            parts.append("富文本")
        }
        return parts
    }

    /// 字数（payloadText 全文计；>1000 显示千分位）
    private var formattedCharCount: String {
        let count = clip.payloadText?.count ?? clip.preview.count
        guard count > 1000 else { return "\(count)" }
        return Self.decimalFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// 图片尺寸与格式（如「1280×800 · PNG」；缺数据显示 nil）
    private var imageDimensionText: String? {
        guard clip.kindEnum == .image else { return nil }
        var parts: [String] = []
        if let width = clip.pixelWidth, let height = clip.pixelHeight, width > 0, height > 0 {
            parts.append("\(width)×\(height)")
        }
        if let format = clip.format, !format.isEmpty {
            parts.append(format)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: 图片懒加载

    /// 加载来源图标与图片缩略图（每行一次；磁盘解码放到后台，避免滚动面板时阻塞主线程）
    private func loadImages() {
        // 来源 App 图标
        if let iconPath = clip.sourceIconPath {
            let url = AppIconStore.shared.fileURL(fileName: iconPath)
            Task {
                let image = await Task.detached {
                    AppIconStore.decodeCached(fileName: iconPath, url: url)
                }.value
                sourceIcon = image
            }
        }
        // 图片缩略图（缩略图名由原图名推导 "-thumb"，缺失回退原图）
        if clip.kindEnum == .image, let ref = clip.payloadRef {
            let thumbName = ImageStore.thumbName(for: ref)
            let thumbURL = ImageStore.shared.fileURL(name: thumbName)
            let origName = ref
            let origURL = ImageStore.shared.fileURL(name: origName)
            Task {
                let thumb = await Task.detached {
                    ImageStore.decodeCached(fileName: thumbName, url: thumbURL)
                }.value
                if let image = thumb {
                    thumbnail = image
                } else {
                    let orig = await Task.detached {
                        ImageStore.decodeCached(fileName: origName, url: origURL)
                    }.value
                    if let image = orig {
                        thumbnail = image
                    }
                }
            }
        }
    }
}
