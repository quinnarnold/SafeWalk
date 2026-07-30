import SwiftUI
import CoreLocation

enum SavedTab: String, CaseIterable {
    case locations = "Locations"
    case routes = "Routes"
}

struct SavedLocationsView: View {
    @ObservedObject var viewModel: RouteViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAddLocation = false
    @State private var newLocationName = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedTab: SavedTab = .locations
    @State private var selectedIcon: LocationIcon = .star
    @State private var editingRoute: FavoriteRoute?
    @State private var editedRouteName = ""
    @State private var editedRouteType: FavoriteRouteType = .custom

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(SavedTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case .locations:
                    locationsContent
                case .routes:
                    routesContent
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedTab == .locations {
                        Button {
                            showAddLocation = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(viewModel.sourceCoord == nil && viewModel.destCoord == nil)
                        .accessibilityLabel("Add saved location")
                        .accessibilityHint("Save current source or destination as a favorite")
                    }
                }
            }
            .sheet(isPresented: $showAddLocation) {
                addLocationSheet
            }
            .sheet(item: $editingRoute) { route in
                editRouteSheet(route)
            }
        }
    }

    @ViewBuilder
    private var locationsContent: some View {
        if viewModel.savedLocations.isEmpty {
            emptyLocationsView
        } else {
            locationsList
        }
    }

    @ViewBuilder
    private var routesContent: some View {
        let cityRoutes = viewModel.favoriteRoutes.filter { $0.city == viewModel.selectedCity }

        if cityRoutes.isEmpty {
            emptyRoutesView
        } else {
            routesList(cityRoutes)
        }
    }

    private var emptyRoutesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Saved Routes")
                .font(.headline)

            Text("Save a route by tapping the star icon on any route card.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func routesList(_ routes: [FavoriteRoute]) -> some View {
        List {
            ForEach(routes) { route in
                favoriteRouteRow(route)
            }
            .onDelete { offsets in
                viewModel.deleteFavoriteRoutes(at: offsets, from: routes)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func favoriteRouteRow(_ route: FavoriteRoute) -> some View {
        Button {
            viewModel.loadFavoriteRoute(route)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if route.favoriteType == .home {
                        Image(systemName: "house.fill")
                            .foregroundColor(.blue)
                    } else if route.favoriteType == .work {
                        Image(systemName: "briefcase.fill")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                    }

                    Text(route.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    routeTypeBadge(route.routeType)

                    Button {
                        editedRouteName = route.name
                        editedRouteType = route.favoriteType
                        editingRoute = route
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.deleteFavoriteRoute(route)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 16) {
                    Label(formatRouteDistance(route.distance), systemImage: "ruler")
                    Label(formatRouteTime(route.time), systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func routeTypeBadge(_ type: String) -> some View {
        Text(routeDisplayName(type))
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(routeTypeColor(type).opacity(0.2))
            .foregroundColor(routeTypeColor(type))
            .clipShape(Capsule())
    }

    private func routeDisplayName(_ type: String) -> String {
        switch type {
        case "moderate": return "Recommended"
        case "safest": return "Lower Risk"
        default: return "Fastest"
        }
    }

    private func routeTypeColor(_ type: String) -> Color {
        switch type {
        case "moderate": return .blue
        case "safest": return .orange
        default: return .red
        }
    }

    private func formatRouteDistance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }

    private func formatRouteTime(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes) min"
    }

    private var emptyLocationsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text("No Saved Locations")
                .font(.headline)

            Text("Drop a pin on the map, then tap the + button to save it as a favorite.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityLabel("Drop a pin on the map, then tap the plus button to save it as a favorite")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var locationsList: some View {
        List {
            ForEach(viewModel.savedLocations) { location in
                locationRow(location)
            }
            .onDelete(perform: viewModel.deleteSavedLocations)
        }
        .listStyle(.insetGrouped)
    }

    private func locationRow(_ location: SavedLocation) -> some View {
        Button {
            useLocation(location)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(
                                red: location.icon.color.red,
                                green: location.icon.color.green,
                                blue: location.icon.color.blue
                            ).opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: location.icon.rawValue)
                            .foregroundColor(Color(
                                red: location.icon.color.red,
                                green: location.icon.color.green,
                                blue: location.icon.color.blue
                            ))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(location.address ?? formatCoordinates(location))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        ShareLink(item: shareText(for: location)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                viewModel.sourceCoord = location.coordinate
                viewModel.playImpactFeedback()
                dismiss()
            } label: {
                Label("Start", systemImage: "location.circle")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteLocation(location)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                viewModel.destCoord = location.coordinate
                viewModel.playImpactFeedback()
                dismiss()
            } label: {
                Label("Go", systemImage: "flag.circle")
            }
            .tint(.blue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(location.name)
        .accessibilityHint("Tap to use as destination. Swipe right to set as start, swipe left for more options.")
    }

    private func formatCoordinates(_ location: SavedLocation) -> String {
        let latDir = location.latitude >= 0 ? "N" : "S"
        let lonDir = location.longitude >= 0 ? "E" : "W"
        return String(format: "%.4f°%@ %.4f°%@", abs(location.latitude), latDir, abs(location.longitude), lonDir)
    }

    private func useLocation(_ location: SavedLocation) {
        viewModel.destCoord = location.coordinate
        viewModel.playImpactFeedback()
        dismiss()
    }

    private func shareText(for location: SavedLocation) -> String {
        var text = "Check out this location: \(location.name)\n\n"
        text += String(format: "Coordinates: %.6f, %.6f\n", location.latitude, location.longitude)
        text += String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=%@", location.latitude, location.longitude, location.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location.name)
        return text
    }

    private var addLocationSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Location Name", text: $newLocationName)
                        .accessibilityLabel("Location name")
                        .accessibilityHint("Enter a name for this saved location")
                }

                Section("Choose Icon") {
                    iconPicker
                }

                Section("Choose Pin to Save") {
                    if let source = viewModel.sourceCoord {
                        Button {
                            selectedCoordinate = source
                        } label: {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                    .foregroundColor(.green)
                                Text("Source Pin")
                                Spacer()
                                if selectedCoordinate?.latitude == source.latitude &&
                                    selectedCoordinate?.longitude == source.longitude {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                        .accessibilityLabel("Source pin")
                        .accessibilityHint("Select source pin to save")
                    }

                    if let dest = viewModel.destCoord {
                        Button {
                            selectedCoordinate = dest
                        } label: {
                            HStack {
                                Image(systemName: "flag.circle.fill")
                                    .foregroundColor(.red)
                                Text("Destination Pin")
                                Spacer()
                                if selectedCoordinate?.latitude == dest.latitude &&
                                    selectedCoordinate?.longitude == dest.longitude {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                        .accessibilityLabel("Destination pin")
                        .accessibilityHint("Select destination pin to save")
                    }
                }
            }
            .navigationTitle("Save Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showAddLocation = false
                        newLocationName = ""
                        selectedCoordinate = nil
                        selectedIcon = .star
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveLocation()
                    }
                    .disabled(newLocationName.isEmpty || selectedCoordinate == nil)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var iconPicker: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 50), spacing: 12)
        ], spacing: 12) {
            ForEach(LocationIcon.allCases, id: \.self) { icon in
                Button {
                    selectedIcon = icon
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(
                                red: icon.color.red,
                                green: icon.color.green,
                                blue: icon.color.blue
                            ).opacity(selectedIcon == icon ? 1.0 : 0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: icon.rawValue)
                            .font(.system(size: 18))
                            .foregroundColor(selectedIcon == icon ? .white : Color(
                                red: icon.color.red,
                                green: icon.color.green,
                                blue: icon.color.blue
                            ))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func saveLocation() {
        guard let coord = selectedCoordinate, !newLocationName.isEmpty else { return }
        viewModel.saveLocation(name: newLocationName, coordinate: coord, icon: selectedIcon)
        showAddLocation = false
        newLocationName = ""
        selectedCoordinate = nil
        selectedIcon = .star
    }

    private func editRouteSheet(_ route: FavoriteRoute) -> some View {
        NavigationView {
            Form {
                Section("Route Name") {
                    TextField("Name", text: $editedRouteName)
                }

                Section("Icon") {
                    routeIconPicker
                }

                Section("Route Info") {
                    HStack {
                        Text("Distance")
                        Spacer()
                        Text(formatRouteDistance(route.distance))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Time")
                        Spacer()
                        Text(formatRouteTime(route.time))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Type")
                        Spacer()
                        routeTypeBadge(route.routeType)
                    }
                }
            }
            .navigationTitle("Edit Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        editingRoute = nil
                        editedRouteName = ""
                        editedRouteType = .custom
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.updateFavoriteRoute(route, name: editedRouteName, favoriteType: editedRouteType)
                        editingRoute = nil
                        editedRouteName = ""
                        editedRouteType = .custom
                    }
                    .disabled(editedRouteName.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var routeIconPicker: some View {
        HStack(spacing: 16) {
            ForEach([FavoriteRouteType.custom, .home, .work], id: \.self) { type in
                Button {
                    editedRouteType = type
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(routeIconColor(type).opacity(editedRouteType == type ? 1.0 : 0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: routeIconName(type))
                                .font(.system(size: 18))
                                .foregroundColor(editedRouteType == type ? .white : routeIconColor(type))
                        }
                        Text(routeIconLabel(type))
                            .font(.caption)
                            .foregroundColor(editedRouteType == type ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func routeIconName(_ type: FavoriteRouteType) -> String {
        switch type {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .custom: return "star.fill"
        }
    }

    private func routeIconColor(_ type: FavoriteRouteType) -> Color {
        switch type {
        case .home: return .blue
        case .work: return .orange
        case .custom: return .yellow
        }
    }

    private func routeIconLabel(_ type: FavoriteRouteType) -> String {
        switch type {
        case .home: return "Home"
        case .work: return "Work"
        case .custom: return "Custom"
        }
    }
}
