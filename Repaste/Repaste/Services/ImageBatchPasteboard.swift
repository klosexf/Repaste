import AppKit
import ImageIO

/// Independent image files allow receiving chat apps to attach the whole batch.
/// This service has no dependency on history storage or the clipboard monitor.
@MainActor
enum ImageBatchPasteboard {
    struct Source {
        let data: Data
        let fileExtension: String
    }

    enum CopyError: Error, Equatable {
        case empty
        case invalidImage(Int)
        case writeFailed
    }

    @discardableResult
    static func write(_ sources: [Source], to pasteboard: NSPasteboard, cacheRoot: URL, ttlDays: Int = 7) throws -> [URL] {
        guard !sources.isEmpty else { throw CopyError.empty }
        // Validate the whole batch before exporting files or replacing the clipboard.
        for (index, source) in sources.enumerated() {
            guard let image = CGImageSourceCreateWithData(source.data as CFData, nil),
                  CGImageSourceCreateImageAtIndex(image, 0, nil) != nil else {
                throw CopyError.invalidImage(index + 1)
            }
        }
        let directory = cacheRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var published = false
        defer { if !published { try? FileManager.default.removeItem(at: directory) } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try sources.enumerated().map { index, source in
            // Only an extension is accepted; never allow path components from history data.
            let safeExtension = source.fileExtension.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let name = String(format: "%04d", index + 1) + "." + (safeExtension.isEmpty ? "png" : safeExtension)
            let url = directory.appendingPathComponent(name)
            try source.data.write(to: url, options: .atomic)
            return url
        }
        pasteboard.prepareForNewContents()
        guard pasteboard.writeObjects(urls.map { $0 as NSURL }) else { throw CopyError.writeFailed }
        published = true
        purgeExpiredCache(at: cacheRoot, keeping: urls, ttlDays: ttlDays)
        return urls
    }

    /// The current pasteboard owns its files until it is replaced, even after the TTL.
    static func purgeExpiredCache(at cacheRoot: URL, keeping urls: [URL], ttlDays: Int) {
        let activeDirectories = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL })
        let cutoff = Date().addingTimeInterval(-TimeInterval(max(1, ttlDays)) * 24 * 60 * 60)
        let oldBatches = (try? FileManager.default.contentsOfDirectory(
            at: cacheRoot, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])) ?? []
        for old in oldBatches where !activeDirectories.contains(old.standardizedFileURL) {
            guard UUID(uuidString: old.lastPathComponent) != nil,
                  let values = try? old.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory == true, let date = values.contentModificationDate, date < cutoff else { continue }
            try? FileManager.default.removeItem(at: old)
        }
    }
}
