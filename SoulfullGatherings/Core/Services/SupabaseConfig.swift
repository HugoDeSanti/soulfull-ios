import Foundation

enum SupabaseConfig {
    static let url: URL = {
        let host = plistValue(for: "SupabaseHost")
        guard let url = URL(string: "https://\(host)") else {
            fatalError("SupabaseHost '\(host)' could not form a valid URL")
        }
        return url
    }()

    static let anonKey: String = plistValue(for: "SupabaseAnonKey")

    private static func plistValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("YOUR_") else {
            fatalError("'\(key)' is missing or unfilled in Config/Secrets.xcconfig")
        }
        return value
    }
}
