import Foundation
import UIKit

enum TokenManagerError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case maxRetriesExceeded
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let message):
            return "HTTP Error \(code): \(message)"
        case .maxRetriesExceeded:
            return "Failed to fetch token after multiple attempts"
        case .networkError:
            return "Network error while fetching a Mapbox token"
        }
    }
}

private struct CachedMapboxToken: Codable {
    let token: String
    let city: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }

    init(token: String, city: String, ttlMinutes: Int = 55) {
        self.token = token
        self.city = city
        self.expiresAt = Date().addingTimeInterval(TimeInterval(ttlMinutes * 60))
    }
}

final class MapboxTokenManager {
    static let shared = MapboxTokenManager()
    private init() {}

    private let keychainTokenKeyPrefix = "com.safewalk.mapboxToken."

    private let maxRetries = 3
    private let baseDelaySeconds: Double = 1.0

    func fetchMapboxToken(for city: String) async throws -> String {
        let cacheKey = keychainTokenKeyPrefix + city.lowercased()

        if let cachedToken = loadCachedToken(key: cacheKey) {
            if !cachedToken.isExpired {
                let remainingMinutes = cachedToken.expiresAt.timeIntervalSinceNow / 60
                if remainingMinutes > 10 {
                    #if DEBUG
                    print("Cached token fresh for \(city), skipping validation (\(Int(remainingMinutes))m remaining).")
                    #endif
                    return cachedToken.token
                }
                let valid = await isTokenValid(cachedToken.token)
                if valid {
                    #if DEBUG
                    print("Cached token valid for \(city).")
                    #endif
                    return cachedToken.token
                }
            }
            deleteCachedToken(key: cacheKey)
            #if DEBUG
            print("Cached token invalid or expired, fetching new one.")
            #endif
        }

        let token = try await fetchWithRetry(city: city)

        let cached = CachedMapboxToken(token: token, city: city.lowercased())
        saveCachedToken(cached, key: cacheKey)
        #if DEBUG
        print("Stored new Mapbox token for \(city) in Keychain.")
        #endif

        return token
    }

    /// Clear all cached tokens (useful for logout or refresh)
    func clearAllCachedTokens() {
        let cities = ["atlanta", "boston", "chicago", "newyork", "philadelphia", "seattle"]
        for city in cities {
            let key = keychainTokenKeyPrefix + city
            deleteCachedToken(key: key)
        }
    }

    private func fetchWithRetry(city: String) async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await fetchNewTokenFromBackend(city: city)
            } catch {
                lastError = error

                let delay = baseDelaySeconds * pow(2.0, Double(attempt))
                let jitter = Double.random(in: 0...0.5)
                let totalDelay = delay + jitter

                #if DEBUG
                print("Token fetch attempt \(attempt + 1) failed, retrying in \(String(format: "%.1f", totalDelay))s...")
                #endif

                try await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
            }
        }

        throw lastError ?? TokenManagerError.maxRetriesExceeded
    }

    private func fetchNewTokenFromBackend(city: String) async throws -> String {
        do {
            let token = try await ApiService.shared.fetchMapboxToken(city: city)
            #if DEBUG
            print("Received new Mapbox token for \(city).")
            #endif
            return token
        } catch {
            throw TokenManagerError.networkError
        }
    }

    private func isTokenValid(_ token: String) async -> Bool {
        guard let url = URL(string: "https://api.mapbox.com/styles/v1/mapbox/streets-v12?access_token=\(token)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            #if DEBUG
            print("Token validation failed.")
            #endif
        }
        return false
    }

    private func saveCachedToken(_ token: CachedMapboxToken, key: String) {
        guard let data = try? JSONEncoder().encode(token) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        #if DEBUG
        if status != errSecSuccess {
            print("Failed to save token to Keychain: \(status)")
        }
        #endif
    }

    private func loadCachedToken(key: String) -> CachedMapboxToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = try? JSONDecoder().decode(CachedMapboxToken.self, from: data) else {
            return nil
        }

        return token
    }

    private func deleteCachedToken(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
