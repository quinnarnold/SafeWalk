import Foundation
import CoreLocation
import UIKit
import SwiftUI

struct TransitItinerary: Codable, Identifiable {
    var id = UUID()
    let startTime: Double
    let endTime: Double
    let duration: Double
    let legs: [TransitLeg]
    let totalWalkDistanceM: Double
    let totalWalkRisk: Double?

    enum CodingKeys: String, CodingKey {
        case startTime, endTime, duration, legs
        case totalWalkDistanceM = "totalWalkDistance_m"
        case totalWalkRisk
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startTime = try container.decode(Double.self, forKey: .startTime)
        self.endTime = try container.decode(Double.self, forKey: .endTime)
        self.duration = try container.decode(Double.self, forKey: .duration)
        self.legs = try container.decode([TransitLeg].self, forKey: .legs)
        self.totalWalkDistanceM = try container.decode(Double.self, forKey: .totalWalkDistanceM)
        self.totalWalkRisk = try container.decodeIfPresent(Double.self, forKey: .totalWalkRisk)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)min"
        }
        return "\(minutes) min"
    }

    var departureTime: Date? {
        Date(timeIntervalSince1970: startTime / 1000)
    }

    var arrivalTime: Date? {
        Date(timeIntervalSince1970: endTime / 1000)
    }

    var transitModes: [String] {
        legs.filter { $0.mode != "WALK" }.compactMap { $0.route?.shortName ?? $0.mode }
    }
}

struct TransitLeg: Codable, Identifiable {
    var id = UUID()
    let mode: String
    let from: LegLocation
    let to: LegLocation
    let startTime: Double
    let endTime: Double
    let duration: Double
    let distanceM: Double
    let geometry: LegGeometry
    let route: TransitRouteInfo?
    let intermediateStops: [IntermediateStop]?
    let predRisk: Double?
    let safetyType: String?

    enum CodingKeys: String, CodingKey {
        case mode, from, to, startTime, endTime, duration, geometry, route, intermediateStops
        case distanceM = "distance_m"
        case predRisk = "pred_risk"
        case safetyType = "safety_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decode(String.self, forKey: .mode)
        self.from = try container.decode(LegLocation.self, forKey: .from)
        self.to = try container.decode(LegLocation.self, forKey: .to)
        self.startTime = try container.decode(Double.self, forKey: .startTime)
        self.endTime = try container.decode(Double.self, forKey: .endTime)
        self.duration = try container.decode(Double.self, forKey: .duration)
        self.distanceM = try container.decode(Double.self, forKey: .distanceM)
        self.geometry = try container.decode(LegGeometry.self, forKey: .geometry)
        self.route = try container.decodeIfPresent(TransitRouteInfo.self, forKey: .route)
        self.intermediateStops = try container.decodeIfPresent([IntermediateStop].self, forKey: .intermediateStops)
        self.predRisk = try container.decodeIfPresent(Double.self, forKey: .predRisk)
        self.safetyType = try container.decodeIfPresent(String.self, forKey: .safetyType)
    }

    var isWalk: Bool { mode == "WALK" }
    var isTransit: Bool { !isWalk }

    var coordinates: [CLLocationCoordinate2D] {
        geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
    }
}

struct LegLocation: Codable {
    let lat: Double
    let lon: Double
    let name: String
    let stopId: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct LegGeometry: Codable {
    let type: String
    let coordinates: [[Double]]
}

struct TransitRouteInfo: Codable {
    let shortName: String?
    let longName: String?
    let color: String?
    let agency: String?
}

struct IntermediateStop: Codable {
    let name: String
    let lat: Double
    let lon: Double
}

struct TransitRouteResponse: Codable {
    let itineraries: [TransitItinerary]
}

extension UIColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init?(hex: String) {
        guard let uiColor = UIColor(hex: hex) else { return nil }
        self.init(uiColor: uiColor)
    }
}
