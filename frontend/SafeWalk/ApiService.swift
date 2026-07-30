import Foundation
import Turf
import MapboxMaps
import os

private let apiLog = Logger(subsystem: "com.safewalk", category: "ApiService")

struct City: Codable, Hashable {
    let name: String
    let center: [Double]
    let defaultZoom: Int
}

struct CitiesResponse: Codable {
    let cities: [City]
}

enum ApiError: LocalizedError {
    case invalidURL
    case noData
    case httpError(statusCode: Int, message: String)
    case decodingError
    case networkError
    case authenticationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received from server"
        case .httpError(let code, let message):
            return "HTTP Error \(code): \(message)"
        case .decodingError:
            return "Failed to decode the server response"
        case .networkError:
            return "Network request failed"
        case .authenticationUnavailable:
            return "App Attest is unavailable; this Release build cannot authenticate with the backend"
        }
    }
}

struct ShareStartResponse: Decodable {
    let sessionId: String
    let writerToken: String
    let watchUrl: String
}

actor ApiService {
    static let shared = ApiService()
    private static let appAttestCredentialNotFoundCode = "app-attest-credential-not-found"

    private struct ErrorEnvelope: Decodable {
        let code: String?
    }

    private let baseURL = AppConfiguration.apiBaseURL
    private let session: URLSession
    private var inFlightRoutes: [String: Task<Data, Error>] = [:]
    private var cachedCities: [City]?
    private var attestationComplete = false

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30

        self.session = URLSession(configuration: config)
    }

    /// Perform App Attest attestation on first use. Call during app startup.
    func ensureAttested(city: String = "boston") async throws {
        guard !attestationComplete else {
            apiLog.info("ensureAttested: already complete for this session")
            return
        }

        #if DEBUG
        apiLog.info("ensureAttested: DEBUG build, App Attest skipped")
        return
        #else
        apiLog.info("ensureAttested: release build, configuring App Attest for city=\(city, privacy: .public)")
        await AppAttestService.shared.configure()
        let available = await AppAttestService.shared.isAvailable
        apiLog.info("ensureAttested: DCAppAttestService.isSupported=\(available, privacy: .public)")
        if available {
            try await AppAttestService.shared.ensureAttested(city: city)
            attestationComplete = true
            apiLog.info("ensureAttested: attestation flow completed successfully")
        } else {
            apiLog.warning("ensureAttested: App Attest unavailable on this device")
            throw ApiError.authenticationUnavailable
        }
        #endif
    }

    private func execute(
        city: String = "boston",
        buildRequest: () async throws -> URLRequest
    ) async throws -> (Data, URLResponse) {
        try await ensureAttested(city: city)
        let keyIdBefore = await AppAttestService.shared.keyId
        let request = try await buildRequest()
        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401,
           let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           envelope.code == Self.appAttestCredentialNotFoundCode {
            let currentKeyId = await AppAttestService.shared.keyId
            attestationComplete = false
            if currentKeyId == keyIdBefore {
                apiLog.warning("execute: backend credential missing, re-attesting for city=\(city, privacy: .public)")
                await AppAttestService.shared.clearAttestation()
            } else {
                apiLog.info("execute: credential changed during recovery; waiting for attestation")
            }
            try await AppAttestService.shared.ensureAttested(city: city)
            attestationComplete = true
            let retryRequest = try await buildRequest()
            return try await session.data(for: retryRequest)
        }

        return (data, response)
    }

    private func signedRequest(url: URL, method: String = "GET", body: Data? = nil) async -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.httpBody = body

        return await RequestSigner.sign(request)
    }

    func getCities() async throws -> [City] {
        if let cached = cachedCities { return cached }
        let cities = try await fetchCities()
        cachedCities = cities
        return cities
    }

    func detectCity(srcLat: Double, srcLon: Double, dstLat: Double, dstLon: Double) async throws -> String {
        let cities = try await getCities()
        let maxDistance: Double = 30_000

        for city in cities {
            let centerLat = city.center[1]
            let centerLon = city.center[0]
            let srcDist = haversineDistance(lat1: srcLat, lon1: srcLon, lat2: centerLat, lon2: centerLon)
            let dstDist = haversineDistance(lat1: dstLat, lon1: dstLon, lat2: centerLat, lon2: centerLon)
            if srcDist <= maxDistance && dstDist <= maxDistance {
                return city.name
            }
        }

        return cities.first?.name ?? "boston"
    }

    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    func fetchCities() async throws -> [City] {
        let url = baseURL.appendingPathComponent("cities")

        do {
            let (data, response) = try await execute { await self.signedRequest(url: url) }

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ApiError.httpError(statusCode: http.statusCode, message: "Cities request failed")
            }

            let decoded = try JSONDecoder().decode(CitiesResponse.self, from: data)
            return decoded.cities

        } catch let apiErr as ApiError {
            throw apiErr
        } catch is DecodingError {
            throw ApiError.decodingError
        } catch {
            throw ApiError.networkError
        }
    }

    func fetchRoute(
        city: String,
        srcLat: Double,
        srcLon: Double,
        dstLat: Double,
        dstLon: Double,
        bin: Int = 2
    ) async throws -> Data {
        let citySlug = city.lowercased()
        let dedupeKey = "\(citySlug):\(srcLat):\(srcLon):\(dstLat):\(dstLon):\(bin)"

        if let existing = inFlightRoutes[dedupeKey] {
            return try await existing.value
        }

        let task = Task<Data, Error> {
            defer { inFlightRoutes.removeValue(forKey: dedupeKey) }
            return try await _performFetchRoute(
                citySlug: citySlug, srcLat: srcLat, srcLon: srcLon,
                dstLat: dstLat, dstLon: dstLon, bin: bin
            )
        }

        inFlightRoutes[dedupeKey] = task
        return try await task.value
    }

    private func _performFetchRoute(
        citySlug: String,
        srcLat: Double,
        srcLon: Double,
        dstLat: Double,
        dstLon: Double,
        bin: Int
    ) async throws -> Data {
        let routeURL = baseURL
            .appendingPathComponent(citySlug)
            .appendingPathComponent("route")
        guard var comps = URLComponents(url: routeURL, resolvingAgainstBaseURL: false) else {
            throw ApiError.invalidURL
        }

        comps.queryItems = [
            URLQueryItem(name: "city", value: citySlug),
            URLQueryItem(name: "src_lat", value: String(srcLat)),
            URLQueryItem(name: "src_lon", value: String(srcLon)),
            URLQueryItem(name: "dst_lat", value: String(dstLat)),
            URLQueryItem(name: "dst_lon", value: String(dstLon)),
            URLQueryItem(name: "bin", value: String(bin))
        ]

        guard let url = comps.url else {
            throw ApiError.invalidURL
        }

        do {
            let (data, response) = try await execute(city: citySlug) { await self.signedRequest(url: url) }

            if let http = response as? HTTPURLResponse {
                if !(200..<300).contains(http.statusCode) {
                    throw ApiError.httpError(statusCode: http.statusCode, message: "Route request failed")
                }
            }

            return data

        } catch let apiErr as ApiError {
            throw apiErr
        } catch {
            throw ApiError.networkError
        }
    }

    func startShareSession(city: String, routeGeoJSON: Data, destinationName: String) async throws -> ShareStartResponse {
        let url = baseURL
            .appendingPathComponent(city)
            .appendingPathComponent("share")
            .appendingPathComponent("start")
        let body = try JSONSerialization.data(withJSONObject: [
            "routeGeoJSON": try JSONSerialization.jsonObject(with: routeGeoJSON),
            "destinationName": destinationName,
        ], options: [.sortedKeys])
        let (data, response) = try await execute(city: city) {
            var req = await self.signedRequest(url: url, method: "POST", body: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return req
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ApiError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Share start failed")
        }
        return try JSONDecoder().decode(ShareStartResponse.self, from: data)
    }

    func sendShareLocation(city: String, sessionId: String, writerToken: String, lat: Double, lon: Double) async throws {
        let url = baseURL
            .appendingPathComponent(city)
            .appendingPathComponent("share")
            .appendingPathComponent("location")
        let body = try JSONSerialization.data(withJSONObject: [
            "sessionId": sessionId,
            "writerToken": writerToken,
            "lat": lat,
            "lon": lon,
        ], options: [.sortedKeys])
        let (_, response) = try await execute(city: city) {
            var req = await self.signedRequest(url: url, method: "POST", body: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return req
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ApiError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Share location failed")
        }
    }

    func transitRoute(
        city: String,
        srcLat: Double, srcLon: Double,
        dstLat: Double, dstLon: Double,
        bin: Int = 2,
        departAt: Date? = nil
    ) async throws -> TransitRouteResponse {
        let transitURL = baseURL
            .appendingPathComponent(city.lowercased())
            .appendingPathComponent("transit-route")
        guard var comps = URLComponents(url: transitURL, resolvingAgainstBaseURL: false) else {
            throw ApiError.invalidURL
        }

        var queryItems = [
            URLQueryItem(name: "src_lat", value: String(srcLat)),
            URLQueryItem(name: "src_lon", value: String(srcLon)),
            URLQueryItem(name: "dst_lat", value: String(dstLat)),
            URLQueryItem(name: "dst_lon", value: String(dstLon)),
            URLQueryItem(name: "bin", value: String(bin)),
        ]
        if let departAt {
            queryItems.append(URLQueryItem(name: "depart_at", value: ISO8601DateFormatter().string(from: departAt)))
        }
        comps.queryItems = queryItems

        guard let url = comps.url else {
            throw ApiError.invalidURL
        }

        do {
            let (data, response) = try await execute(city: city.lowercased()) {
                var req = await self.signedRequest(url: url)
                req.timeoutInterval = 30
                return req
            }

            if let http = response as? HTTPURLResponse {
                if !(200..<300).contains(http.statusCode) {
                    throw ApiError.httpError(statusCode: http.statusCode, message: "Transit route request failed")
                }
            }

            return try JSONDecoder().decode(TransitRouteResponse.self, from: data)
        } catch let apiErr as ApiError {
            throw apiErr
        } catch is DecodingError {
            throw ApiError.decodingError
        } catch {
            throw ApiError.networkError
        }
    }

    func stopShareSession(city: String, sessionId: String, writerToken: String, reason: String) async throws {
        let url = baseURL
            .appendingPathComponent(city)
            .appendingPathComponent("share")
            .appendingPathComponent("stop")
        let body = try JSONSerialization.data(withJSONObject: [
            "sessionId": sessionId,
            "writerToken": writerToken,
            "reason": reason,
        ], options: [.sortedKeys])
        let (_, response) = try await execute(city: city) {
            var request = await self.signedRequest(url: url, method: "POST", body: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return request
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ApiError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "Share stop failed"
            )
        }
    }

    func fetchMapboxToken(city: String) async throws -> String {
        struct Response: Decodable { let mapbox_token: String }
        let url = baseURL
            .appendingPathComponent(city.lowercased())
            .appendingPathComponent("mapbox-temporary-token")
        let (data, response) = try await execute(city: city.lowercased()) {
            await self.signedRequest(url: url, method: "POST")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ApiError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "Mapbox token request failed"
            )
        }
        let token = try JSONDecoder().decode(Response.self, from: data).mapbox_token
        guard !token.isEmpty else {
            throw ApiError.noData
        }
        return token
    }
}
