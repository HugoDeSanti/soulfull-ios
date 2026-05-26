import Foundation

enum SupabaseConfig {

    enum ConfigError: LocalizedError {
        case missingKey(String)
        case malformedHost(String)

        var errorDescription: String? {
            switch self {
            case .missingKey(let key):
                return "'\(key)' is missing or unfilled. Copy Config/Secrets.xcconfig.example → Config/Secrets.xcconfig."
            case .malformedHost(let host):
                return "'\(host)' could not form a valid URL."
            }
        }
    }

    static func make() throws -> (url: URL, anonKey: String) {
        let host = try plistValue(for: "SupabaseHost")
        guard let url = URL(string: "https://\(host)") else {
            throw ConfigError.malformedHost(host)
        }
        let key = try plistValue(for: "SupabaseAnonKey")
        return (url, key)
    }

    private static func plistValue(for key: String) throws -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("YOUR_") else {
            throw ConfigError.missingKey(key)
        }
        return value
    }
}
