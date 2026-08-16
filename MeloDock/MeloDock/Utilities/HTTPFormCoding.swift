import Foundation

enum HTTPFormCoding {
    private static let allowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    static func encode(_ params: [String: String]) -> Data? {
        let body = params
            .map { key, value in
                let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? key
                let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
                return "\(escapedKey)=\(escapedValue)"
            }
            .sorted()
            .joined(separator: "&")

        return body.data(using: .utf8)
    }

    static func queryDictionary(from items: [URLQueryItem]?) -> [String: String] {
        Dictionary((items ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
}
