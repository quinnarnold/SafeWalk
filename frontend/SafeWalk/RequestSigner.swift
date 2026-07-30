import Foundation
import CryptoKit
import os

private let signerLog = Logger(subsystem: "com.safewalk", category: "RequestSigner")

/// Signs API requests using App Attest assertions.
enum RequestSigner {
    private static let queryAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    /// Sign a URL request with an App Attest assertion.
    static func sign(_ request: URLRequest) async -> URLRequest {
        if await AppAttestService.shared.isAvailable {
            if let signed = await signWithAppAttest(request) {
                return signed
            }
            signerLog.warning("sign: App Attest signing returned nil for \(request.httpMethod ?? "?", privacy: .public) \(request.url?.path ?? "?", privacy: .public)")
        } else {
            signerLog.info("sign: App Attest unavailable")
        }
        return request
    }

    private static func signWithAppAttest(_ request: URLRequest) async -> URLRequest? {
        var signedRequest = request

        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let path = components.path
        let method = (request.httpMethod ?? "GET").uppercased()
        let timestamp = Int(Date().timeIntervalSince1970)
        let query = (components.queryItems ?? [])
            .sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }
            .map {
                let name = $0.name.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? ""
                let value = ($0.value ?? "").addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? ""
                return "\(name)=\(value)"
            }
            .joined(separator: "&")
        let bodyHash = SHA256.hash(data: request.httpBody ?? Data())
            .map { String(format: "%02x", $0) }
            .joined()
        let payload = [String(timestamp), method, path, query, bodyHash].joined(separator: "\n")
        let payloadData = Data(payload.utf8)
        signerLog.debug("signWithAppAttest: signing \(method, privacy: .public) \(path, privacy: .public)")

        do {
            guard let assertion = try await AppAttestService.shared.generateAssertion(for: payloadData) else {
                signerLog.warning("signWithAppAttest: generateAssertion returned nil (not attested?)")
                return nil
            }

            guard let keyId = await AppAttestService.shared.keyId else {
                signerLog.warning("signWithAppAttest: keyId nil after successful assertion")
                return nil
            }

            signedRequest.setValue(keyId, forHTTPHeaderField: "X-App-Attest-KeyId")
            signedRequest.setValue(assertion, forHTTPHeaderField: "X-App-Attest-Assertion")
            signedRequest.setValue(String(timestamp), forHTTPHeaderField: "X-Timestamp")

            signerLog.info("signWithAppAttest: signed \(method, privacy: .public) \(path, privacy: .public)")
            return signedRequest
        } catch {
            signerLog.error("signWithAppAttest: generateAssertion failed")
            return nil
        }
    }
}
