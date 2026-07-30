import Foundation
import MapboxMaps

enum AppConfiguration {
    static let apiBaseURL: URL = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SAFEWALK_API_BASE_URL") as? String,
           !configured.isEmpty,
           !configured.hasPrefix("$("),
           let url = URL(string: configured) {
            return url
        }

        #if DEBUG
        return URL(string: "http://localhost:8080")!
        #else
        // A Release build must provide SAFEWALK_API_BASE_URL. The reserved
        // .invalid fallback fails closed instead of sending data to another operator.
        return URL(string: "https://api.safewalk.invalid")!
        #endif
    }()

    static let mapStyleURI: StyleURI = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SAFEWALK_MAP_STYLE_URI") as? String,
           !configured.isEmpty,
           !configured.hasPrefix("$("),
           let style = StyleURI(rawValue: configured) {
            return style
        }
        return .streets
    }()
}
