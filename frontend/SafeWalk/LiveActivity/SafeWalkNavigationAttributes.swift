import ActivityKit
import Foundation

struct SafeWalkNavigationAttributes: ActivityAttributes {
    let destinationName: String
    let routeType: String
    let totalDistanceMeters: Double

    struct ContentState: Codable, Hashable {
        let currentStepName: String
        let nextManeuverIcon: String
        let distanceToNextManeuverMeters: Double
        let distanceRemainingMeters: Double
        let estimatedArrival: Date
        let fractionComplete: Double
    }
}
