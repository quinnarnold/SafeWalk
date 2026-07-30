import Foundation
import Combine
import MapboxMaps

@MainActor
final class AppLoader: ObservableObject {
    enum LoadState {
        case loading
        case ready
        case failed(Error)
    }

    @Published var state: LoadState = .loading

    func load(for city: String = "boston") async {
        do {
            try await ApiService.shared.ensureAttested(city: city)

            let token = try await MapboxTokenManager.shared.fetchMapboxToken(for: city)

            MapboxOptions.accessToken = token

            Bundle.main.setTemporaryMapboxToken(token)
            #if DEBUG
            print("Mapbox access token set and injected successfully")
            #endif

            state = .ready

        } catch {
            #if DEBUG
            print("Mapbox token fetch failed.")
            #endif
            state = .failed(error)
        }
    }
}
