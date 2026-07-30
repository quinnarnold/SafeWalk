import SwiftUI
import CoreLocation
import Turf
internal import MapKit
import MapboxMaps
import MapboxNavigationCore
import MapboxDirections

extension Notification.Name {
    static let runDemoRoute = Notification.Name("runDemoRoute")
}

struct ContentView: View {
    @StateObject private var viewModel = RouteViewModel()
    @EnvironmentObject var appLoader: AppLoader

    @State private var mapCoordinator: MapViewRepresentable.Coordinator?

    @State private var sheetOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    @State private var demoRouteObserver: NSObjectProtocol?

    var body: some View {
        Group {
            if viewModel.showWelcome {
                WelcomeView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                ZStack {
                    NavigationView {
                        mainAppView
                    }

                    LocationPickerOverlay(
                        viewModel: viewModel,
                        userLocation: mapCoordinator?.userLocation,
                        onCameraFit: { coordinate in
                            mapCoordinator?.recenter(to: coordinate, zoom: 15.5)
                        }
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: viewModel.showWelcome)
        .onOpenURL { url in
            viewModel.handleDeepLink(url)
        }
        .onAppear {
            setupNotificationObserver()
        }
        .onDisappear {
            cleanupNotificationObserver()
            viewModel.cancelAllTasks()
        }
    }

    private func setupNotificationObserver() {
        demoRouteObserver = NotificationCenter.default.addObserver(
            forName: .runDemoRoute,
            object: nil,
            queue: .main
        ) { [weak viewModel] _ in
            guard let vm = viewModel else { return }
            Task { @MainActor in
                vm.startDemoTutorial()
            }
        }
    }

    private func cleanupNotificationObserver() {
        if let observer = demoRouteObserver {
            NotificationCenter.default.removeObserver(observer)
            demoRouteObserver = nil
        }
    }

    private var selectedRouteETA: String? {
        guard let type = viewModel.selectedRouteType,
              let route = viewModel.routes.first(where: { $0.type == type }) else { return nil }
        let minutes = Int(route.time / 60)
        return "\(minutes) min"
    }

    private var mainAppView: some View {
        ZStack {
            mapLayer

            if viewModel.selectedRouteType != nil && viewModel.transitNavigationManager == nil {
                startNavigationButton
            }

            if viewModel.isOffline {
                offlineBanner
            }

            if viewModel.tutorialActive {
                tutorialOverlay
            }

            transitNavigationOverlay
        }
        .navigationTitle("SafeWalk")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $viewModel.showHowItWorks) { HowItWorksView() }
        .sheet(isPresented: $viewModel.showAbout) { AboutView() }
        .sheet(isPresented: $viewModel.showTrustedContacts) {
            NavigationStack {
                TrustedContactsSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { viewModel.showTrustedContacts = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $viewModel.showSavedLocations) { SavedLocationsView(viewModel: viewModel) }
        .sheet(isPresented: $viewModel.showRouteHistory) { RouteHistoryView(viewModel: viewModel) }
        .sheet(item: $viewModel.selectedPlace) { place in
            PlaceDetailSheet(
                place: place,
                onDirections: {
                    viewModel.useSelectedPlaceAsDestination(userLocation: mapCoordinator?.userLocation)
                },
                onDismiss: {
                    viewModel.clearSelectedPlace()
                }
            )
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $viewModel.droppedPin) { pin in
            DroppedPinSheet(
                droppedPin: pin,
                onDirections: {
                    viewModel.useDroppedPinAsDestination(userLocation: mapCoordinator?.userLocation)
                },
                onSave: { name in
                    viewModel.saveLocation(name: name, coordinate: pin.coordinate, address: pin.address)
                    viewModel.clearDroppedPin()
                },
                onDismiss: {
                    viewModel.clearDroppedPin()
                }
            )
            .presentationDetents([.fraction(0.25), .medium])
            .presentationDragIndicator(.hidden)
        }
        .onChange(of: viewModel.sourceCoord) { newSourceCoord in
            if newSourceCoord != nil {
                viewModel.tutorialDidSetSource()
            }
            if newSourceCoord != nil && viewModel.destCoord != nil && viewModel.routes.isEmpty {
                viewModel.routeTask?.cancel()
                viewModel.routeTask = Task {
                    await viewModel.getRoute()
                }
            }
        }
        .onChange(of: viewModel.destCoord) { newDestCoord in
            if newDestCoord != nil {
                viewModel.tutorialDidSetDestination()
            }
        }
        .onChange(of: viewModel.routes) { newRoutes in
            if !newRoutes.isEmpty {
                viewModel.tutorialDidGetRoutes()
            }
        }
        .onChange(of: viewModel.selectedRouteType) { newRouteType in
            if newRouteType != nil {
                viewModel.tutorialDidSelectRoute()
            }
        }
        .onChange(of: viewModel.pendingCameraFit) { coordinates in
            if let coords = coordinates, !coords.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    mapCoordinator?.fitToBounds(coordinates: coords)
                    viewModel.pendingCameraFit = nil
                }
            }
        }
        .alert(item: $viewModel.errorMessage) { err in
            Alert(
                title: Text(alertTitle(for: err)),
                message: Text(err.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var mapLayer: some View {
        MapViewRepresentable(
            featureCollection: viewModel.isTransitMode ? nil : viewModel.featureCollection,
            sourceCoord: Binding(
                get: { viewModel.sourceCoord },
                set: { coord in
                    if let c = coord {
                        viewModel.setSourceCoord(c)
                    }
                }
            ),
            destCoord: Binding(
                get: { viewModel.destCoord },
                set: { coord in
                    if let c = coord {
                        viewModel.setDestCoord(c, autoFetchRoute: viewModel.sourceCoord != nil)
                    }
                }
            ),
            mode: $viewModel.mode,
            selectedCity: $viewModel.selectedCity,
            droppedPinCoord: viewModel.droppedPin?.coordinate,
            selectedTransitItinerary: viewModel.isTransitMode ? viewModel.selectedItinerary : nil,
            onLongPress: { coordinate in
                viewModel.dropPin(at: coordinate)
            },
            onPOITap: { name, coordinate, category in
                viewModel.selectPOI(name: name, coordinate: coordinate, category: category)
            }
        )
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                mapCoordinator = MapViewRepresentable.CoordinatorHolder.shared.coordinator
            }
        }
        .accessibilityLabel("Map view")
        .accessibilityHint("Tap to place pins when source or destination mode is active. Long-press to drop a pin.")
    }


    private var startNavigationButton: some View {
        VStack {
            Spacer()
            Button {
                viewModel.navigationTask?.cancel()
                viewModel.navigationTask = Task {
                    await viewModel.startNavigation()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start")
                        .font(.subheadline.weight(.semibold))
                    if let eta = selectedRouteETA {
                        Text("·")
                            .font(.subheadline)
                        Text(eta)
                            .font(.subheadline.weight(.medium))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .cornerRadius(20)
            .padding(.bottom, 200)
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
            .accessibilityLabel("Start navigation")
            .accessibilityHint("Begin turn-by-turn walking navigation")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedRouteType)
    }

    private var offlineBanner: some View {
        VStack {
            HStack {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.white)
                Text("You're offline")
                    .foregroundColor(.white)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.9))
            .cornerRadius(20)
            .padding(.top, 60)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut, value: viewModel.isOffline)
        .accessibilityLabel("Offline mode")
        .accessibilityHint("You need an internet connection to fetch routes")
    }

    private var tutorialOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.endTutorial()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 60)
                    .accessibilityLabel("Skip tutorial")
                }

                Spacer().frame(height: 40)

                Group {
                    switch viewModel.demoStep {
                    case .welcome:
                        TutorialHintView(text: "Welcome! Let's compare walking routes together.")

                    case .tapFromField:
                        TutorialHintView(text: "Step 1: Tap the \"From\" field below to set your starting point.")

                    case .chooseSourceMethod:
                        TutorialHintView(text: "Step 2: Tap \"Current Location\" to use your position, or \"Drop Pin\" to choose on the map.")

                    case .dropSourcePin:
                        TutorialHintView(text: "Step 3: Tap anywhere on the map to drop your starting pin.")

                    case .tapDestField:
                        TutorialHintView(text: "Step 4: Now tap the \"Where to?\" field to set your destination.")

                    case .chooseDestMethod:
                        TutorialHintView(text: "Step 5: Use the search bar to find a place, or tap \"Drop Pin\" to choose on the map.")

                    case .setDestination:
                        TutorialHintView(text: "Step 6: Search for a place and tap a result, or tap on the map to drop your pin.")

                    case .selectRoute:
                        TutorialHintView(text: "Step 7: Routes calculated! Tap a route card to compare distance, time, and modeled risk.")

                    case .done:
                        TutorialHintView(
                            text: "You're all set! Tap the green Start button to begin navigation, or finish the tutorial.",
                            showFinishButton: true,
                            onFinish: { viewModel.endTutorial() }
                        )

                    case .none:
                        EmptyView()
                    }
                }
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.3), value: viewModel.demoStep)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var transitNavigationOverlay: some View {
        if let manager = viewModel.transitNavigationManager {
            TransitNavigationOverlay(
                manager: manager,
                onFinished: {
                    if viewModel.transitNavigationManager === manager {
                        viewModel.transitNavigationManager = nil
                    }
                }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                viewModel.showHowItWorks = true
            } label: {
                Label("Info", systemImage: "info.circle")
            }
            .accessibilityLabel("How it works")
            .accessibilityHint("Learn how SafeWalk compares modeled route risk")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                mapCoordinator?.recenterOnUser()
                viewModel.playImpactFeedback()
            } label: {
                Label("Recenter", systemImage: "location.fill")
            }
            .accessibilityLabel("Recenter map")
            .accessibilityHint("Center the map on your current location")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {

                Button {
                    viewModel.showTrustedContacts = true
                } label: {
                    Label("Share My Walk", systemImage: "location.fill.viewfinder")
                }

                Button {
                    viewModel.showAbout = true
                } label: {
                    Label("About", systemImage: "info.circle")
                }

                Button {
                    viewModel.showTermsOfService = true
                } label: {
                    Label("Safety and Privacy Notice", systemImage: "hand.raised")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityLabel("More options")
            .accessibilityHint("Access saved locations, route history, and settings")
        }
    }

    private func alertTitle(for error: ErrorWrapper) -> String {
        if error.message.localizedCaseInsensitiveContains("network") ||
            error.message.localizedCaseInsensitiveContains("offline") {
            return "Network Error"
        } else if error.message.localizedCaseInsensitiveContains("coordinates") ||
                    error.message.localizedCaseInsensitiveContains("navigation") {
            return "Navigation Unavailable"
        }
        return "Error"
    }
}

struct TutorialHintView: View {
    let text: String
    var showFinishButton: Bool = false
    var onFinish: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 12) {
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                if showFinishButton, let onFinish = onFinish {
                    Button("Finish Tutorial") {
                        onFinish()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(.systemGray3), Color(.systemGray4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(10)
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                    .padding(.bottom, 6)
                    .accessibilityLabel("Finish tutorial")
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemGray5), Color(.systemGray6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
            )
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
    }
}

struct WelcomeView: View {
    @ObservedObject var viewModel: RouteViewModel
    @State private var iconVisible = false
    @State private var termsAccepted = false

    private func acceptAndDismiss() {
        UserDefaults.standard.set(true, forKey: "com.safewalk.termsAccepted")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "com.safewalk.termsAcceptedAt")
        withAnimation(.easeInOut(duration: 0.4)) {
            viewModel.showWelcome = false
        }
        viewModel.playImpactFeedback()
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.walk.circle.fill")
                .resizable()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
                .scaleEffect(iconVisible ? CGFloat(1.0) : CGFloat(0.8))
                .opacity(iconVisible ? 1.0 : 0)
                .animation(.easeOut(duration: 0.6), value: iconVisible)
                .accessibilityHidden(true)

            Text("Welcome to SafeWalk")
                .font(.largeTitle)
                .bold()
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text("Compare walking routes using statistical risk estimates derived from historical public incident data.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            VStack(spacing: 4) {
                Text("SafeWalk provides route suggestions based on historical public safety data. It does not guarantee your personal safety. Always remain aware of your surroundings and use your own judgment.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        termsAccepted.toggle()
                    } label: {
                        Image(systemName: termsAccepted ? "checkmark.square.fill" : "square")
                            .foregroundColor(termsAccepted ? .blue : .secondary)
                            .font(.system(size: 22))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(termsAccepted ? "Notice acknowledged" : "Acknowledge safety and privacy notice")
                    .accessibilityHint("Tap to \(termsAccepted ? "uncheck" : "acknowledge") the notice")

                    Text("I have read the")
                        .font(.subheadline)

                    Button {
                        viewModel.showTermsOfService = true
                    } label: {
                        Text("Safety and Privacy Notice")
                            .font(.subheadline.weight(.semibold))
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)

            VStack(spacing: 12) {
                Button {
                    acceptAndDismiss()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!termsAccepted)
                .accessibilityLabel("Get started")
                .accessibilityHint(termsAccepted ? "Begin using SafeWalk" : "Acknowledge the notice first")

                Button {
                    acceptAndDismiss()
                    NotificationCenter.default.post(name: .runDemoRoute, object: nil)
                } label: {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Take a Guided Tour")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!termsAccepted)
                .accessibilityLabel("Take guided tour")
                .accessibilityHint(termsAccepted ? "Start a step-by-step tutorial" : "Acknowledge the notice first")
            }
            .padding(.horizontal, 40)
        }
        .padding()
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear {
            iconVisible = true
        }
        .sheet(isPresented: $viewModel.showTermsOfService) {
            TermsOfServiceView()
        }
    }
}

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Safety and Privacy Notice")
                        .font(.largeTitle.bold())
                        .padding(.top, 8)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    Text("Last updated: July 30, 2026")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    tosSection(
                        title: "Route model limitations",
                        body: "SafeWalk compares routes using historical public incident data and a statistical model. Data may be incomplete, delayed, unevenly reported, or inaccurate. A lower modeled score is not a prediction or guarantee of safety, and conditions can change at any time."
                    )

                    tosSection(
                        title: "Use your own judgment",
                        body: "SafeWalk is an informational route-planning tool, not emergency assistance, real-time monitoring, or personal security. Remain aware of your surroundings and use your own judgment. Call local emergency services when appropriate."
                    )

                    tosSection(
                        title: "Route requests",
                        body: "The app sends route coordinates, route options, and related request details to the backend configured by the person or organization that built this copy of SafeWalk. The backend may use Mapbox and other configured routing services to fulfill those requests."
                    )

                    tosSection(
                        title: "Share My Walk",
                        body: "When you start sharing, the configured backend temporarily stores the selected route and live location for up to 50 minutes. Anyone with the private watch link can view that information until it expires, so share the link only with people you trust."
                    )

                    tosSection(
                        title: "Data stored on this device",
                        body: "Saved locations, favorite routes, route history, selected city, preferences, and trusted contacts are stored locally on the device or its App Group container. Mapbox access tokens and the App Attest key identifier are stored in the Keychain."
                    )

                    tosSection(
                        title: "Third-party services",
                        body: "Map rendering, navigation, and some routing requests use Mapbox. Mapbox states that its SDKs send limited de-identified location and usage data under its terms; the map keeps Mapbox's attribution and telemetry-control UI visible. Place search can use Apple MapKit, and app authentication can use Apple App Attest."
                    )

                    tosSection(
                        title: "For downstream operators",
                        body: "This notice describes the behavior of the open-source code. Anyone distributing or hosting a modified copy must review its actual data flows and publish their own accurate privacy notice, terms, retention policy, and contact information."
                    )

}
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Safety and Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func tosSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            Text(body)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}

struct HowItWorksView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("How SafeWalk Works")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                    InfoCard(
                        icon: "sparkles",
                        title: "New in 4.0",
                        text: "Transit mode is here. Tap the Transit button after setting a route to see walk + train + bus combinations with safety-scored walking legs. Available in Atlanta, Boston, Chicago, New York, Philadelphia, and Seattle. Plus, routes that start or end outside city coverage now use universal routing instead of cutting off at the city boundary."
                    )

                    InfoCard(
                        icon: "play.circle.fill",
                        title: "Getting Started",
                        text: "New to SafeWalk? Take the guided tour from the welcome screen to learn how to set your start and destination, compare routes, and begin navigation."
                    )

                    InfoCard(
                        icon: "map.circle.fill",
                        title: "Public Safety Data",
                        text: "SafeWalk analyzes publicly available city crime data, including time and location of incidents, to understand local safety patterns. Safety routing is available in Atlanta, Boston, Chicago, New York, Philadelphia, and Seattle, with basic routing worldwide."
                    )

                    InfoCard(
                        icon: "brain.head.profile",
                        title: "Statistical Risk Modeling",
                        text: "SafeWalk uses a time-binned kernel-density estimate of selected historical incidents to compare relative modeled risk near streets. The score is not a prediction that an incident will occur."
                    )

                    InfoCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Dynamic Risk Surface",
                        text: "Using these data points, SafeWalk builds a comprehensive safety surface for each city, estimating relative risk levels along every street and sidewalk."
                    )

                    LegendCard()

                    InfoCard(
                        icon: "figure.walk.circle.fill",
                        title: "Smart Route Choices",
                        text: "When you plan a trip, SafeWalk calculates three route options: Recommended (balances modeled risk and time), Lower Risk, and Fastest. Each shows distance, time, and an estimated risk comparison."
                    )

                    InfoCard(
                        icon: "star.fill",
                        title: "Save Your Favorites",
                        text: "Save frequently used routes and locations for quick access. Assign custom names and icons, or mark routes as Home or Work for one-tap navigation."
                    )

                    InfoCard(
                        icon: "lock.shield.fill",
                        title: "Privacy First",
                        text: "Route coordinates are sent to the configured backend. Saved items remain on the device, while Share My Walk temporarily stores the route and live location for viewers with the private link."
                    )

                    InfoCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "Important",
                        text: "Route suggestions are based on historical public safety data and statistical models. They do not guarantee your personal safety. Conditions can change at any time. Always remain aware of your surroundings and use your own judgment."
                    )
                }
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct InfoCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.blue, .teal)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemGray6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(text)")
    }
}

struct LegendCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue, .teal)
                    .accessibilityHidden(true)

                Text("Route Legend")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }

            LegendRow(color: .blue, text: "Recommended Route – balances modeled risk and travel time.")
            LegendRow(color: .orange, text: "Lower Risk Route – prioritizes the lowest modeled score among the generated options.")
            LegendRow(color: .red, text: "Fastest Route – prioritizes travel time rather than modeled risk.")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemGray6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Route legend. Blue is recommended, balancing modeled risk and travel time. Orange is lower risk. Red is fastest.")
    }
}

struct LegendRow: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.walk.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue, .teal)
                            .accessibilityHidden(true)

                        Text("SafeWalk")
                            .font(.largeTitle.bold())
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                        Text("Walk Informed, Walk Prepared")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                    .padding(.top, 8)

                    AboutCard(
                        title: "Our Mission",
                        text: "SafeWalk helps pedestrians make more informed route decisions. By combining publicly available safety data with statistical risk modeling, we provide additional information to consider when planning your walk. Route suggestions are based on historical data and do not guarantee personal safety."
                    )

                    AboutCard(
                        title: "Current release",
                        text: "Transit mode with safety-scored walking legs, available in Atlanta, Boston, Chicago, New York, Philadelphia, and Seattle. Plus universal routing for routes that start or end outside city coverage."
                    )

                    AboutCard(
                        title: "Key Features",
                        text: "• Statistical route comparisons\n• Three route options: Lower Risk, Recommended, and Fastest\n• Save favorite routes and locations\n• View route history and lifetime statistics\n• Turn-by-turn navigation\n• Works worldwide with risk-weighted routing in Atlanta, Boston, Chicago, New York, Philadelphia, and Seattle"
                    )

                    AboutCard(
                        title: "Privacy First",
                        text: "Route requests send coordinates to the configured backend. Share My Walk temporarily stores route and live-location data for people who have the private share link. SafeWalk has no account database or project-operated general analytics service. Mapbox SDKs include their own telemetry under Mapbox's terms."
                    )

                    AboutCard(
                        title: "Open Source",
                        text: "SafeWalk-authored source code and documentation are available under the MIT License. Third-party SDKs, services, data, generated artifacts, and bundled raster assets have separate terms or provenance requirements. Consult the operator for deployment-specific privacy terms and support."
                    )

                    VStack(spacing: 4) {
                        Text("Version \(version)")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.secondary)

                        Text("MIT-licensed source by SafeWalk contributors.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 12)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AboutCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemGray6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(text)")
    }
}

struct TransitNavigationOverlay: View {
    @ObservedObject var manager: TransitNavigationManager
    let onFinished: () -> Void

    var body: some View {
        switch manager.phase {
        case .boardingTransit(let idx):
            if idx < manager.itinerary.legs.count {
                let leg = manager.itinerary.legs[idx]
                VStack {
                    Spacer()
                    TransitInfoCard(
                        leg: leg,
                        onBoarded: { manager.userBoarded() },
                        onDismiss: {
                            manager.cancel()
                            onFinished()
                        }
                    )
                    .padding(.bottom, 220)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: manager.phase)
            }

        case .ridingTransit(let idx):
            if idx < manager.itinerary.legs.count {
                let leg = manager.itinerary.legs[idx]
                VStack {
                    Spacer()
                    Button {
                        manager.transitLegComplete()
                    } label: {
                        TransitRidingCard(leg: leg)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 220)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: manager.phase)
            }

        case .arrived:
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "flag.checkered")
                        .font(.headline)
                    Text("You have arrived")
                        .font(.headline)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
                .padding(.bottom, 240)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        onFinished()
                    }
                }
            }
            .transition(.opacity)

        default:
            EmptyView()
        }
    }
}
