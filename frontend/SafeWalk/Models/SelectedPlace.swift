import Foundation
import CoreLocation

struct SelectedPlace: Identifiable, Equatable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let category: String?

    var phone: String?
    var website: URL?
    var address: String?
    var isLoading: Bool

    init(name: String, coordinate: CLLocationCoordinate2D, category: String? = nil) {
        self.id = UUID()
        self.name = name
        self.coordinate = coordinate
        self.category = category
        self.phone = nil
        self.website = nil
        self.address = nil
        self.isLoading = true
    }

    static func == (lhs: SelectedPlace, rhs: SelectedPlace) -> Bool {
        lhs.id == rhs.id
    }

    var categoryIcon: String {
        guard let category = category?.lowercased() else { return "mappin.circle.fill" }

        if category.contains("restaurant") || category.contains("food") { return "fork.knife" }
        if category.contains("cafe") || category.contains("coffee") { return "cup.and.saucer.fill" }
        if category.contains("bar") || category.contains("pub") || category.contains("nightlife") { return "wineglass.fill" }
        if category.contains("hotel") || category.contains("lodging") { return "bed.double.fill" }
        if category.contains("store") || category.contains("shop") || category.contains("retail") { return "bag.fill" }
        if category.contains("gas") || category.contains("fuel") { return "fuelpump.fill" }
        if category.contains("parking") { return "p.circle.fill" }
        if category.contains("hospital") || category.contains("medical") || category.contains("pharmacy") { return "cross.case.fill" }
        if category.contains("bank") || category.contains("atm") { return "dollarsign.circle.fill" }
        if category.contains("school") || category.contains("university") || category.contains("college") { return "graduationcap.fill" }
        if category.contains("library") { return "books.vertical.fill" }
        if category.contains("museum") { return "building.columns.fill" }
        if category.contains("theater") || category.contains("cinema") || category.contains("movie") { return "theatermasks.fill" }
        if category.contains("park") || category.contains("garden") { return "leaf.fill" }
        if category.contains("gym") || category.contains("fitness") { return "figure.run" }
        if category.contains("transit") || category.contains("bus") || category.contains("train") { return "bus.fill" }
        if category.contains("airport") { return "airplane" }

        return "mappin.circle.fill"
    }
}
