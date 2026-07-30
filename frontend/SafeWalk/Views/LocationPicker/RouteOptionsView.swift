import SwiftUI
import CoreLocation

struct RouteOptionsView: View {
    @ObservedObject var viewModel: RouteViewModel
    var onSelectRoute: (String) -> Void

    @State private var showingSaveSheet = false
    @State private var routeToSave: RouteInfo?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isFetching && viewModel.routes.isEmpty {
                        ForEach(0..<3, id: \.self) { index in
                            SkeletonRouteCard()
                                .animation(
                                    .easeOut(duration: 0.3).delay(Double(index) * 0.1),
                                    value: viewModel.isFetching
                                )
                        }
                    } else {
                        ForEach(Array(viewModel.routes.enumerated()), id: \.element.id) { index, route in
                            RouteOptionCard(
                                route: route,
                                shortestRoute: viewModel.shortestRoute,
                                isSelected: viewModel.selectedRouteType == route.type,
                                isSaved: viewModel.isFavoriteRoute(
                                    source: viewModel.sourceCoord ?? CLLocationCoordinate2D(),
                                    destination: viewModel.destCoord ?? CLLocationCoordinate2D(),
                                    routeType: route.type
                                ),
                                isFallback: viewModel.isFallbackRoute,
                                onSelect: {
                                    onSelectRoute(route.type)
                                },
                                onSave: {
                                    viewModel.selectRouteType(route.type)
                                    routeToSave = route
                                    showingSaveSheet = true
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                            .animation(
                                .easeOut(duration: 0.3).delay(Double(index) * 0.1),
                                value: viewModel.routes.count
                            )
                        }

                        Button {
                            Task {
                                await viewModel.calculateTransitRoute()
                            }
                            viewModel.isTransitMode = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "tram.fill")
                                    .font(.title3)
                                Text("Transit")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(viewModel.isTransitMode ? Color.purple.opacity(0.15) : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(viewModel.isTransitMode ? Color.purple : .clear, lineWidth: 2)
                            )
                        }

                        if viewModel.isTransitMode {
                            if viewModel.isLoadingTransit {
                                ProgressView("Finding transit routes...")
                                    .padding()
                            } else if let error = viewModel.transitError {
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding()
                            } else {
                                ForEach(viewModel.transitItineraries) { itinerary in
                                    let isSelected = viewModel.selectedItinerary?.id == itinerary.id
                                    VStack(alignment: .leading, spacing: 0) {
                                        Button {
                                            viewModel.selectedItinerary = itinerary
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    ForEach(itinerary.legs.filter(\.isTransit)) { leg in
                                                        if let route = leg.route {
                                                            Text(route.shortName ?? route.longName ?? leg.mode)
                                                                .font(.caption.bold())
                                                                .padding(.horizontal, 6)
                                                                .padding(.vertical, 2)
                                                                .background(Color(hex: route.color ?? "") ?? .purple)
                                                                .foregroundStyle(.white)
                                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                                        }
                                                    }
                                                    Spacer()
                                                    Text(itinerary.formattedDuration)
                                                        .font(.subheadline.bold())
                                                }

                                                ForEach(itinerary.legs) { leg in
                                                    TransitLegView(leg: leg)
                                                }
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)

                                        if isSelected {
                                            Button {
                                                viewModel.startTransitNavigation()
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "tram.fill")
                                                        .font(.system(size: 13, weight: .semibold))
                                                    Text("Start Transit Navigation")
                                                        .font(.subheadline.weight(.semibold))
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(Color.purple)
                                                .foregroundStyle(.white)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            .padding([.horizontal, .bottom], 12)
                                            .accessibilityLabel("Start transit navigation")
                                            .accessibilityHint("Begin segmented walk and transit navigation")
                                        }
                                    }
                                    .background(
                                        isSelected
                                            ? Color.purple.opacity(0.08)
                                            : Color(.systemGray6)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if viewModel.isFallbackRoute {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Safety routing not available for this area")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            if !viewModel.routes.isEmpty && !viewModel.isFetching {
                Text("Routes based on historical data. Not a guarantee of safety.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            if viewModel.selectedRouteType != nil {
                Button {
                    viewModel.startShareSession(
                        destinationName: viewModel.destDisplayName ?? "Destination"
                    )
                } label: {
                    HStack {
                        Image(systemName: "location.fill.viewfinder")
                        Text("Share My Walk")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isStartingShare)
                .padding(.horizontal, 16)
                .sheet(isPresented: $viewModel.showingShareSheet) {
                    if let url = viewModel.shareWatchUrl {
                        ShareMyWalkSheet(watchUrl: url) {
                            viewModel.showingShareSheet = false
                        }
                    }
                }
            }

            if viewModel.isFetching && !viewModel.routes.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(x: 0.8, y: 0.8, anchor: .center)
                    Text("Calculating routes...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveRouteSheet(
                viewModel: viewModel,
                routeToSave: routeToSave,
                isPresented: $showingSaveSheet
            )
        }
    }
}

struct SkeletonRouteCard: View {
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(height: 70)
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color(.systemGray5),
                            Color(.systemGray4).opacity(0.6),
                            Color(.systemGray5)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 100)
                    .offset(x: shimmerOffset)
                    .onAppear {
                        withAnimation(
                            .linear(duration: 1.2)
                            .repeatForever(autoreverses: false)
                        ) {
                            shimmerOffset = geometry.size.width + 100
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct RouteOptionCard: View {
    let route: RouteInfo
    let shortestRoute: RouteInfo?
    let isSelected: Bool
    let isSaved: Bool
    var isFallback: Bool = false
    let onSelect: () -> Void
    let onSave: () -> Void

    private var isRecommended: Bool {
        route.type == "moderate"
    }

    private var riskReductionPercent: Double? {
        if isFallback { return nil }
        guard let shortest = shortestRoute, shortest.predRisk > 0 else { return nil }
        let reduction = (shortest.predRisk - route.predRisk) / shortest.predRisk * 100
        return reduction > 0 ? reduction : nil
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(routeColor)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(routeDisplayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))
                        }
                    }

                    HStack(spacing: 8) {
                        Label(formatDistance(route.distance), systemImage: "arrow.left.and.right")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label(formatTime(route.time), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let pct = riskReductionPercent {
                    Text(String(format: "%.0f%% lower modeled risk", pct))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.green)
                        )
                }

                Button {
                    onSave()
                } label: {
                    Image(systemName: isSaved ? "star.fill" : "star")
                        .foregroundColor(isSaved ? .yellow : .secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
                .accessibilityLabel(isSaved ? "Route saved" : "Save route")
                .accessibilityHint(isSaved ? "This route is already saved" : "Tap to save this route as a favorite")
            }
            .padding(isRecommended ? 14 : 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isSelected ? Color.blue : (isRecommended ? Color.blue.opacity(0.3) : Color.clear),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(routeDisplayName) route, \(formatDistance(route.distance)), \(formatTime(route.time))\(riskReductionPercent.map { ", \(String(format: "%.0f percent lower modeled risk", $0))" } ?? "")")
        .accessibilityHint(isSelected ? "Currently selected" : "Tap to select this route")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var routeDisplayName: String {
        if isFallback { return "Shortest" }
        switch route.type {
        case "moderate": return "Recommended"
        case "safest": return "Lower Risk"
        case "shortest": return "Fastest"
        default: return route.type.capitalized
        }
    }

    private var routeColor: Color {
        switch route.type {
        case "moderate": return .blue
        case "safest": return .orange
        default: return .red
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes) min"
    }
}

#Preview {
    RouteOptionsView(
        viewModel: {
            let vm = RouteViewModel()
            vm.routes = [
                RouteInfo(type: "moderate", distance: 1500, time: 1200, predRisk: 0.25),
                RouteInfo(type: "safest", distance: 1800, time: 1400, predRisk: 0.15),
                RouteInfo(type: "shortest", distance: 1200, time: 1000, predRisk: 0.35)
            ]
            vm.selectedRouteType = "moderate"
            vm.sourceCoord = CLLocationCoordinate2D(latitude: 42.36, longitude: -71.06)
            vm.destCoord = CLLocationCoordinate2D(latitude: 42.37, longitude: -71.07)
            return vm
        }(),
        onSelectRoute: { _ in }
    )
}
