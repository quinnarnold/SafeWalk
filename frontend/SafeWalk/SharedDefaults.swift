import Foundation

enum SharedDefaults {
    static let suiteName: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SAFEWALK_APP_GROUP") as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else {
            return "group.org.safewalk.app"
        }
        return value
    }()

    static var suite: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    enum Key {
        static let savedLocations = "com.safewalk.savedLocations"
        static let favoriteRoutes = "com.safewalk.favoriteRoutes"
        static let migrationComplete = "com.safewalk.sharedDefaultsMigrated"
    }
}
