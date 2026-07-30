import Foundation
import CoreLocation

struct DroppedPin: Equatable, Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    var address: String?
    var isLoadingAddress: Bool

    init(coordinate: CLLocationCoordinate2D) {
        self.id = UUID()
        self.coordinate = coordinate
        self.address = nil
        self.isLoadingAddress = true
    }

    static func == (lhs: DroppedPin, rhs: DroppedPin) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.address == rhs.address &&
        lhs.isLoadingAddress == rhs.isLoadingAddress
    }
}
