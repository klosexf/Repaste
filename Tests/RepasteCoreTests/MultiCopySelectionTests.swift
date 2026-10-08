import Foundation
import Testing
@testable import RepasteCore

struct MultiCopySelectionTests {
    let first = UUID()
    let second = UUID()
    let third = UUID()

    @Test func selectingUsesClickOrderAndReselectingAppends() {
        var selection = MultiCopySelection()
        selection.toggle(second)
        selection.toggle(first)
        #expect(selection.ids == [second, first])
        #expect(selection.position(of: first) == 2)
        selection.toggle(second)
        #expect(selection.ids == [first])
        selection.toggle(second)
        #expect(selection.ids == [first, second])
    }

    @Test func previewCanMoveAndRemoveWithoutChangingHistory() {
        var selection = MultiCopySelection()
        [first, second, third].forEach { selection.toggle($0) }
        selection.move(third, by: -1)
        #expect(selection.ids == [first, third, second])
        selection.move(first, by: -1)
        selection.move(second, by: 1)
        selection.move(UUID(), by: -1)
        #expect(selection.ids == [first, third, second])
        selection.remove(third)
        #expect(selection.ids == [first, second])
        selection.clear()
        #expect(selection.ids.isEmpty)
    }

    @Test func refreshingPrunesDeletedItemsAndKeepsSelectionOrder() {
        var selection = MultiCopySelection()
        [third, first, second].forEach { selection.toggle($0) }
        // Reconcile against all available records, never against filtered rows.
        selection.reconcile(with: Set([second, third]))
        #expect(selection.ids == [third, second])
        #expect(selection.position(of: second) == 2)
    }

    @Test func mergingUsesFullPayloadAndPreservesInternalWhitespace() {
        var selection = MultiCopySelection()
        selection.toggle(second)
        selection.toggle(first)
        let longText = "  第一段\n第二段  " + String(repeating: "正文", count: 250)
        let link = "https://example.com/path?q=hello"
        #expect(selection.mergedText(from: [first: longText, second: link], separator: .newline)
            == link + "\n" + longText)
    }

    @Test(arguments: BatchCopySeparator.allCases)
    func separatorsOnlyChangeTheBoundary(_ separator: BatchCopySeparator) {
        var selection = MultiCopySelection()
        selection.toggle(first)
        selection.toggle(second)
        #expect(selection.mergedText(from: [first: "A\nB", second: "C"], separator: separator)
            == "A\nB" + separator.value + "C")
    }

    @Test func emptyOrIncompleteSelectionCannotProducePartialCopy() {
        var selection = MultiCopySelection()
        #expect(selection.mergedText(from: [:], separator: .newline) == nil)
        selection.toggle(first)
        selection.toggle(second)
        #expect(selection.mergedText(from: [first: "A"], separator: .newline) == nil)
    }

    @Test func onlyTextAndLinksWithFullPayloadCanBeSelected() {
        #expect(MultiCopySelection.textForSelection(kind: "text", text: "原文\n") == "原文\n")
        #expect(MultiCopySelection.textForSelection(kind: "link", text: "https://example.com") != nil)
        #expect(MultiCopySelection.textForSelection(kind: "image", text: "图片") == nil)
        #expect(MultiCopySelection.textForSelection(kind: "file", text: "/tmp/file") == nil)
        #expect(MultiCopySelection.textForSelection(kind: "text", text: nil) == nil)
        #expect(MultiCopySelection.textForSelection(kind: "text", text: "") == nil)
    }

    @Test func imageBatchRejectsMixedContentAndUnlocksWhenEmptied() {
        var selection = MultiCopySelection()
        selection.toggle(first, kind: .image)
        selection.toggle(second, kind: .text)
        #expect(selection.ids == [first])
        selection.toggle(third, kind: .image)
        #expect(selection.ids == [first, third])
        #expect(selection.mergedText(from: [first: "fake", third: "text"], separator: .newline) == nil)
        selection.reconcile(with: [])
        #expect(selection.kind == nil)
        selection.toggle(second)
        #expect(selection.kind == .text)
        selection.toggle(first, kind: .image)
        #expect(selection.ids == [second])
        selection.remove(second)
        #expect(selection.kind == nil)
        selection.toggle(first, kind: .image)
        selection.clear()
        #expect(selection.kind == nil)
    }
}
