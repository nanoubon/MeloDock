#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class HTTPFormCodingTests: XCTestCase {
    func testEncodesReservedCharactersInFormBody() throws {
        let data = HTTPFormCoding.encode([
            "code": "a+b=c&d",
            "redirect_uri": "melodock://spotify-auth"
        ])

        let body = String(data: XCTUnwrap(data), encoding: .utf8)
        XCTAssertEqual(
            body,
            "code=a%2Bb%3Dc%26d&redirect_uri=melodock%3A%2F%2Fspotify-auth"
        )
    }

    func testQueryDictionaryKeepsLastDuplicateKey() {
        let items = [
            URLQueryItem(name: "state", value: "first"),
            URLQueryItem(name: "code", value: "abc"),
            URLQueryItem(name: "state", value: "second")
        ]

        let query = HTTPFormCoding.queryDictionary(from: items)
        XCTAssertEqual(query["state"], "second")
        XCTAssertEqual(query["code"], "abc")
    }
}
#endif
