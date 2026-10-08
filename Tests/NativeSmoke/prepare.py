"""Build an isolated, in-memory native smoke app using the production panel code.

Run: python3 Tests/NativeSmoke/prepare.py
Open the printed app path. Startup checks write results.json beside the app project.
The test app has its own bundle ID, no clipboard monitoring and no global hotkey.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
scratch = Path(tempfile.mkdtemp(prefix="repaste-multi-copy-smoke-"))
shutil.copytree(repo / "Repaste", scratch / "Repaste", ignore=shutil.ignore_patterns("xcuserdata", ".DS_Store"))
source = scratch / "Repaste/Repaste"
provider = source / "Services/ModelContainerProvider.swift"
provider.write_text(provider.read_text().replace(
    "ModelConfiguration(schema: schema)", "ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)"))
event_log = source / "Services/EventLog.swift"
event_log.write_text(event_log.read_text().replace(
    'let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]',
    f'let support = URL(fileURLWithPath: "{scratch}")'))
for name in ["ImageStore.swift", "PasteboardWriter.swift"]:
    file = source / "Services" / name
    file.write_text(file.read_text().replace(
        'let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]',
        f'let support = URL(fileURLWithPath: "{scratch}")'))

entry = source / "RepasteApp.swift"
original = entry.read_text()
bridge = original[original.index("// MARK: - 窗口管理桥"):]
entry.write_text(r'''
import SwiftUI
import AppKit

@main
struct RepasteSmokeApp: App {
    @NSApplicationDelegateAdaptor(SmokeDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class SmokeDelegate: NSObject, NSApplicationDelegate {
    func makeImage(width: Int, height: Int, color: NSColor, title: String) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        (title as NSString).draw(at: NSPoint(x: 36, y: height / 2), withAttributes: [
            .font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor.white])
        ("REPASTE  •  ORIGINAL IMAGE" as NSString).draw(at: NSPoint(x: 36, y: 36), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore.shared
        settings.pasteTarget = "clipboard"
        settings.enableAppFilter = true
        settings.rememberAppFilter = false
        settings.recordingEnabled = true
        settings.defaultTab = "all"
        settings.sortMode = "recent_used"

        let store = ClipboardStore.shared
        let first = Clip(kind: .text, preview: "第一段文字", payloadText: "第一段文字\n保留原有换行", sourceBundleId: "demo.notes", sourceAppName: "备忘录")
        let link = Clip(kind: .link, preview: "https://example.com/repaste", payloadText: "https://example.com/repaste", sourceBundleId: "demo.browser", sourceAppName: "浏览器")
        let second = Clip(kind: .text, preview: "第二段文字", payloadText: "第二段文字", sourceBundleId: "demo.notes", sourceAppName: "备忘录")
        let image = Clip(kind: .image, preview: "演示图片.png", sourceAppName: "演示")
        let file = Clip(kind: .file, preview: "演示文件", payloadText: "/tmp/demo")
        let firstImageData = makeImage(width: 640, height: 360, color: NSColor(deviceRed: 0.42, green: 0.25, blue: 0.84, alpha: 1), title: "IMAGE 01")
        let secondImageData = makeImage(width: 480, height: 640, color: NSColor(deviceRed: 0.05, green: 0.55, blue: 0.50, alpha: 1), title: "IMAGE 02")
        let firstRef = ImageStore.shared.save(data: firstImageData, format: "PNG").originalName
        let secondRef = ImageStore.shared.save(data: secondImageData, format: "PNG").originalName
        let firstImage = Clip(kind: .image, preview: "紫色横图.png", payloadRef: firstRef, sourceAppName: "演示", pixelWidth: 640, pixelHeight: 360, format: "PNG")
        let secondImage = Clip(kind: .image, preview: "绿色竖图.png", payloadRef: secondRef, sourceAppName: "演示", pixelWidth: 480, pixelHeight: 640, format: "PNG")
        [first, link, second, image, file, firstImage, secondImage].forEach { store.insert(clip: $0) }
        let group = store.createGroup(name: "常用模板")
        let template = store.addTemplate(text: "模板回复", groupId: group.id)
        let model = PanelController.shared.viewModel
        model.prepareForDisplay()
        var checks: [String: Bool] = [:]
        model.toggleMultiSelection()
        model.activateRow(first)
        model.activateRow(link)
        let ids = model.batchSelection.ids
        model.searchText = "不存在的关键词"
        checks["search_preserves_selection"] = model.batchSelection.ids == ids && model.filteredClips.isEmpty && model.hiddenBatchSelectionCount == 2
        model.searchText = ""
        model.selectedTab = .text
        model.selectedSourceFilter = "demo.browser"
        checks["tab_and_source_preserve_selection"] = model.batchSelection.ids == ids
        model.selectedTab = .group(group.id)
        model.activateRow(template)
        checks["template_joins_history_batch"] = model.batchSelection.ids == ids + [template.id]
        model.activateRow(image)
        model.activateRow(file)
        checks["unsupported_types_ignored"] = model.batchSelection.ids == ids + [template.id]
        model.openBatchPreview()
        model.moveBatchItem(template.id, by: -1)
        checks["preview_reorders_full_payload"] = model.mergedBatchText == "第一段文字\n保留原有换行\n模板回复\nhttps://example.com/repaste"
        model.removeBatchItem(template.id)
        model.copySeparator = .blankLine
        checks["separator_preserves_internal_newline"] = model.mergedBatchText == "第一段文字\n保留原有换行\n\nhttps://example.com/repaste"
        model.reload()
        checks["reload_preserves_batch"] = model.batchSelection.ids == ids
        model.copySelectedBatch()
        checks["single_plain_text_clipboard_payload"] = NSPasteboard.general.string(forType: .string) == "第一段文字\n保留原有换行\n\nhttps://example.com/repaste" && NSPasteboard.general.pasteboardItems?.count == 1
        checks["copy_clears_mode_and_preview"] = !model.isMultiSelecting && !model.isBatchPreviewPresented && model.batchSelection.ids.isEmpty
        checks["batch_records_usage"] = first.lastUsedAt != nil && link.lastUsedAt != nil
        model.toggleMultiSelection()
        model.activateRow(first)
        model.activateRow(second)
        model.delete(clip: second)
        checks["delete_prunes_batch"] = model.batchSelection.ids == [first.id]
        model.undoDelete(clipId: second.id)
        model.persistOnHide()
        checks["hide_clears_batch"] = !model.isMultiSelecting && model.batchSelection.ids.isEmpty
        model.toggleMultiSelection()
        model.activateRow(firstImage)
        model.activateRow(first)
        model.activateRow(secondImage)
        checks["image_batch_locks_category"] = model.isImageBatch && model.batchSelection.ids == [firstImage.id, secondImage.id]
        checks["missing_original_is_disabled"] = !model.canBatchSelect(image) && model.batchUnavailableReason(image) == "原图已清理"
        model.selectedSourceFilter = nil
        model.selectedTab = .image
        model.searchText = "紫色"
        checks["image_search_preserves_batch"] = model.hiddenBatchSelectionCount == 1 && model.batchSelection.ids.count == 2
        model.openBatchPreview()
        model.moveBatchItem(secondImage.id, by: -1)
        checks["image_preview_reorders"] = model.batchClips.map(\.id) == [secondImage.id, firstImage.id] && model.canCopyBatch && model.isBatchPreviewPresented && model.mergedBatchText == nil
        model.copySelectedBatch()
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        checks["image_batch_has_two_independent_items"] = NSPasteboard.general.pasteboardItems?.count == 2 && urls.count == 2
        checks["image_batch_preserves_original_bytes_and_order"] = urls.count == 2 && (try? Data(contentsOf: urls[0])) == secondImageData && (try? Data(contentsOf: urls[1])) == firstImageData
        checks["image_copy_records_usage_and_exits"] = firstImage.lastUsedAt != nil && secondImage.lastUsedAt != nil && !model.isMultiSelecting && !model.isBatchPreviewPresented
        model.toggleMultiSelection()
        model.activateRow(firstImage)
        model.activateRow(secondImage)
        try! FileManager.default.removeItem(at: ImageStore.shared.fileURL(name: secondRef))
        checks["copied_files_survive_original_removal"] = urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
        let changeCount = NSPasteboard.general.changeCount
        model.copySelectedBatch()
        checks["missing_original_keeps_selection_and_clipboard"] = model.isMultiSelecting && model.batchSelection.ids.count == 2 && NSPasteboard.general.changeCount == changeCount
        try! secondImageData.write(to: ImageStore.shared.fileURL(name: secondRef))
        model.cancelMultiSelection()
        model.searchText = ""
        model.selectedSourceFilter = nil
        model.selectedTab = .image
        model.copySeparator = .newline
        let result = ["passed": checks.values.allSatisfy { $0 }, "checks": checks] as [String: Any]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: "SMOKE_RESULTS_PATH"))
        PanelController.shared.show(mode: .centered)
    }
}
'''.replace("SMOKE_RESULTS_PATH", str(scratch / "results.json")) + bridge)

env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
log = scratch / "build.log"
with log.open("w") as output:
    result = subprocess.run([
        "xcodebuild", "-project", str(scratch / "Repaste/Repaste.xcodeproj"), "-scheme", "Repaste",
        "-configuration", "Debug", "-derivedDataPath", str(scratch / "build"),
        "PRODUCT_BUNDLE_IDENTIFIER=com.xiaofengchen.Repaste.MultiCopySmoke", "CODE_SIGNING_ALLOWED=NO", "build",
    ], env=env, stdout=output, stderr=subprocess.STDOUT)
if result.returncode:
    print(log.read_text())
    raise SystemExit(result.returncode)
print(f"APP={scratch / 'build/Build/Products/Debug/Repaste.app'}")
print(f"RESULTS={scratch / 'results.json'}")
print(f"BUILD_LOG={log}")
