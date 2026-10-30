#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class MusicArtworkFileStoreTests: XCTestCase {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])

    func testFileNameIsStableAndKeyed() {
        XCTAssertEqual(MusicArtworkFileStore.fileName(forKey: "survival|skye newman"),
                       MusicArtworkFileStore.fileName(forKey: "survival|skye newman"))
        XCTAssertNotEqual(MusicArtworkFileStore.fileName(forKey: "a|b"),
                          MusicArtworkFileStore.fileName(forKey: "a|c"))
        XCTAssertFalse(MusicArtworkFileStore.fileName(forKey: "a/b|../c").contains("/"))
    }

    func testValidation() {
        XCTAssertTrue(MusicArtworkFileStore.isValidImageData(png))
        XCTAssertTrue(MusicArtworkFileStore.isValidImageData(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        XCTAssertFalse(MusicArtworkFileStore.isValidImageData(Data()))
        XCTAssertFalse(MusicArtworkFileStore.isValidImageData(Data("missing value".utf8)))
        XCTAssertFalse(MusicArtworkFileStore.isValidImageData(Data(count: MusicArtworkFileStore.maxBytes + 1)))
    }

    func testStoreOverwritesByKeyRejectsInvalidAndPrunes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertNil(MusicArtworkFileStore.store(Data("nope".utf8), forKey: "k", in: dir))
        let first = try XCTUnwrap(MusicArtworkFileStore.store(png, forKey: "k", in: dir))
        let second = try XCTUnwrap(MusicArtworkFileStore.store(png, forKey: "k", in: dir))
        XCTAssertEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), png)

        for i in 0..<5 { _ = MusicArtworkFileStore.store(png, forKey: "k\(i)", in: dir) }
        MusicArtworkFileStore.prune(directory: dir, keeping: first, limit: 3)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 3)
    }
}
#endif
