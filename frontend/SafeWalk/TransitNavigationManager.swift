import Foundation
import SwiftUI
import Combine
import CoreLocation
import Turf
import MapboxDirections
import MapboxNavigationCore

enum TransitNavPhase: Equatable {
    case idle
    case walkingLeg(legIndex: Int)
    case boardingTransit(legIndex: Int)
    case ridingTransit(legIndex: Int)
    case arrived
}

@MainActor
final class TransitNavigationManager: ObservableObject {
    @Published var phase: TransitNavPhase = .idle
    @Published var activeTransitLeg: TransitLeg?
    @Published var error: String?

    let itinerary: TransitItinerary
    private let destinationName: String
    private var walkLegTask: Task<Void, Never>?

    init(itinerary: TransitItinerary, destinationName: String) {
        self.itinerary = itinerary
        self.destinationName = destinationName
    }

    /// Starts the segmented navigation flow from the first leg.
    func start() {
        advanceToLeg(at: 0)
    }

    /// Called by UI when the user taps "I've Boarded" on the transit info card.
    func userBoarded() {
        guard case .boardingTransit(let idx) = phase else { return }
        phase = .ridingTransit(legIndex: idx)
        activeTransitLeg = itinerary.legs[idx]
    }

    /// Called by UI when the transit leg riding card is dismissed / user acknowledges arrival.
    func transitLegComplete() {
        guard case .ridingTransit(let idx) = phase else { return }
        advanceToLeg(at: idx + 1)
    }

    /// Cancels navigation and resets to idle.
    func cancel() {
        walkLegTask?.cancel()
        walkLegTask = nil
        phase = .idle
        activeTransitLeg = nil
    }

    // MARK: - Private

    private func advanceToLeg(at index: Int) {
        let legs = itinerary.legs

        guard index < legs.count else {
            phase = .arrived
            activeTransitLeg = nil
            return
        }

        let leg = legs[index]

        if leg.isWalk {
            phase = .walkingLeg(legIndex: index)
            activeTransitLeg = nil
            startWalkLeg(leg, legIndex: index)
        } else {
            phase = .boardingTransit(legIndex: index)
            activeTransitLeg = leg
        }
    }

    private func startWalkLeg(_ leg: TransitLeg, legIndex: Int) {
        walkLegTask = Task {
            do {
                let navRoutes = try await buildNavigationRoutes(for: leg)
                guard !Task.isCancelled else { return }
                let isLastLeg = legIndex == itinerary.legs.count - 1
                let legDest = isLastLeg ? destinationName : leg.to.name

                let legIndex = legIndex
                NavigationPresenter.shared.present(
                    navRoutes: navRoutes,
                    startCoordinate: leg.coordinates.first,
                    destinationName: legDest,
                    routeType: leg.safetyType ?? "shortest",
                    totalDistance: leg.distanceM,
                    onDismiss: { @MainActor [weak self] canceled in
                        guard let self else { return }
                        if canceled {
                            self.cancel()
                        } else {
                            self.walkLegCompleted(legIndex: legIndex)
                        }
                    }
                )
            } catch {
                self.error = "Unable to start navigation."
                self.phase = .idle
            }
        }
    }

    private func walkLegCompleted(legIndex: Int) {
        advanceToLeg(at: legIndex + 1)
    }

    private func buildNavigationRoutes(for leg: TransitLeg) async throws -> NavigationRoutes {
        let coords = leg.coordinates
        guard coords.count >= 2 else {
            throw TransitNavError.insufficientCoordinates
        }

        let geoJSONCoords = coords.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let lineString = LineString(geoJSONCoords)

        var feature = Feature(geometry: .lineString(lineString))
        feature.properties = [
            "type": .string(leg.safetyType ?? "shortest")
        ]

        let fc = FeatureCollection(features: [feature])
        return try await MapboxMatchedNavigator.routes(
            from: fc,
            preferredType: leg.safetyType ?? "shortest",
            profile: .walking
        )
    }
}

enum TransitNavError: Error, LocalizedError {
    case insufficientCoordinates

    var errorDescription: String? {
        switch self {
        case .insufficientCoordinates:
            return "Walk leg has too few coordinates to navigate."
        }
    }
}
