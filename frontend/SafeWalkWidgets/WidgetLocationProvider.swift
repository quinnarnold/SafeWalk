import Foundation

struct WidgetLocation: Codable, Identifiable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    let icon: String
    let address: String?
}

enum WidgetLocationProvider {
    private static let suiteName: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SAFEWALK_APP_GROUP") as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else {
            return "group.org.safewalk.app"
        }
        return value
    }()
    private static let savedLocationsKey = "com.safewalk.savedLocations"

    static func loadLocations() -> [WidgetLocation] {
        guard let suite = UserDefaults(suiteName: suiteName),
              let data = suite.data(forKey: savedLocationsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([WidgetLocation].self, from: data)) ?? []
    }

    static func currentCity() -> String {
        guard let suite = UserDefaults(suiteName: suiteName) else { return "" }
        return suite.string(forKey: "com.safewalk.selectedCity") ?? ""
    }
}
