import Foundation

/// Pure helpers for persisting cover art that Music.app hands us as raw bytes
/// (used when neither MusicKit nor iTunes Search can supply an artwork URL).
enum MusicArtworkFileStore {
    static let directoryName = "MeloDockArtwork"
    static let maxBytes = 10 * 1024 * 1024
    static let maxFiles = 50

    /// Stable, filesystem-safe filename for an artwork cache key (FNV-1a 64-bit).
    static func fileName(forKey key: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx.img", hash)
    }

    /// True when `data` is non-empty, within the size cap, and starts with a PNG, JPEG or TIFF signature.
    static func isValidImageData(_ data: Data) -> Bool {
        guard data.isEmpty == false, data.count <= maxBytes else { return false }
        let bytes = [UInt8](data.prefix(4))
        guard bytes.count == 4 else { return false }
        if bytes == [0x89, 0x50, 0x4E, 0x47] { return true }          // PNG
        if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF { return true } // JPEG
        if bytes == [0x49, 0x49, 0x2A, 0x00] || bytes == [0x4D, 0x4D, 0x00, 0x2A] { return true } // TIFF
        return false
    }

    static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Writes (overwriting by key) and prunes the directory to `maxFiles`. Returns nil for invalid data or I/O failure.
    static func store(_ data: Data, forKey key: String, in directory: URL) -> URL? {
        guard isValidImageData(data), key.isEmpty == false else { return nil }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(fileName(forKey: key))
            try data.write(to: url, options: .atomic)
            prune(directory: directory, keeping: url)
            return url
        } catch {
            return nil
        }
    }

    static func prune(directory: URL, keeping keep: URL, limit: Int = maxFiles) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > limit else { return }
        let dated = files.map { url -> (URL, Date) in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url, date)
        }.sorted { $0.1 < $1.1 }
        let candidates = dated.filter { $0.0 != keep }
        for (url, _) in candidates.prefix(files.count - limit) {
            try? fm.removeItem(at: url)
        }
    }
}
