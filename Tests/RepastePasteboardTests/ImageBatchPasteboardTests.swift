import AppKit
import Testing
@testable import RepastePasteboard

@MainActor
struct ImageBatchPasteboardTests {
    private func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.setColor(NSColor(deviceRed: 0.5, green: 0.3, blue: 0.9, alpha: 1), atX: 0, y: 0)
        return rep.representation(using: .png, properties: [:])!
    }

    @Test func independentOriginalFilesKeepOrderAndSurviveHistoryDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let board = NSPasteboard(name: .init("RepasteTests-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: root); board.releaseGlobally() }
        let data = [png(width: 240, height: 100), png(width: 80, height: 160)]
        let history = root.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        let originals = try data.enumerated().map { index, bytes in
            let original = history.appendingPathComponent("\(index).png")
            try bytes.write(to: original)
            return original
        }
        let sources = try originals.map { ImageBatchPasteboard.Source(data: try Data(contentsOf: $0), fileExtension: "png") }
        let urls = try ImageBatchPasteboard.write(sources, to: board, cacheRoot: root.appendingPathComponent("copies"))
        try FileManager.default.removeItem(at: history)
        #expect(board.pasteboardItems?.count == 2)
        let pastedURLs = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(pastedURLs == urls)
        #expect(try urls.map { try Data(contentsOf: $0) } == data)
        #expect(urls.map { NSImage(contentsOf: $0)!.size } == [NSSize(width: 240, height: 100), NSSize(width: 80, height: 160)])
        #expect(urls.allSatisfy { $0.pathExtension == "png" })
        #expect(urls[0].lastPathComponent < urls[1].lastPathComponent)
    }

    @Test func successfulCopyCleansOnlyExpiredOwnedBatches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let board = NSPasteboard(name: .init("RepasteTests-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: root); board.releaseGlobally() }
        let expired = root.appendingPathComponent(UUID().uuidString)
        let recent = root.appendingPathComponent(UUID().uuidString)
        let foreign = root.appendingPathComponent("other-data")
        for directory in [expired, recent, foreign] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let oldDate = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        for directory in [expired, foreign] {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: directory.path)
        }
        let urls = try ImageBatchPasteboard.write([.init(data: png(width: 20, height: 20), fileExtension: "png")], to: board, cacheRoot: root)
        #expect(!FileManager.default.fileExists(atPath: expired.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(FileManager.default.fileExists(atPath: foreign.path))
        #expect(FileManager.default.fileExists(atPath: urls[0].path))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: urls[0].deletingLastPathComponent().path)
        ImageBatchPasteboard.purgeExpiredCache(at: root, keeping: urls, ttlDays: 7)
        #expect(FileManager.default.fileExists(atPath: urls[0].path))
        ImageBatchPasteboard.purgeExpiredCache(at: root, keeping: [], ttlDays: 7)
        #expect(!FileManager.default.fileExists(atPath: urls[0].path))
    }

    @Test func invalidSecondImageLeavesClipboardAndCacheUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let board = NSPasteboard(name: .init("RepasteTests-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: root); board.releaseGlobally() }
        board.clearContents()
        board.setString("原剪贴板", forType: .string)
        let change = board.changeCount
        #expect(throws: ImageBatchPasteboard.CopyError.invalidImage(2)) {
            try ImageBatchPasteboard.write([
                .init(data: png(width: 60, height: 40), fileExtension: "png"),
                .init(data: Data("broken".utf8), fileExtension: "png"),
            ], to: board, cacheRoot: root)
        }
        #expect(board.changeCount == change)
        #expect(board.string(forType: .string) == "原剪贴板")
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func emptyBatchAndExportFailurePreserveClipboard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let board = NSPasteboard(name: .init("RepasteTests-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: root); board.releaseGlobally() }
        board.clearContents()
        board.setString("原剪贴板", forType: .string)
        #expect(throws: ImageBatchPasteboard.CopyError.empty) {
            try ImageBatchPasteboard.write([], to: board, cacheRoot: root)
        }
        try Data("file blocks directory".utf8).write(to: root)
        #expect(throws: (any Error).self) {
            try ImageBatchPasteboard.write([.init(data: png(width: 20, height: 20), fileExtension: "png")], to: board, cacheRoot: root)
        }
        #expect(board.string(forType: .string) == "原剪贴板")
    }
}
