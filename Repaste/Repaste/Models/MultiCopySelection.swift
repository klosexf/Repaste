import Foundation

enum BatchCopyKind { case text, image }

enum BatchCopySeparator: String, CaseIterable, Identifiable {
    case newline, blankLine, space
    var id: String { rawValue }
    var value: String {
        switch self {
        case .newline: return "\n"
        case .blankLine: return "\n\n"
        case .space: return " "
        }
    }
    var title: String {
        switch self {
        case .newline: return "换行"
        case .blankLine: return "空行"
        case .space: return "空格"
        }
    }
}

struct MultiCopySelection {
    private(set) var ids: [UUID] = []
    private(set) var kind: BatchCopyKind?

    mutating func toggle(_ id: UUID, kind requestedKind: BatchCopyKind = .text) {
        guard kind == nil || kind == requestedKind else { return }
        kind = requestedKind
        if ids.contains(id) { remove(id) } else { ids.append(id) }
    }

    mutating func remove(_ id: UUID) {
        ids.removeAll { $0 == id }
        if ids.isEmpty { kind = nil }
    }

    mutating func move(_ id: UUID, by offset: Int) {
        guard let index = ids.firstIndex(of: id) else { return }
        let destination = index + offset
        guard ids.indices.contains(destination) else { return }
        ids.swapAt(index, destination)
    }

    /// Use the full available history here; a filter change must never discard selections.
    mutating func reconcile(with availableIDs: Set<UUID>) {
        ids.removeAll { !availableIDs.contains($0) }
        if ids.isEmpty { kind = nil }
    }

    mutating func clear() { ids.removeAll(); kind = nil }

    func position(of id: UUID) -> Int? {
        ids.firstIndex(of: id).map { $0 + 1 }
    }

    /// Missing payloads invalidate the batch rather than silently copying fewer records.
    func mergedText(from contents: [UUID: String], separator: BatchCopySeparator) -> String? {
        guard kind == .text, !ids.isEmpty else { return nil }
        let texts = ids.compactMap { contents[$0] }
        guard texts.count == ids.count else { return nil }
        return texts.joined(separator: separator.value)
    }

    static func textForSelection(kind: String, text: String?) -> String? {
        guard kind == "text" || kind == "link", let text, !text.isEmpty else { return nil }
        return text
    }
}
