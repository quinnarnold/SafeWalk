import Foundation
import DeviceCheck
import CryptoKit
import os

private let appAttestLog = Logger(subsystem: "com.safewalk", category: "AppAttest")

/// Manages App Attest key lifecycle: generation, attestation, and per-request assertion.
///
/// On first launch, generates a hardware-backed key, attests it with the server using a
/// challenge-response flow, and stores the key ID in Keychain. On subsequent requests,
/// generates assertions that the backend verifies against the stored public key.
///
/// Falls back gracefully on simulator and DEBUG builds where App Attest is unavailable.
actor AppAttestService {
    static let shared = AppAttestService()

    private let keychainAccount = "com.safewalk.appAttestKeyId"
    private let firstLaunchDefaultsKey = "com.safewalk.appAttest.installSeen"
    private let baseURL = AppConfiguration.apiBaseURL
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private(set) var keyId: String?
    private var isAttested = false
    private var attestationInProgress: Task<Bool, Error>?

    private init() {}

    func configure() {
        purgeKeychainIfFreshInstall()
        keyId = loadKeyIdFromKeychain()
        if keyId != nil {
            isAttested = true
            appAttestLog.info("configure: loaded keyId from Keychain, isAttested=true")
        } else {
            appAttestLog.info("configure: no keyId in Keychain, attestation required")
        }
    }

    private func purgeKeychainIfFreshInstall() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: firstLaunchDefaultsKey) {
            return
        }
        let deleted = deleteKeyIdFromKeychain()
        defaults.set(true, forKey: firstLaunchDefaultsKey)
        appAttestLog.info("fresh install detected, purged stale Keychain keyId (deleted=\(deleted, privacy: .public))")
    }

    var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 14.0, *) {
            return DCAppAttestService.shared.isSupported
        }
        return false
        #endif
    }

    /// Ensure the device has an attested key, performing the full attestation flow if needed.
    func ensureAttested(city: String = "boston") async throws {
        if isAttested && keyId != nil {
            appAttestLog.info("ensureAttested: already attested, skipping")
            return
        }

        if let existing = attestationInProgress {
            appAttestLog.info("ensureAttested: reusing in-flight attestation task")
            _ = try await existing.value
            return
        }

        appAttestLog.info("ensureAttested: starting attestation flow for city=\(city, privacy: .public)")
        let task = Task<Bool, Error> {
            defer { attestationInProgress = nil }
            try await performAttestation(city: city)
            return true
        }
        attestationInProgress = task
        _ = try await task.value
    }

    /// Reset attestation state, forcing a full re-attestation on the next request.
    ///
    /// Call when the server returns the credential-not-found recovery code,
    /// indicating that the backend no longer has the stored public key.
    func clearAttestation() {
        isAttested = false
        keyId = nil
        deleteKeyIdFromKeychain()
        appAttestLog.info("clearAttestation: reset, will re-attest on next request")
    }

    /// Generate an assertion for the given request data.
    ///
    /// Returns base64-encoded assertion data, or nil if App Attest is not available.
    func generateAssertion(for requestData: Data) async throws -> String? {
        guard isAvailable, let keyId = keyId, isAttested else {
            return nil
        }

        let clientDataHash = Data(SHA256.hash(data: requestData))
        let assertionData = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
        return assertionData.base64EncodedString()
    }

    private func performAttestation(city: String) async throws {
        guard isAvailable else {
            appAttestLog.warning("performAttestation: DCAppAttestService not available on this device")
            return
        }

        appAttestLog.info("performAttestation: generating hardware key")
        let newKeyId: String
        do {
            newKeyId = try await DCAppAttestService.shared.generateKey()
        } catch {
            appAttestLog.error("generateKey failed")
            throw error
        }
        appAttestLog.info("performAttestation: generated key")

        let challenge: String
        do {
            challenge = try await fetchChallenge(city: city)
        } catch {
            appAttestLog.error("fetchChallenge failed")
            throw error
        }
        appAttestLog.info("performAttestation: got challenge")

        let challengeData = Data(challenge.utf8)
        let clientDataHash = Data(SHA256.hash(data: challengeData))

        let attestationData: Data
        do {
            attestationData = try await DCAppAttestService.shared.attestKey(newKeyId, clientDataHash: clientDataHash)
        } catch {
            appAttestLog.error("attestKey failed")
            throw error
        }
        appAttestLog.info("performAttestation: attestKey succeeded (\(attestationData.count, privacy: .public) bytes)")

        do {
            try await sendAttestation(
                city: city,
                keyId: newKeyId,
                attestation: attestationData,
                challenge: challenge
            )
        } catch {
            appAttestLog.error("sendAttestation failed")
            throw error
        }

        saveKeyIdToKeychain(newKeyId)
        keyId = newKeyId
        isAttested = true
        appAttestLog.info("performAttestation: complete, keyId stored in Keychain")
    }

    private func fetchChallenge(city: String) async throws -> String {
        let url = baseURL
            .appendingPathComponent(city)
            .appendingPathComponent("attest")
            .appendingPathComponent("challenge")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        appAttestLog.info("fetchChallenge: GET \(url.absoluteString, privacy: .public)")
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            appAttestLog.error("fetchChallenge: non-200 status=\(status, privacy: .public)")
            throw AppAttestError.challengeFetchFailed
        }

        struct ChallengeResponse: Decodable {
            let challenge: String
        }

        let decoded = try JSONDecoder().decode(ChallengeResponse.self, from: data)
        return decoded.challenge
    }

    private func sendAttestation(city: String, keyId: String, attestation: Data, challenge: String) async throws {
        let url = baseURL
            .appendingPathComponent(city)
            .appendingPathComponent("attest")
            .appendingPathComponent("verify")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "keyId": keyId,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        appAttestLog.info("sendAttestation: POST \(url.absoluteString, privacy: .public)")
        let (_, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            appAttestLog.error("sendAttestation: rejected with status=\(status, privacy: .public)")
            throw AppAttestError.attestationRejected
        }
        appAttestLog.info("sendAttestation: 200 OK")
    }

    private func loadKeyIdFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    @discardableResult
    private func deleteKeyIdFromKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }

    @discardableResult
    private func saveKeyIdToKeychain(_ keyId: String) -> Bool {
        guard let data = keyId.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        return status == errSecSuccess
    }
}

enum AppAttestError: LocalizedError {
    case invalidURL
    case challengeFetchFailed
    case attestationRejected
    case assertionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid attestation URL"
        case .challengeFetchFailed:
            return "Failed to fetch attestation challenge"
        case .attestationRejected:
            return "Attestation rejected"
        case .assertionFailed:
            return "Failed to generate assertion"
        }
    }
}
