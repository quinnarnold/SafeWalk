import Foundation
import SwiftUI
import CoreLocation
import Turf
internal import MapKit
import MapboxNavigationCore
import Network
import Combine
import MapboxDirections
import WidgetKit

struct RouteInfo: Identifiable, Hashable {
    let id = UUID()
    let type: String
    let distance: Double
    let time: Double
    let predRisk: Double
}

struct ErrorWrapper: Identifiable {
    let id = UUID()
    let message: String
}

enum PhotoState: Equatable {
    case notLoaded
    case loading
    case loaded(UIImage)
    case unavailable

    static func == (lhs: PhotoState, rhs: PhotoState) -> Bool {
        switch (lhs, rhs) {
        case (.notLoaded, .notLoaded), (.loading, .loading), (.unavailable, .unavailable):
            return true
        case (.loaded(let img1), .loaded(let img2)):
            return img1 === img2
        default:
            return false
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distance: Double?
    let address: String?
    let category: MKPointOfInterestCategory?
    let phone: String?
    var photoState: PhotoState = .notLoaded

    var distanceFormatted: String? {
        guard let distance = distance else { return nil }
        let miles = distance / 1609.34
        if miles < 0.1 {
            let feet = distance * 3.28084
            return String(format: "%.0f ft", feet)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }

    var categoryIcon: String {
        guard let category = category else { return "mappin.circle.fill" }
        if #available(iOS 18.0, *) {
            switch category {
            case .restaurant: return "fork.knife"
            case .cafe: return "cup.and.saucer.fill"
            case .bakery: return "birthday.cake.fill"
            case .brewery, .winery: return "wineglass.fill"
            case .nightlife: return "moon.stars.fill"
            case .foodMarket, .store: return "cart.fill"
            case .gasStation, .evCharger: return "fuelpump.fill"
            case .parking: return "p.circle.fill"
            case .hotel: return "bed.double.fill"
            case .hospital, .pharmacy: return "cross.case.fill"
            case .fitnessCenter: return "figure.run"
            case .laundry: return "washer.fill"
            case .atm, .bank: return "dollarsign.circle.fill"
            case .library: return "books.vertical.fill"
            case .museum: return "building.columns.fill"
            case .movieTheater, .theater: return "theatermasks.fill"
            case .musicVenue: return "music.note.house.fill"
            case .park, .nationalPark: return "leaf.fill"
            case .beach: return "beach.umbrella.fill"
            case .zoo, .aquarium: return "pawprint.fill"
            case .campground: return "tent.fill"
            case .school, .university: return "graduationcap.fill"
            case .postOffice: return "envelope.fill"
            case .publicTransport: return "bus.fill"
            case .airport: return "airplane"
            case .carRental: return "car.fill"
            case .marina: return "ferry.fill"
            default: return "mappin.circle.fill"
            }
        } else {
            return "mappin.circle.fill"
        }
    }

    init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = name
        self.coordinate = coordinate
        self.distance = nil
        self.address = nil
        self.category = nil
        self.phone = nil
    }

    init(name: String, coordinate: CLLocationCoordinate2D, distance: Double?, address: String?, category: MKPointOfInterestCategory?, phone: String?) {
        self.name = name
        self.coordinate = coordinate
        self.distance = distance
        self.address = address
        self.category = category
        self.phone = phone
    }
}

enum LocationIcon: String, Codable, CaseIterable {
    case star = "star.fill"
    case home = "house.fill"
    case work = "briefcase.fill"
    case heart = "heart.fill"
    case gym = "figure.run"
    case food = "fork.knife"
    case coffee = "cup.and.saucer.fill"
    case shopping = "cart.fill"
    case medical = "cross.case.fill"
    case school = "graduationcap.fill"
    case pin = "mappin.circle.fill"
    case bookmark = "bookmark.fill"

    var color: (red: Double, green: Double, blue: Double) {
        switch self {
        case .star: return (1.0, 0.8, 0.0)      // Yellow
        case .home: return (0.0, 0.48, 1.0)     // Blue
        case .work: return (1.0, 0.58, 0.0)     // Orange
        case .heart: return (1.0, 0.27, 0.35)   // Pink/Red
        case .gym: return (0.0, 0.78, 0.33)     // Green
        case .food: return (1.0, 0.42, 0.21)    // Coral
        case .coffee: return (0.55, 0.27, 0.07) // Brown
        case .shopping: return (0.56, 0.27, 0.68) // Purple
        case .medical: return (1.0, 0.23, 0.19) // Red
        case .school: return (0.0, 0.64, 0.87)  // Cyan
        case .pin: return (1.0, 0.27, 0.35)     // Red
        case .bookmark: return (0.35, 0.35, 0.81) // Indigo
        }
    }
}

struct SavedLocation: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    let icon: LocationIcon
    let address: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: UUID = UUID(), name: String, coordinate: CLLocationCoordinate2D, icon: LocationIcon = .star, createdAt: Date = Date(), address: String? = nil) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.icon = icon
        self.createdAt = createdAt
        self.address = address
    }
}

struct RouteCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum FavoriteRouteType: String, Codable {
    case custom
    case home
    case work
}

struct FavoriteRoute: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let sourceLatitude: Double
    let sourceLongitude: Double
    let destLatitude: Double
    let destLongitude: Double
    let city: String
    let routeType: String
    let routeGeometry: [RouteCoordinate]
    let distance: Double
    let time: Double
    let createdAt: Date
    let favoriteType: FavoriteRouteType

    var sourceCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: sourceLatitude, longitude: sourceLongitude)
    }

    var destCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destLatitude, longitude: destLongitude)
    }

    init(
        id: UUID = UUID(),
        name: String,
        source: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        city: String,
        routeType: String,
        routeGeometry: [CLLocationCoordinate2D],
        distance: Double,
        time: Double,
        favoriteType: FavoriteRouteType = .custom
    ) {
        self.id = id
        self.name = name
        self.sourceLatitude = source.latitude
        self.sourceLongitude = source.longitude
        self.destLatitude = destination.latitude
        self.destLongitude = destination.longitude
        self.city = city
        self.routeType = routeType
        self.routeGeometry = routeGeometry.map { RouteCoordinate($0) }
        self.distance = distance
        self.time = time
        self.createdAt = Date()
        self.favoriteType = favoriteType
    }
}

struct RouteHistoryEntry: Identifiable, Codable {
    let id: UUID
    let sourceLatitude: Double
    let sourceLongitude: Double
    let destLatitude: Double
    let destLongitude: Double
    let city: String
    let routeType: String
    let distance: Double
    let time: Double
    let riskReduction: Double?
    let timestamp: Date
    let routeGeometry: [RouteCoordinate]?
    let sourceDisplayName: String?
    let destDisplayName: String?

    var sourceCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: sourceLatitude, longitude: sourceLongitude)
    }

    var destCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: destLatitude, longitude: destLongitude)
    }

    init(
        id: UUID = UUID(),
        source: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        city: String,
        routeType: String,
        distance: Double,
        time: Double,
        riskReduction: Double?,
        timestamp: Date = Date(),
        routeGeometry: [RouteCoordinate]? = nil,
        sourceDisplayName: String? = nil,
        destDisplayName: String? = nil
    ) {
        self.id = id
        self.sourceLatitude = source.latitude
        self.sourceLongitude = source.longitude
        self.destLatitude = destination.latitude
        self.destLongitude = destination.longitude
        self.city = city
        self.routeType = routeType
        self.distance = distance
        self.time = time
        self.riskReduction = riskReduction
        self.timestamp = timestamp
        self.routeGeometry = routeGeometry
        self.sourceDisplayName = sourceDisplayName
        self.destDisplayName = destDisplayName
    }
}

struct LifetimeStats: Codable {
    var totalRoutes: Int
    var totalDistanceMeters: Double
    var totalTimeSeconds: Double
    var riskReducingRouteCount: Int
    var totalRiskReduction: Double

    init() {
        self.totalRoutes = 0
        self.totalDistanceMeters = 0
        self.totalTimeSeconds = 0
        self.riskReducingRouteCount = 0
        self.totalRiskReduction = 0
    }

    var averageRiskReduction: Double? {
        guard riskReducingRouteCount > 0 else { return nil }
        return totalRiskReduction / Double(riskReducingRouteCount)
    }

    mutating func addRoute(distance: Double, time: Double, riskReduction: Double?) {
        totalRoutes += 1
        totalDistanceMeters += distance
        totalTimeSeconds += time

        if let reduction = riskReduction, reduction > 0 {
            riskReducingRouteCount += 1
            totalRiskReduction += reduction
        }
    }
}

enum DemoStep: Int {
    case none
    case welcome
    case tapFromField
    case chooseSourceMethod
    case dropSourcePin
    case tapDestField
    case chooseDestMethod
    case setDestination
    case selectRoute
    case done
}

enum LocationField: Hashable {
    case source
    case destination
}

struct RecentSearch: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: UUID = UUID(), name: String, address: String?, coordinate: CLLocationCoordinate2D, timestamp: Date = Date()) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.timestamp = timestamp
    }
}

enum CityConfiguration {
    static let cities = ["Atlanta", "Boston", "Chicago", "New York", "Philadelphia", "Seattle"]

    static let centers: [String: CLLocationCoordinate2D] = [
        "Atlanta": CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
        "Boston": CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
        "Chicago": CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),
        "New York": CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        "Philadelphia": CLLocationCoordinate2D(latitude: 39.9526, longitude: -75.1652),
        "Seattle": CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    ]
}

struct RouteCacheEntry {
    let data: Data
    let timestamp: Date

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 300
    }

    static func cacheKey(city: String, srcLat: Double, srcLon: Double, dstLat: Double, dstLon: Double, bin: Int) -> String {
        let rSrcLat = (srcLat * 10000).rounded() / 10000
        let rSrcLon = (srcLon * 10000).rounded() / 10000
        let rDstLat = (dstLat * 10000).rounded() / 10000
        let rDstLon = (dstLon * 10000).rounded() / 10000
        return "\(city):\(rSrcLat),\(rSrcLon):\(rDstLat),\(rDstLon):\(bin)"
    }
}

@MainActor
final class RouteViewModel: ObservableObject {
    @Published var sourceCoord: CLLocationCoordinate2D?
    @Published var destCoord: CLLocationCoordinate2D?
    @Published var featureCollection: FeatureCollection?

    @Published var navRoutes: NavigationRoutes?
    @Published var navStartCoord: CLLocationCoordinate2D?

    @Published var isFetching = false
    @Published var selectedCity = "Boston" {
        didSet {
            SharedDefaults.suite.set(selectedCity, forKey: "com.safewalk.selectedCity")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    @Published var mode: MarkerMode = .idle
    @Published var showRouteInfo = false
    @Published var routes: [RouteInfo] = []
    @Published var selectedRouteType: String?
    @Published var routeGeometry: [CLLocationCoordinate2D]?

    @Published var searchText = ""
    @Published var searchResults: [SearchResult] = []
    @Published var searchResultPhotos: [UUID: UIImage] = [:]

    @Published var activeField: LocationField = .destination
    @Published var isSearchFocused: Bool = false
    @Published var sourceDisplayName: String? = nil
    @Published var destDisplayName: String? = nil
    @Published var useCurrentLocationAsSource: Bool = true
    @Published var recentSearches: [RecentSearch] = []
    @Published var sheetDetent: PresentationDetent = .height(180)
    @Published var showSourceOptions: Bool = false
    @Published var showDestinationOptions: Bool = false

    @Published var showAbout = false
    @Published var showTrustedContacts = false
    @Published var showHowItWorks = false
    @Published var showWelcome: Bool = !UserDefaults.standard.bool(forKey: "com.safewalk.termsAccepted")
    @Published var showTermsOfService = false
    @Published var showSavedLocations = false
    @Published var showRouteHistory = false

    @Published var errorMessage: ErrorWrapper?

    @Published var tutorialActive = false
    @Published var demoStep: DemoStep = .none

    @Published var isOffline = false

    @Published var savedLocations: [SavedLocation] = []

    @Published var routeHistory: [RouteHistoryEntry] = []
    @Published var lifetimeStats: LifetimeStats = LifetimeStats()

    @Published var favoriteRoutes: [FavoriteRoute] = []

    /// Set this to trigger a camera fit to the given coordinates (cleared after use)
    @Published var pendingCameraFit: [CLLocationCoordinate2D]?

    @Published var droppedPin: DroppedPin?

    @Published var selectedPlace: SelectedPlace?

    @Published var shareWatchUrl: String?
    @Published var showingShareSheet = false
    @Published var isStartingShare = false
    @Published var isFallbackRoute = false

    @Published var transitItineraries: [TransitItinerary] = []
    @Published var selectedItinerary: TransitItinerary?
    @Published var isTransitMode: Bool = false
    @Published var isLoadingTransit: Bool = false
    @Published var transitError: String?
    @Published var transitNavigationManager: TransitNavigationManager?

    var searchTask: Task<Void, Never>?
    var routeTask: Task<Void, Never>?
    var navigationTask: Task<Void, Never>?
    var photoTasks: [UUID: Task<Void, Never>] = [:]

    private var lastSearchTime: Date = .distantPast
    private var lastSearchQuery: String = ""
    private let minSearchInterval: TimeInterval = 0.8

    private var routeCache: [String: RouteCacheEntry] = [:]
    private let routeCacheMaxSize = 20
    private let routeCacheTTL: TimeInterval = 300

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")

    private let savedLocationsKey = "com.safewalk.savedLocations"
    private let routeHistoryKey = "com.safewalk.routeHistory"
    private let lifetimeStatsKey = "com.safewalk.lifetimeStats"
    private let recentSearchesKey = "com.safewalk.recentSearches"
    private let favoriteRoutesKey = "com.safewalk.favoriteRoutes"

    var citySlug: String {
        selectedCity.lowercased().replacingOccurrences(of: " ", with: "")
    }

    var currentTimeBin: Int {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour / 6
    }

    var canGetRoute: Bool {
        sourceCoord != nil && destCoord != nil && !isFetching && !isOffline
    }

    var isOnline: Bool {
        !isOffline
    }

    init() {
        migrateToSharedDefaults()
        loadSavedLocations()
        loadRouteHistory()
        loadLifetimeStats()
        loadRecentSearches()
        loadFavoriteRoutes()
        startNetworkMonitoring()
        impactFeedback.prepare()
        notificationFeedback.prepare()
        selectionFeedback.prepare()
    }

    private func migrateToSharedDefaults() {
        let shared = SharedDefaults.suite
        guard !shared.bool(forKey: SharedDefaults.Key.migrationComplete) else { return }

        let standard = UserDefaults.standard
        let keys = [SharedDefaults.Key.savedLocations, SharedDefaults.Key.favoriteRoutes]

        for key in keys {
            if let data = standard.data(forKey: key), shared.data(forKey: key) == nil {
                shared.set(data, forKey: key)
            }
        }

        shared.set(true, forKey: SharedDefaults.Key.migrationComplete)
    }

    deinit {
        networkMonitor.cancel()
    }

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOffline = path.status != .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    func playImpactFeedback() {
        impactFeedback.impactOccurred()
    }

    func playSuccessFeedback() {
        notificationFeedback.notificationOccurred(.success)
    }

    func playErrorFeedback() {
        notificationFeedback.notificationOccurred(.error)
    }

    func playSelectionFeedback() {
        selectionFeedback.selectionChanged()
    }

    func setSourceCoord(_ coord: CLLocationCoordinate2D, name: String? = nil) {
        sourceCoord = coord
        sourceDisplayName = name
        useCurrentLocationAsSource = false
        mode = .idle
        playImpactFeedback()

        if name == nil {
            reverseGeocodeForDisplay(coord, isSource: true)
        }
    }

    func setDestCoord(_ coord: CLLocationCoordinate2D, name: String? = nil, autoFetchRoute: Bool = false) {
        destCoord = coord
        destDisplayName = name
        mode = .idle
        playImpactFeedback()

        if name == nil {
            reverseGeocodeForDisplay(coord, isSource: false)
        }

        if autoFetchRoute && sourceCoord != nil {
            routeTask?.cancel()
            routeTask = Task {
                await getRoute()
            }
        }
    }

    /// Reverse geocodes a coordinate and updates the display name for source or destination
    private func reverseGeocodeForDisplay(_ coordinate: CLLocationCoordinate2D, isSource: Bool) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    let address = formatAddressForPin(from: placemark)
                    if isSource {
                        sourceDisplayName = address
                    } else {
                        destDisplayName = address
                    }
                }
            } catch {
            }
        }
    }

    /// Formats a placemark into a readable address string for pin display
    private func formatAddressForPin(from placemark: CLPlacemark) -> String {
        if let name = placemark.name,
           name != placemark.thoroughfare,
           !name.contains(placemark.subThoroughfare ?? "~~~") {
            return name
        }

        var components: [String] = []

        if let subThoroughfare = placemark.subThoroughfare,
           let thoroughfare = placemark.thoroughfare {
            components.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }

        if let locality = placemark.locality {
            components.append(locality)
        }

        return components.isEmpty ? "Dropped Pin" : components.joined(separator: ", ")
    }

    func clearPins() {
        sourceCoord = nil
        destCoord = nil
        sourceDisplayName = nil
        destDisplayName = nil
        useCurrentLocationAsSource = true
        featureCollection = nil
        routes.removeAll()
        isFallbackRoute = false
        selectedRouteType = nil
        playImpactFeedback()
    }

    /// Clears the current route, destination, and resets to initial state (keeps source)
    func clearRoute() {
        destCoord = nil
        destDisplayName = nil

        sourceCoord = nil
        sourceDisplayName = nil
        useCurrentLocationAsSource = true

        featureCollection = nil
        routes.removeAll()
        isFallbackRoute = false
        selectedRouteType = nil

        mode = .idle
        activeField = .destination

        isTransitMode = false
        transitItineraries = []
        selectedItinerary = nil
        transitNavigationManager = nil
        transitError = nil

        playImpactFeedback()
    }

    /// Drops a pin at the given coordinate and triggers reverse geocoding
    func dropPin(at coordinate: CLLocationCoordinate2D) {
        droppedPin = DroppedPin(coordinate: coordinate)
        playImpactFeedback()
        reverseGeocode(coordinate)
    }

    /// Reverse geocodes the coordinate to get an address
    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    let address = formatAddress(from: placemark)
                    droppedPin?.address = address
                } else {
                    droppedPin?.address = "Dropped Pin"
                }
            } catch {
                droppedPin?.address = "Dropped Pin"
            }
            droppedPin?.isLoadingAddress = false
        }
    }

    /// Formats a placemark into a readable address string
    private func formatAddress(from placemark: CLPlacemark) -> String {
        var components: [String] = []

        if let subThoroughfare = placemark.subThoroughfare,
           let thoroughfare = placemark.thoroughfare {
            components.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        } else if let name = placemark.name {
            components.append(name)
        }

        if let locality = placemark.locality {
            components.append(locality)
        }

        return components.isEmpty ? "Dropped Pin" : components.joined(separator: ", ")
    }

    /// Clears the dropped pin
    func clearDroppedPin() {
        droppedPin = nil
    }

    /// Uses the dropped pin as the destination and triggers route calculation
    func useDroppedPinAsDestination(userLocation: CLLocationCoordinate2D?) {
        guard let pin = droppedPin else { return }

        setDestCoord(pin.coordinate, name: pin.address ?? "Dropped Pin")

        if sourceCoord == nil, let userLoc = userLocation {
            useCurrentLocation(userLoc)
        }

        clearDroppedPin()

        if sourceCoord != nil && destCoord != nil {
            routeTask?.cancel()
            routeTask = Task {
                await getRoute()
            }
        }
    }

    /// Called when user taps on a POI feature on the map
    func selectPOI(name: String, coordinate: CLLocationCoordinate2D, category: String?) {
        guard mode == .idle else { return }

        clearDroppedPin()

        selectedPlace = SelectedPlace(name: name, coordinate: coordinate, category: category)

        enrichSelectedPlaceWithMapKit(name: name, coordinate: coordinate)
    }

    /// Uses MapKit to get phone, website, and address for the selected place
    private func enrichSelectedPlaceWithMapKit(name: String, coordinate: CLLocationCoordinate2D) {
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = name
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            request.resultTypes = .pointOfInterest

            let search = MKLocalSearch(request: request)

            do {
                let response = try await search.start()

                let bestMatch = response.mapItems
                    .filter { $0.name?.lowercased() == name.lowercased() }
                    .min { item1, item2 in
                        let dist1 = item1.placemark.location?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? .infinity
                        let dist2 = item2.placemark.location?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? .infinity
                        return dist1 < dist2
                    } ?? response.mapItems.first

                if let mapItem = bestMatch {
                    selectedPlace?.phone = mapItem.phoneNumber
                    selectedPlace?.website = mapItem.url
                    selectedPlace?.address = formatPlacemarkAddress(mapItem.placemark)
                }
            } catch {
                #if DEBUG
                print("MapKit lookup failed.")
                #endif
            }

            selectedPlace?.isLoading = false
        }
    }

    /// Formats a placemark into a readable address for POI
    private func formatPlacemarkAddress(_ placemark: MKPlacemark) -> String? {
        var components: [String] = []

        if let subThoroughfare = placemark.subThoroughfare,
           let thoroughfare = placemark.thoroughfare {
            components.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }

        if let locality = placemark.locality {
            if let adminArea = placemark.administrativeArea {
                components.append("\(locality), \(adminArea)")
            } else {
                components.append(locality)
            }
        }

        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    /// Clears the selected place
    func clearSelectedPlace() {
        selectedPlace = nil
    }

    /// Uses the selected place as destination and triggers route calculation
    func useSelectedPlaceAsDestination(userLocation: CLLocationCoordinate2D?) {
        guard let place = selectedPlace else { return }

        setDestCoord(place.coordinate, name: place.name)

        if sourceCoord == nil, let userLoc = userLocation {
            useCurrentLocation(userLoc)
        }

        clearSelectedPlace()

        if sourceCoord != nil && destCoord != nil {
            routeTask?.cancel()
            routeTask = Task {
                await getRoute()
            }
        }
    }

    func startDemoTutorial() {
        sourceCoord = nil
        destCoord = nil
        sourceDisplayName = nil
        destDisplayName = nil
        featureCollection = nil
        routes.removeAll()
        isFallbackRoute = false
        selectedRouteType = nil
        isFetching = false
        useCurrentLocationAsSource = false
        mode = .idle
        activeField = .source
        isSearchFocused = false
        searchText = ""
        showSourceOptions = false
        showDestinationOptions = false

        tutorialActive = true
        demoStep = .welcome

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard self?.tutorialActive == true, self?.demoStep == .welcome else { return }
            self?.demoStep = .tapFromField
        }
    }

    /// Called when user taps the From field during tutorial
    func tutorialDidTapFromField() {
        guard tutorialActive, demoStep == .tapFromField else { return }
        demoStep = .chooseSourceMethod
    }

    /// Called when user selects "Current Location" during tutorial
    func tutorialDidSelectCurrentLocation() {
        guard tutorialActive, demoStep == .chooseSourceMethod else { return }
        demoStep = .tapDestField
    }

    /// Called when user taps "Drop Pin" for source during tutorial
    func tutorialDidTapDropPinForSource() {
        guard tutorialActive, demoStep == .chooseSourceMethod else { return }
        demoStep = .dropSourcePin
    }

    /// Called when source coordinate is set during tutorial
    func tutorialDidSetSource() {
        guard tutorialActive else { return }
        if demoStep == .dropSourcePin || demoStep == .chooseSourceMethod {
            demoStep = .tapDestField
        }
    }

    /// Called when user taps the destination field during tutorial
    func tutorialDidTapDestField() {
        guard tutorialActive, demoStep == .tapDestField else { return }
        demoStep = .chooseDestMethod
    }

    /// Called when user taps "Drop Pin" for destination during tutorial
    func tutorialDidTapDropPinForDest() {
        guard tutorialActive, demoStep == .chooseDestMethod else { return }
        demoStep = .setDestination
    }

    /// Called when user starts searching during tutorial
    func tutorialDidStartSearch() {
        guard tutorialActive, demoStep == .chooseDestMethod else { return }
        demoStep = .setDestination
    }

    /// Called when destination coordinate is set during tutorial
    func tutorialDidSetDestination() {
        guard tutorialActive else { return }
        if demoStep == .setDestination || demoStep == .chooseDestMethod {
            demoStep = .selectRoute
        }
    }

    /// Called when routes are calculated during tutorial
    func tutorialDidGetRoutes() {
        guard tutorialActive else { return }
        if demoStep == .selectRoute && !routes.isEmpty {}
    }

    /// Called when user selects a route during tutorial
    func tutorialDidSelectRoute() {
        guard tutorialActive, demoStep == .selectRoute else { return }
        demoStep = .done
    }

    func endTutorial() {
        tutorialActive = false
        demoStep = .none
    }

    func getRoute() async {
        guard let src = sourceCoord, let dst = destCoord else { return }
        guard !isOffline else {
            errorMessage = ErrorWrapper(message: "You're offline. Please check your internet connection.")
            playErrorFeedback()
            return
        }

        try? Task.checkCancellation()

        isFetching = true

        do {
            let detectedCity = try await ApiService.shared.detectCity(
                srcLat: src.latitude, srcLon: src.longitude,
                dstLat: dst.latitude, dstLon: dst.longitude
            )
            let slug = detectedCity.lowercased().replacingOccurrences(of: " ", with: "")
            let displayName: String
            switch slug {
            case "atlanta": displayName = "Atlanta"
            case "boston": displayName = "Boston"
            case "chicago": displayName = "Chicago"
            case "newyork": displayName = "New York"
            case "philadelphia": displayName = "Philadelphia"
            case "seattle": displayName = "Seattle"
            default: displayName = detectedCity.capitalized
            }
            selectedCity = displayName

            let cacheKey = RouteCacheEntry.cacheKey(
                city: slug,
                srcLat: src.latitude, srcLon: src.longitude,
                dstLat: dst.latitude, dstLon: dst.longitude,
                bin: currentTimeBin
            )

            if let cached = routeCache[cacheKey], !cached.isExpired {
                applyRouteData(cached.data)
                return
            }

            let data = try await ApiService.shared.fetchRoute(
                city: slug,
                srcLat: src.latitude,
                srcLon: src.longitude,
                dstLat: dst.latitude,
                dstLon: dst.longitude,
                bin: currentTimeBin
            )

            try Task.checkCancellation()

            routeCache[cacheKey] = RouteCacheEntry(data: data, timestamp: Date())
            evictRouteCache()

            applyRouteData(data)

        } catch is CancellationError {
            isFetching = false
        } catch {
            isFetching = false
            errorMessage = ErrorWrapper(message: "Could not fetch route. Please check your connection or try again.")
            playErrorFeedback()
        }
    }

    private func applyRouteData(_ data: Data) {
        do {
            let fc = try JSONDecoder().decode(FeatureCollection.self, from: data)

            featureCollection = fc

            var detectedFallback = false
            routes = fc.features.compactMap { f in
                guard let props = f.properties else { return nil }
                let cleanProps: [String: JSONValue] = props.compactMapValues { $0 }

                guard let type = cleanProps["type"]?.stringValue,
                      let distance = cleanProps["distance_m"]?.doubleValue,
                      let time = cleanProps["time_s"]?.doubleValue else {
                    return nil
                }

                if cleanProps["fallback"]?.boolValue == true {
                    detectedFallback = true
                }

                let predRisk = cleanProps["pred_risk"]?.doubleValue ?? 0.0

                return RouteInfo(
                    type: type,
                    distance: distance,
                    time: time,
                    predRisk: predRisk
                )
            }

            isFallbackRoute = detectedFallback
            isFetching = false
            showRouteInfo = true
            playSuccessFeedback()
        } catch {
            isFetching = false
            errorMessage = ErrorWrapper(message: "Could not decode route data.")
            playErrorFeedback()
        }
    }

    private func evictRouteCache() {
        routeCache = routeCache.filter { !$0.value.isExpired }
        while routeCache.count > routeCacheMaxSize {
            if let oldest = routeCache.min(by: { $0.value.timestamp < $1.value.timestamp }) {
                routeCache.removeValue(forKey: oldest.key)
            }
        }
    }

    func calculateTransitRoute() async {
        guard let source = sourceCoord, let destination = destCoord else { return }

        isLoadingTransit = true
        transitError = nil
        defer { isLoadingTransit = false }

        do {
            let response = try await ApiService.shared.transitRoute(
                city: citySlug,
                srcLat: source.latitude, srcLon: source.longitude,
                dstLat: destination.latitude, dstLon: destination.longitude,
                bin: currentTimeBin
            )
            transitItineraries = response.itineraries
            selectedItinerary = response.itineraries.first
            transitError = response.itineraries.isEmpty ? "No transit routes found for this trip" : nil
        } catch {
            transitItineraries = []
            selectedItinerary = nil
            transitError = "Transit routing temporarily unavailable"
        }
    }

    func startTransitNavigation() {
        guard let itinerary = selectedItinerary else { return }
        let manager = TransitNavigationManager(
            itinerary: itinerary,
            destinationName: destDisplayName ?? "Destination"
        )
        transitNavigationManager = manager
        manager.start()
    }

    /// Selects a route type for highlighting on the map without clearing the route options
    func selectRouteType(_ type: String) {
        selectedRouteType = type

        if let fc = featureCollection,
           let feature = fc.features.first(where: {
               $0.properties?["type"]??.stringValue == type
           }),
           case let .lineString(line) = feature.geometry {
            routeGeometry = line.coordinates.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        }

        playSelectionFeedback()
    }

    /// Computes risk reduction percentage for a route compared to the shortest route
    func riskReductionPercent(for route: RouteInfo, comparedTo shortest: RouteInfo) -> Double? {
        guard shortest.predRisk > 0 else { return nil }
        let reduction = (shortest.predRisk - route.predRisk) / shortest.predRisk * 100
        return reduction > 0 ? reduction : nil
    }

    /// Returns the shortest route from the current routes array
    var shortestRoute: RouteInfo? {
        routes.first { $0.type == "shortest" }
    }

    func useRoute(ofType type: String) {
        guard let fc = featureCollection else { return }

        let filtered = fc.features.filter { feature in
            let props = feature.properties?.compactMapValues { $0 } ?? [:]
            return props["type"]?.stringValue == type
        }

        guard !filtered.isEmpty else { return }

        var extractedGeometry: [CLLocationCoordinate2D]?
        if let feature = filtered.first,
           case let .lineString(line) = feature.geometry {
            extractedGeometry = line.coordinates.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        }

        featureCollection = FeatureCollection(features: filtered)
        selectedRouteType = type
        routeGeometry = extractedGeometry
        showRouteInfo = false
        playSelectionFeedback()

        if let src = sourceCoord, let dst = destCoord,
           let route = routes.first(where: { $0.type == type }) {
            let riskReduction: Double? = {
                guard let shortest = shortestRoute else { return nil }
                return riskReductionPercent(for: route, comparedTo: shortest)
            }()

            addToRouteHistory(
                source: src,
                destination: dst,
                routeType: type,
                distance: route.distance,
                time: route.time,
                riskReduction: riskReduction,
                geometry: extractedGeometry
            )
        }
    }

    func startNavigation() async {
        guard let fc = featureCollection else { return }

        do {
            let matched = try await MapboxMatchedNavigator.routes(
                from: fc,
                preferredType: selectedRouteType ?? "moderate",
                profile: .walking
            )

            var startCoord: CLLocationCoordinate2D?
            let picked: Feature? = {
                if let sel = selectedRouteType {
                    return fc.features.first(where: {
                        $0.properties?["type"]??.stringValue == sel
                    })
                } else {
                    return fc.features.first(where: { $0.geometry?.lineString != nil })
                }
            }()

            if let picked = picked,
               case let .lineString(line) = picked.geometry,
               let first = line.coordinates.first {
                startCoord = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
            }

            navRoutes = matched
            navStartCoord = startCoord

            let routeDistance: Double = {
                if let sel = selectedRouteType, let info = routes.first(where: { $0.type == sel }) {
                    return info.distance
                }
                return routes.first?.distance ?? 0
            }()

            NavigationPresenter.shared.present(
                navRoutes: matched,
                startCoordinate: startCoord,
                destinationName: destDisplayName ?? "Destination",
                routeType: selectedRouteType ?? "moderate",
                totalDistance: routeDistance
            )

            playSuccessFeedback()

        } catch {
            let msg: String
            if case MatchedNavError.tooFewPoints = error {
                msg = "Not enough points to start navigation."
            } else if case MatchedNavError.routingFailed(let detail) = error {
                msg = "Unable to start navigation: \(detail)"
            } else {
                msg = "Unable to start navigation."
            }

            errorMessage = ErrorWrapper(message: msg)
            playErrorFeedback()
        }
    }

    func searchPlaces(query: String, userLocation: CLLocationCoordinate2D? = nil) async {
        guard !query.isEmpty else { return }

        let now = Date()
        if query == lastSearchQuery { return }
        if now.timeIntervalSince(lastSearchTime) < minSearchInterval { return }

        lastSearchTime = now
        lastSearchQuery = query

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]

        if let cityCenter = CityConfiguration.centers[selectedCity] {
            request.region = MKCoordinateRegion(
                center: cityCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()

            let referenceLocation: CLLocation? = {
                if let userLoc = userLocation {
                    return CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
                } else if let cityCenter = CityConfiguration.centers[selectedCity] {
                    return CLLocation(latitude: cityCenter.latitude, longitude: cityCenter.longitude)
                }
                return nil
            }()

            var results = response.mapItems.map { item -> SearchResult in
                let placemark = item.placemark

                let distance: Double? = {
                    guard let refLoc = referenceLocation else { return nil }
                    let itemLoc = CLLocation(latitude: placemark.coordinate.latitude, longitude: placemark.coordinate.longitude)
                    return refLoc.distance(from: itemLoc)
                }()

                let address = buildAddress(from: placemark)

                return SearchResult(
                    name: item.name ?? placemark.title ?? "Unknown",
                    coordinate: placemark.coordinate,
                    distance: distance,
                    address: address,
                    category: item.pointOfInterestCategory,
                    phone: item.phoneNumber
                )
            }

            results.sort { (r1, r2) -> Bool in
                guard let d1 = r1.distance else { return false }
                guard let d2 = r2.distance else { return true }
                return d1 < d2
            }

            searchResults = results
        } catch {}
    }

    private func buildAddress(from placemark: MKPlacemark) -> String? {
        var components: [String] = []

        if let subThoroughfare = placemark.subThoroughfare,
           let thoroughfare = placemark.thoroughfare {
            components.append("\(subThoroughfare) \(thoroughfare)")
        } else if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }

        if let locality = placemark.locality {
            if let administrativeArea = placemark.administrativeArea {
                components.append("\(locality), \(administrativeArea)")
            } else {
                components.append(locality)
            }
        }

        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    /// Clears search results and associated photo data
    func clearSearchResults() {
        for task in photoTasks.values {
            task.cancel()
        }
        photoTasks.removeAll()

        searchResults = []
        searchResultPhotos.removeAll()

        lastSearchQuery = ""
    }

    /// Sets current location as source
    func useCurrentLocation(_ coordinate: CLLocationCoordinate2D) {
        setSourceCoord(coordinate, name: "Current Location")
        useCurrentLocationAsSource = true
        sourceDisplayName = "Current Location"
    }

    /// Swaps source and destination
    func swapSourceAndDestination() {
        let tempCoord = sourceCoord
        let tempName = sourceDisplayName

        sourceCoord = destCoord
        sourceDisplayName = destDisplayName

        destCoord = tempCoord
        destDisplayName = tempName

        useCurrentLocationAsSource = false

        featureCollection = nil
        routes.removeAll()
        isFallbackRoute = false
        selectedRouteType = nil

        playSelectionFeedback()

        if sourceCoord != nil && destCoord != nil {
            routeTask?.cancel()
            routeTask = Task {
                await getRoute()
            }
        }
    }

    /// Selects a search result for the active field
    func selectSearchResult(_ result: SearchResult) {
        switch activeField {
        case .source:
            setSourceCoord(result.coordinate, name: result.name)
        case .destination:
            setDestCoord(result.coordinate, name: result.name, autoFetchRoute: sourceCoord != nil)
        }

        addToRecentSearches(result)

        searchText = ""
        clearSearchResults()
        isSearchFocused = false
    }

    /// Adds a search result to recent searches
    func addToRecentSearches(_ result: SearchResult) {
        let recent = RecentSearch(
            name: result.name,
            address: result.address,
            coordinate: result.coordinate
        )

        recentSearches.removeAll { existing in
            existing.name == recent.name &&
            abs(existing.latitude - recent.latitude) < 0.0001 &&
            abs(existing.longitude - recent.longitude) < 0.0001
        }

        recentSearches.insert(recent, at: 0)

        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }

        persistRecentSearches()
    }

    /// Selects a recent search for the active field
    func selectRecentSearch(_ recent: RecentSearch) {
        switch activeField {
        case .source:
            setSourceCoord(recent.coordinate, name: recent.name)
        case .destination:
            setDestCoord(recent.coordinate, name: recent.name, autoFetchRoute: sourceCoord != nil)
        }

        searchText = ""
        clearSearchResults()
        isSearchFocused = false
    }

    /// Selects a saved location for the active field
    func selectSavedLocation(_ location: SavedLocation) {
        switch activeField {
        case .source:
            setSourceCoord(location.coordinate, name: location.name)
        case .destination:
            setDestCoord(location.coordinate, name: location.name, autoFetchRoute: sourceCoord != nil)
        }

        searchText = ""
        clearSearchResults()
        isSearchFocused = false
    }

    /// Clears the active field
    func clearActiveField() {
        switch activeField {
        case .source:
            clearSourceField()
        case .destination:
            clearDestinationField()
        }
    }

    /// Clears the source field specifically
    func clearSourceField() {
        sourceCoord = nil
        sourceDisplayName = nil
        useCurrentLocationAsSource = true

        featureCollection = nil
        routes.removeAll()
        isFallbackRoute = false
        selectedRouteType = nil

        playImpactFeedback()
    }

    /// Clears the destination field specifically
    func clearDestinationField() {
        destCoord = nil
        destDisplayName = nil

        featureCollection = nil
        routes.removeAll()
        isFallbackRoute = false
        selectedRouteType = nil

        playImpactFeedback()
    }

    private func loadRecentSearches() {
        guard let data = UserDefaults.standard.data(forKey: recentSearchesKey),
              let searches = try? JSONDecoder().decode([RecentSearch].self, from: data) else {
            return
        }
        recentSearches = searches
    }

    private func persistRecentSearches() {
        guard let data = try? JSONEncoder().encode(recentSearches) else { return }
        UserDefaults.standard.set(data, forKey: recentSearchesKey)
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        persistRecentSearches()
    }

    func saveLocation(name: String, coordinate: CLLocationCoordinate2D, icon: LocationIcon = .star, address: String? = nil) {
        let location = SavedLocation(name: name, coordinate: coordinate, icon: icon, address: address)
        savedLocations.append(location)
        persistSavedLocations()
        playSuccessFeedback()
    }

    func deleteLocation(_ location: SavedLocation) {
        savedLocations.removeAll { $0.id == location.id }
        persistSavedLocations()
    }

    func deleteSavedLocations(at offsets: IndexSet) {
        savedLocations.remove(atOffsets: offsets)
        persistSavedLocations()
    }

    private func loadSavedLocations() {
        guard let data = SharedDefaults.suite.data(forKey: savedLocationsKey),
              let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
            return
        }
        savedLocations = locations
    }

    private func persistSavedLocations() {
        guard let data = try? JSONEncoder().encode(savedLocations) else { return }
        SharedDefaults.suite.set(data, forKey: savedLocationsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadFavoriteRoutes() {
        guard let data = SharedDefaults.suite.data(forKey: favoriteRoutesKey),
              let routes = try? JSONDecoder().decode([FavoriteRoute].self, from: data) else {
            return
        }
        favoriteRoutes = routes
    }

    private func persistFavoriteRoutes() {
        guard let data = try? JSONEncoder().encode(favoriteRoutes) else { return }
        SharedDefaults.suite.set(data, forKey: favoriteRoutesKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func saveFavoriteRoute(
        name: String,
        source: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        routeType: String,
        geometry: [CLLocationCoordinate2D],
        distance: Double,
        time: Double,
        favoriteType: FavoriteRouteType = .custom
    ) {
        if favoriteType == .home || favoriteType == .work {
            favoriteRoutes.removeAll { $0.favoriteType == favoriteType && $0.city == selectedCity }
        }

        let route = FavoriteRoute(
            name: name,
            source: source,
            destination: destination,
            city: selectedCity,
            routeType: routeType,
            routeGeometry: geometry,
            distance: distance,
            time: time,
            favoriteType: favoriteType
        )

        favoriteRoutes.insert(route, at: 0)

        let customRoutes = favoriteRoutes.filter { $0.favoriteType == .custom && $0.city == selectedCity }
        if customRoutes.count > 20 {
            if let lastCustom = customRoutes.last {
                favoriteRoutes.removeAll { $0.id == lastCustom.id }
            }
        }

        persistFavoriteRoutes()
        playSuccessFeedback()
    }

    func deleteFavoriteRoute(_ route: FavoriteRoute) {
        favoriteRoutes.removeAll { $0.id == route.id }
        persistFavoriteRoutes()
        playImpactFeedback()
    }

    func deleteFavoriteRoutes(at offsets: IndexSet, from routes: [FavoriteRoute]) {
        let idsToRemove = offsets.map { routes[$0].id }
        favoriteRoutes.removeAll { idsToRemove.contains($0.id) }
        persistFavoriteRoutes()
    }

    func updateFavoriteRoute(_ route: FavoriteRoute, name: String, favoriteType: FavoriteRouteType) {
        guard let index = favoriteRoutes.firstIndex(where: { $0.id == route.id }) else { return }
        var updated = favoriteRoutes[index]
        updated.name = name
        favoriteRoutes[index] = FavoriteRoute(
            id: updated.id,
            name: name,
            source: updated.sourceCoordinate,
            destination: updated.destCoordinate,
            city: updated.city,
            routeType: updated.routeType,
            routeGeometry: updated.routeGeometry.map { $0.clCoordinate },
            distance: updated.distance,
            time: updated.time,
            favoriteType: favoriteType
        )
        persistFavoriteRoutes()
        playImpactFeedback()
    }

    func isFavoriteRoute(source: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, routeType: String) -> Bool {
        favoriteRoutes.contains { route in
            route.city == selectedCity &&
            route.routeType == routeType &&
            abs(route.sourceLatitude - source.latitude) < 0.0001 &&
            abs(route.sourceLongitude - source.longitude) < 0.0001 &&
            abs(route.destLatitude - destination.latitude) < 0.0001 &&
            abs(route.destLongitude - destination.longitude) < 0.0001
        }
    }

    func homeRoute(for city: String) -> FavoriteRoute? {
        favoriteRoutes.first { $0.favoriteType == .home && $0.city == city }
    }

    func workRoute(for city: String) -> FavoriteRoute? {
        favoriteRoutes.first { $0.favoriteType == .work && $0.city == city }
    }

    func loadFavoriteRoute(_ route: FavoriteRoute) {
        guard !route.routeGeometry.isEmpty else { return }

        sourceCoord = route.sourceCoordinate
        destCoord = route.destCoordinate
        selectedCity = route.city

        let coordinates = route.routeGeometry.map { $0.clCoordinate }
        let lineString = LineString(coordinates.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })

        var feature = Feature(geometry: .lineString(lineString))
        feature.properties = [
            "type": .string(route.routeType),
            "distance_m": .number(route.distance),
            "time_s": .number(route.time),
            "pred_risk": .number(0)
        ]

        featureCollection = FeatureCollection(features: [feature])
        routeGeometry = coordinates

        isFallbackRoute = false
        routes = [RouteInfo(
            type: route.routeType,
            distance: route.distance,
            time: route.time,
            predRisk: 0
        )]

        selectedRouteType = route.routeType
        pendingCameraFit = coordinates

        playSuccessFeedback()
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "safewalk",
              url.host == "route",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let locationId = components.queryItems?.first(where: { $0.name == "to" })?.value,
              let uuid = UUID(uuidString: locationId) else {
            return
        }

        if let location = savedLocations.first(where: { $0.id == uuid }) {
            activeField = .destination
            selectSavedLocation(location)
        } else if let favorite = favoriteRoutes.first(where: { $0.id == uuid }) {
            loadFavoriteRoute(favorite)
        } else {
            errorMessage = ErrorWrapper(message: "Saved location no longer exists. Please update your widget.")
        }
    }

    func addToRouteHistory(
        source: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        routeType: String,
        distance: Double,
        time: Double,
        riskReduction: Double?,
        geometry: [CLLocationCoordinate2D]? = nil
    ) {
        let routeCoords = geometry?.map { RouteCoordinate($0) }

        let entry = RouteHistoryEntry(
            source: source,
            destination: destination,
            city: selectedCity,
            routeType: routeType,
            distance: distance,
            time: time,
            riskReduction: riskReduction,
            routeGeometry: routeCoords,
            sourceDisplayName: sourceDisplayName,
            destDisplayName: destDisplayName
        )
        routeHistory.insert(entry, at: 0)

        if routeHistory.count > 10 {
            routeHistory = Array(routeHistory.prefix(10))
        }

        lifetimeStats.addRoute(distance: distance, time: time, riskReduction: riskReduction)

        persistRouteHistory()
        persistLifetimeStats()
    }

    func clearRouteHistory() {
        routeHistory.removeAll()
        persistRouteHistory()
    }

    func deleteHistoryEntry(_ entry: RouteHistoryEntry) {
        routeHistory.removeAll { $0.id == entry.id }
        persistRouteHistory()
    }

    /// Loads a saved route from history onto the map without making an API call
    func loadRouteFromHistory(_ entry: RouteHistoryEntry) {
        guard let geometry = entry.routeGeometry, !geometry.isEmpty else {
            return
        }

        sourceCoord = entry.sourceCoordinate
        destCoord = entry.destCoordinate
        selectedCity = entry.city

        let coordinates = geometry.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let lineString = LineString(coordinates)

        var properties: JSONObject = [
            "type": .string(entry.routeType),
            "distance_m": .number(entry.distance),
            "time_s": .number(entry.time)
        ]
        if let reduction = entry.riskReduction {
            properties["pred_risk_reduction_pct"] = .number(reduction)
        }

        var feature = Feature(geometry: .lineString(lineString))
        feature.properties = properties

        featureCollection = FeatureCollection(features: [feature])

        isFallbackRoute = false
        routes = [RouteInfo(
            type: entry.routeType,
            distance: entry.distance,
            time: entry.time,
            predRisk: 0
        )]

        selectedRouteType = entry.routeType

        pendingCameraFit = geometry.map { $0.clCoordinate }

        playSuccessFeedback()
    }

    private func loadRouteHistory() {
        guard let data = UserDefaults.standard.data(forKey: routeHistoryKey),
              let history = try? JSONDecoder().decode([RouteHistoryEntry].self, from: data) else {
            return
        }
        routeHistory = history
    }

    private func persistRouteHistory() {
        guard let data = try? JSONEncoder().encode(routeHistory) else { return }
        UserDefaults.standard.set(data, forKey: routeHistoryKey)
    }

    private func loadLifetimeStats() {
        guard let data = UserDefaults.standard.data(forKey: lifetimeStatsKey),
              let stats = try? JSONDecoder().decode(LifetimeStats.self, from: data) else {
            return
        }
        lifetimeStats = stats
    }

    private func persistLifetimeStats() {
        guard let data = try? JSONEncoder().encode(lifetimeStats) else { return }
        UserDefaults.standard.set(data, forKey: lifetimeStatsKey)
    }

    func startShareSession(destinationName: String) {
        guard !isStartingShare,
              let fc = featureCollection,
              let selectedType = selectedRouteType else { return }

        let filtered = fc.features.filter { f in
            if case .string(let val) = f.properties?["type"] { return val == selectedType }
            return false
        }
        guard !filtered.isEmpty,
              let data = try? JSONEncoder().encode(FeatureCollection(features: filtered)) else { return }

        isStartingShare = true
        Task {
            do {
                let citySlug = selectedCity.lowercased().replacingOccurrences(of: " ", with: "")
                let response = try await ApiService.shared.startShareSession(
                    city: citySlug,
                    routeGeoJSON: data,
                    destinationName: destinationName
                )
                self.shareWatchUrl = response.watchUrl
                self.showingShareSheet = true
                self.isStartingShare = false
                NavigationPresenter.shared.setShareSession(
                    sessionId: response.sessionId,
                    writerToken: response.writerToken,
                    city: citySlug
                )
            } catch {
                #if DEBUG
                print("Share My Walk: startShareSession failed.")
                #endif
                self.isStartingShare = false
            }
        }
    }

    func cancelAllTasks() {
        searchTask?.cancel()
        routeTask?.cancel()
        navigationTask?.cancel()
    }
}

extension JSONValue {
    var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }
    var doubleValue: Double? {
        if case let .number(v) = self { return v }
        return nil
    }
    var boolValue: Bool? {
        if case let .boolean(v) = self { return v }
        return nil
    }
}
