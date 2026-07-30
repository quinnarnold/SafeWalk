import Foundation
import CoreLocation
import Turf
import MapboxDirections
import MapboxNavigationCore
import MapboxMaps

enum MatchedNavError: Error, LocalizedError {
    case noChosen
    case notLineString
    case tooFewPoints
    case routingFailed(String)
    case missingAccessToken

    var errorDescription: String? {
        switch self {
        case .noChosen:       return "No chosen route feature found."
        case .notLineString:  return "Chosen route is not a LineString."
        case .tooFewPoints:   return "Chosen route needs at least two coordinates."
        case .routingFailed(let m): return "Map matching failed: \(m)"
        case .missingAccessToken: return "Mapbox access token missing. Add MBXAccessToken to Info.plist."
        }
    }
}

struct MapboxMatchedNavigator {
    private static let pointLimits = [80, 50, 25]

    static func routes(
        from featureCollection: FeatureCollection,
        preferredType: String = "moderate",
        profile: ProfileIdentifier = .walking
    ) async throws -> NavigationRoutes {

        let token = MapboxOptions.accessToken
        if token.isEmpty {
            throw MatchedNavError.missingAccessToken
        }

        let chosenFeature: Feature? =
            featureCollection.features.first(where: { $0.properties?["type"]??.stringValue == preferredType }) ??
            featureCollection.features.first(where: { $0.geometry?.lineString != nil })

        guard let feature = chosenFeature else { throw MatchedNavError.noChosen }
        guard case let .lineString(line) = feature.geometry else { throw MatchedNavError.notLineString }

        let fullCoords = line.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard fullCoords.count >= 2 else { throw MatchedNavError.tooFewPoints }

        // Try map matching first (preserves exact safety-weighted geometry)
        var lastError: Error?

        for limit in pointLimits {
            let coords = thin(fullCoords, to: limit)
            #if DEBUG
            print("Attempting map match with \(coords.count) points (limit \(limit)).")
            #endif

            do {
                return try await matchRoutes(coords: coords, profile: profile)
            } catch {
                lastError = error
                #if DEBUG
                print("Map match failed at \(coords.count) points.")
                #endif
            }
        }

        // Fallback: use Directions API with waypoints sampled from our route.
        // This follows approximately the same path via intermediate via-points.
        #if DEBUG
        print("Map matching exhausted. Falling back to directions with waypoints.")
        #endif

        do {
            return try await directionsRoutes(coords: fullCoords, profile: profile)
        } catch {
            _ = lastError
            throw MatchedNavError.routingFailed("Mapbox routing service unavailable")
        }
    }

    private static func thin(_ coords: [CLLocationCoordinate2D], to limit: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > limit else { return coords }

        let ls = LineString(coords)
        var tolerance = 0.00005 // ~5 meters in degrees
        var simplified = ls.simplified(tolerance: tolerance).coordinates
        while simplified.count > limit && tolerance < 0.002 {
            tolerance *= 1.5
            simplified = ls.simplified(tolerance: tolerance).coordinates
        }

        if simplified.count > limit {
            simplified = uniformSample(simplified, count: limit)
        }

        if simplified.count < 2 {
            simplified = [coords.first!, coords.last!]
        }

        if simplified.first != coords.first { simplified.insert(coords.first!, at: 0) }
        if simplified.last  != coords.last  { simplified.append(coords.last!) }

        if simplified.count > limit {
            simplified = uniformSample(simplified, count: limit)
        }

        return simplified
    }

    private static func uniformSample(_ coords: [CLLocationCoordinate2D], count: Int) -> [CLLocationCoordinate2D] {
        let total = coords.count
        guard total > count else { return coords }
        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(count)
        for n in 0..<count {
            let idx = Int(round(Double(n) * Double(total - 1) / Double(count - 1)))
            result.append(coords[idx])
        }
        return result
    }

    private static func matchRoutes(
        coords: [CLLocationCoordinate2D],
        profile: ProfileIdentifier
    ) async throws -> NavigationRoutes {
        let waypoints: [Waypoint] = coords.enumerated().map { (i, c) in
            var wp = Waypoint(coordinate: c, name: (i == 0 ? "Start" : (i == coords.count - 1 ? "Destination" : nil)))
            if i != 0 && i != coords.count - 1 { wp.separatesLegs = false }
            return wp
        }

        let options = NavigationMatchOptions(waypoints: waypoints, profileIdentifier: profile)
        options.includesSteps = true
        options.includesSpokenInstructions = true
        options.includesVisualInstructions = true

        let routingProvider = NavigationPresenter.navigationProvider.mapboxNavigation.routingProvider()
        return try await routingProvider.calculateRoutes(options: options).value
    }

    /// Fallback: use Directions API with sampled intermediate waypoints to approximate our route.
    private static func directionsRoutes(
        coords: [CLLocationCoordinate2D],
        profile: ProfileIdentifier
    ) async throws -> NavigationRoutes {
        let sampled = uniformSample(coords, count: 12)

        let waypoints: [Waypoint] = sampled.enumerated().map { (i, c) in
            var wp = Waypoint(coordinate: c, name: (i == 0 ? "Start" : (i == sampled.count - 1 ? "Destination" : nil)))
            if i != 0 && i != sampled.count - 1 { wp.separatesLegs = false }
            return wp
        }

        let options = NavigationRouteOptions(waypoints: waypoints, profileIdentifier: profile)
        options.includesSteps = true
        options.includesSpokenInstructions = true
        options.includesVisualInstructions = true

        let routingProvider = NavigationPresenter.navigationProvider.mapboxNavigation.routingProvider()
        return try await routingProvider.calculateRoutes(options: options).value
    }
}
