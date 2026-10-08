import SwiftUI

/// Numbered check circle shared by history and template rows.
struct BatchSelectionBadge: View {
    let number: Int?
    var isEnabled = true

    var body: some View {
        ZStack {
            Circle().fill(number != nil ? DT.accentBtn : Color.clear)
            Circle().strokeBorder(number != nil ? DT.accent : DT.muted2, lineWidth: 1)
            if let number {
                Text("\(number)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else if !isEnabled {
                Image(systemName: "minus").font(.system(size: 8)).foregroundStyle(DT.muted2)
            }
        }
        .frame(width: 21, height: 21)
        .accessibilityHidden(true)
    }
}

struct BatchSeparatorPicker: View {
    @Binding var selection: BatchCopySeparator

    var body: some View {
        Picker("分隔方式", selection: $selection) {
            ForEach(BatchCopySeparator.allCases) { separator in
                Text(separator.title).tag(separator)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .foregroundStyle(DT.fg)
        .environment(\.colorScheme, .dark)
        .frame(width: 72)
        .accessibilityLabel("分隔方式")
    }
}

/// Only appears during multi-selection; no persistent explanatory row.
struct MultiCopyFooter: View {
    let viewModel: PanelViewModel

    var body: some View {
        @Bindable var model = viewModel
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isImageBatch ? "已选 \(model.batchSelection.ids.count) 张" : "已选 \(model.batchSelection.ids.count) 项")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DT.fg)
                if model.hiddenBatchSelectionCount > 0 {
                    Text("含 \(model.hiddenBatchSelectionCount) 项筛选外内容")
                        .font(.system(size: 10))
                        .foregroundStyle(DT.muted)
                }
            }
            Spacer(minLength: 0)
            if !model.isImageBatch { BatchSeparatorPicker(selection: $model.copySeparator) }
            SolidButton(title: "预览") { model.openBatchPreview() }
                .disabled(model.batchSelection.ids.isEmpty)
            DialogPrimaryButton(title: model.batchCopyTitle) {
                model.copySelectedBatch()
            }
            .disabled(!model.canCopyBatch)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(DT.surface3)
    }
}

/// In-panel preview: ordering affects only this batch, never persistent template order.
struct MultiCopyPreview: View {
    let viewModel: PanelViewModel
    let availableHeight: CGFloat

    var body: some View {
        @Bindable var model = viewModel
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.isImageBatch ? "图片预览" : "合并预览")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DT.fgStrong)
                Spacer()
                Button { model.closeBatchPreview() } label: {
                    Image(systemName: "xmark").foregroundStyle(DT.muted)
                }
                .buttonStyle(.plain)
                .help("关闭预览")
                .accessibilityLabel("关闭预览")
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(model.batchClips.enumerated()), id: \.element.id) { index, clip in
                        HStack(spacing: 8) {
                            BatchSelectionBadge(number: index + 1)
                            if model.isImageBatch, let ref = clip.payloadRef {
                                BatchImageThumbnail(reference: ref)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(clip.preview).font(.system(size: 12)).foregroundStyle(DT.fg).lineLimit(1)
                                if model.isImageBatch {
                                    Text(model.batchKindDescription(clip))
                                        .font(.system(size: 10)).foregroundStyle(DT.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            orderButton("arrow.up", title: "上移第 \(index + 1) 项", disabled: index == 0) {
                                model.moveBatchItem(clip.id, by: -1)
                            }
                            orderButton("arrow.down", title: "下移第 \(index + 1) 项", disabled: index == model.batchClips.count - 1) {
                                model.moveBatchItem(clip.id, by: 1)
                            }
                            orderButton("xmark", title: "移除第 \(index + 1) 项", disabled: false) {
                                model.removeBatchItem(clip.id)
                            }
                        }
                        .padding(7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DT.surface3))
                    }
                }
            }
            .frame(height: model.isImageBatch
                ? max(44, min(250, availableHeight * 0.58, CGFloat(model.batchClips.count) * 78))
                : max(44, min(105, availableHeight * 0.24)))
            if !model.isImageBatch {
                HStack {
                    Text("粘贴内容").font(.system(size: 11)).foregroundStyle(DT.muted)
                    Spacer()
                    BatchSeparatorPicker(selection: $model.copySeparator)
                }
                ScrollView {
                    Text(model.mergedBatchText ?? "尚未选择内容")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.fg)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: max(48, min(110, availableHeight * 0.26)))
                .background(RoundedRectangle(cornerRadius: 8).fill(DT.panel))
            }
            HStack {
                Text(model.isImageBatch ? "\(model.batchSelection.ids.count) 张图片" : "\(model.batchSelection.ids.count) 项")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DT.muted)
                Spacer()
                SolidButton(title: "返回选择") { model.closeBatchPreview() }
                DialogPrimaryButton(title: model.batchCopyTitle) {
                    model.copySelectedBatch()
                }
                .disabled(!model.canCopyBatch)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: DT.dialogRadius).fill(DT.menuSurface))
        .overlay(RoundedRectangle(cornerRadius: DT.dialogRadius).strokeBorder(DT.strokeStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    private func orderButton(_ icon: String, title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(DT.fg)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(DT.button))
        }
        .buttonStyle(.mattePress)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct BatchImageThumbnail: View {
    let reference: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(DT.muted) }
        }
        .frame(width: 64, height: 58)
        .background(RoundedRectangle(cornerRadius: 6).fill(DT.panel))
        .task(id: reference) {
            image = ImageStore.shared.load(name: reference)
                ?? ImageStore.shared.load(name: ImageStore.thumbName(for: reference))
        }
        .accessibilityHidden(true)
    }
}
