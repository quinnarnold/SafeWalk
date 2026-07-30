import SwiftUI
import CoreLocation

struct SuggestionsView: View {
    @ObservedObject var viewModel: RouteViewModel
    var userLocation: CLLocationCoordinate2D?
    var onSelectCurrentLocation: () -> Void
    var onCameraFit: (CLLocationCoordinate2D) -> Void
    var onDismiss: (() -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if viewModel.activeField == .source && userLocation != nil {
                    CurrentLocationRow(onTap: onSelectCurrentLocation)

                    Divider()
                        .padding(.leading, 52)
                }

                QuickActionsSection(viewModel: viewModel, onCameraFit: onCameraFit)

                if viewModel.homeRoute(for: viewModel.selectedCity) != nil ||
                   viewModel.workRoute(for: viewModel.selectedCity) != nil {
                    shortcutsSection
                }

                let cityFavorites = viewModel.favoriteRoutes.filter {
                    $0.favoriteType == .custom && $0.city == viewModel.selectedCity
                }
                if !cityFavorites.isEmpty {
                    sectionHeader("Favorite Routes")
                    ForEach(cityFavorites.prefix(5)) { route in
                        favoriteRouteRow(route)
                        Divider().padding(.leading, 52)
                    }
                }

                if !viewModel.recentSearches.isEmpty {
                    sectionHeader("Recent")

                    ForEach(viewModel.recentSearches) { recent in
                        recentSearchRow(recent)
                    }
                }

                if !viewModel.savedLocations.isEmpty {
                    sectionHeader("Saved")

                    ForEach(viewModel.savedLocations) { location in
                        savedLocationRow(location)
                    }
                }

                if !viewModel.routeHistory.isEmpty {
                    sectionHeader("Recent Routes")

                    ForEach(viewModel.routeHistory.prefix(5)) { entry in
                        routeHistoryRow(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        sectionHeader("Shortcuts")

        if let homeRoute = viewModel.homeRoute(for: viewModel.selectedCity) {
            shortcutRow(
                route: homeRoute,
                icon: "house.fill",
                color: .blue
            )
            Divider().padding(.leading, 52)
        }

        if let workRoute = viewModel.workRoute(for: viewModel.selectedCity) {
            shortcutRow(
                route: workRoute,
                icon: "briefcase.fill",
                color: .orange
            )
            Divider().padding(.leading, 52)
        }
    }

    private func shortcutRow(route: FavoriteRoute, icon: String, color: Color) -> some View {
        Button {
            viewModel.loadFavoriteRoute(route)
            onDismiss?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    Text(formatTime(route.time))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                recalculateRoute(route)
            } label: {
                Label("Recalculate", systemImage: "arrow.clockwise")
            }
            .disabled(!viewModel.isOnline)

            Button(role: .destructive) {
                viewModel.deleteFavoriteRoute(route)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func recalculateRoute(_ route: FavoriteRoute) {
        viewModel.sourceCoord = route.sourceCoordinate
        viewModel.destCoord = route.destCoordinate
        viewModel.selectedCity = route.city

        Task {
            await viewModel.getRoute()
        }

        onDismiss?()
    }

    private func favoriteRouteRow(_ route: FavoriteRoute) -> some View {
        Button {
            viewModel.loadFavoriteRoute(route)
            onDismiss?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(route.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(formatDistance(route.distance))
                        Text(formatTime(route.time))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Circle()
                    .fill(routeTypeColor(route.routeType))
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                recalculateRoute(route)
            } label: {
                Label("Recalculate", systemImage: "arrow.clockwise")
            }
            .disabled(!viewModel.isOnline)

            Button(role: .destructive) {
                viewModel.deleteFavoriteRoute(route)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func routeTypeColor(_ type: String) -> Color {
        switch type {
        case "moderate": return .blue
        case "safest": return .orange
        default: return .red
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    private func recentSearchRow(_ recent: RecentSearch) -> some View {
        Button {
            viewModel.selectRecentSearch(recent)
            onCameraFit(recent.coordinate)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let address = recent.address {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(recent.name)\(recent.address.map { ", \($0)" } ?? "")")
        .accessibilityHint("Tap to select as \(viewModel.activeField == .source ? "start" : "destination")")
    }

    private func savedLocationRow(_ location: SavedLocation) -> some View {
        Button {
            viewModel.selectSavedLocation(location)
            onCameraFit(location.coordinate)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.yellow)
                    .frame(width: 32)

                Text(location.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(location.name)
        .accessibilityHint("Tap to select as \(viewModel.activeField == .source ? "start" : "destination")")
    }

    private func routeHistoryRow(_ entry: RouteHistoryEntry) -> some View {
        Button {
            viewModel.loadRouteFromHistory(entry)
            if let geometry = entry.routeGeometry, !geometry.isEmpty {
                onCameraFit(geometry[0].clCoordinate)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    if let from = entry.sourceDisplayName, let to = entry.destDisplayName {
                        Text("\(from) \u{2192} \(to)")
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    } else {
                        Text("\(entry.city.capitalized) Route")
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Text(formatDistance(entry.distance))
                        Text("•")
                        Text(formatTime(entry.time))
                        if let reduction = entry.riskReduction, reduction > 0 {
                            Text("•")
                            Text(String(format: "%.0f%% lower modeled risk", reduction))
                                .foregroundColor(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Text(formatRelativeDate(entry.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.city) route, \(formatDistance(entry.distance)), \(formatTime(entry.time))")
        .accessibilityHint("Tap to load this route on the map")
    }

    private func formatDistance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes) min"
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    SuggestionsView(
        viewModel: {
            let vm = RouteViewModel()
            vm.recentSearches = [
                RecentSearch(name: "Starbucks", address: "123 Main St", coordinate: CLLocationCoordinate2D(latitude: 42.36, longitude: -71.06))
            ]
            return vm
        }(),
        userLocation: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
        onSelectCurrentLocation: {},
        onCameraFit: { _ in },
        onDismiss: {}
    )
}
