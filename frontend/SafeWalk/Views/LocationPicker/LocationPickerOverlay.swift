import SwiftUI
import CoreLocation

enum SheetHeight: CGFloat, CaseIterable {
    case collapsed = 180
    case medium = 380
    case expanded = 600

    static func closestHeight(to value: CGFloat) -> SheetHeight {
        let heights = SheetHeight.allCases.map { $0.rawValue }
        let closest = heights.min(by: { abs($0 - value) < abs($1 - value) }) ?? SheetHeight.collapsed.rawValue
        return SheetHeight(rawValue: closest) ?? .collapsed
    }

    /// Returns closest height, excluding full-screen search height
    static func closestNonSearchHeight(to value: CGFloat, maxHeight: CGFloat) -> CGFloat {
        // If we're closer to full height (search mode), snap to expanded instead
        if value > SheetHeight.expanded.rawValue + 50 {
            return SheetHeight.expanded.rawValue
        }
        return closestHeight(to: value).rawValue
    }
}

struct LocationPickerOverlay: View {
    @ObservedObject var viewModel: RouteViewModel
    var userLocation: CLLocationCoordinate2D?
    var onCameraFit: (CLLocationCoordinate2D) -> Void

    @State private var sheetHeight: CGFloat = SheetHeight.collapsed.rawValue
    @State private var lastDragValue: CGFloat = 0
    @State private var screenHeight: CGFloat = 0
    @State private var initialScreenHeight: CGFloat = 0
    @FocusState private var isSearchFieldFocused: Bool

    private var isShowingRoutes: Bool {
        !viewModel.routes.isEmpty && !viewModel.isSearchFocused
    }

    private var searchModeHeight: CGFloat {
        let baseHeight = initialScreenHeight > 0 ? initialScreenHeight : screenHeight
        return max(baseHeight - 60, SheetHeight.expanded.rawValue)
    }

    var body: some View {
        GeometryReader { geometry in
            let stableHeight = initialScreenHeight > 0 ? initialScreenHeight : geometry.size.height
            let maxHeight = (isSearchFieldFocused ? stableHeight : geometry.size.height) - 60
            let bottomSafeArea = geometry.safeAreaInsets.bottom

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    dragIndicator

                    VStack(spacing: 0) {
                        RouteHeaderView(
                            viewModel: viewModel,
                            isSearchFieldFocused: $isSearchFieldFocused,
                            userLocation: userLocation
                        )

                        Divider()

                        contentView
                    }
                    .padding(.bottom, viewModel.isSearchFocused ? 0 : max(bottomSafeArea, 20))
                }
                .frame(height: min(sheetHeight + bottomSafeArea, maxHeight))
                .frame(maxWidth: .infinity)
                .background(
                    Color(.systemBackground)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -5)
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 16
                    )
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newHeight = sheetHeight - value.translation.height + lastDragValue
                            sheetHeight = max(SheetHeight.collapsed.rawValue, min(newHeight, maxHeight - bottomSafeArea))
                        }
                        .onEnded { value in
                            lastDragValue = 0
                            let velocity = value.predictedEndTranslation.height - value.translation.height

                            var targetHeight = sheetHeight - velocity * 0.3

                            if velocity > 200 && isSearchFieldFocused {
                                isSearchFieldFocused = false
                                viewModel.isSearchFocused = false
                                targetHeight = SheetHeight.collapsed.rawValue
                            }

                            let snappedHeight = SheetHeight.closestNonSearchHeight(to: targetHeight, maxHeight: maxHeight)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                sheetHeight = snappedHeight
                            }
                        }
                )
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .ignoresSafeArea(.keyboard)
            .onAppear {
                screenHeight = geometry.size.height
                initialScreenHeight = geometry.size.height
            }
            .onChange(of: geometry.size.height) { newHeight in
                screenHeight = newHeight
                if initialScreenHeight == 0 {
                    initialScreenHeight = newHeight
                }
            }
        }
        .onChange(of: isSearchFieldFocused) { focused in
            viewModel.isSearchFocused = focused
            if focused {
                let targetHeight = searchModeHeight
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sheetHeight = targetHeight
                    }
                }
            }
        }
        .onChange(of: viewModel.searchText) { newValue in
            handleSearchTextChange(newValue)
        }
        .onChange(of: viewModel.routes) { routes in
            if !routes.isEmpty && !viewModel.isSearchFocused {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    sheetHeight = SheetHeight.medium.rawValue
                }
            }
        }
        .onChange(of: viewModel.isFetching) { isFetching in
            if isFetching && !viewModel.isSearchFocused {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    sheetHeight = SheetHeight.medium.rawValue
                }
            }
        }
        .sheet(isPresented: $viewModel.showSourceOptions) {
            SourceOptionsView(
                viewModel: viewModel,
                userLocation: userLocation,
                onSelectCurrentLocation: {
                    if let loc = userLocation {
                        viewModel.useCurrentLocation(loc)
                        viewModel.tutorialDidSelectCurrentLocation()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sheetHeight = SheetHeight.collapsed.rawValue
                        }
                    }
                },
                onDropPin: {
                    viewModel.mode = .source
                    viewModel.isSearchFocused = false
                    viewModel.tutorialDidTapDropPinForSource()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sheetHeight = SheetHeight.collapsed.rawValue
                    }
                },
                onSearch: {
                    viewModel.activeField = .source
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.isSearchFocused = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sheetHeight = searchModeHeight
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFieldFocused = true
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $viewModel.showDestinationOptions) {
            DestinationOptionsView(
                viewModel: viewModel,
                onDropPin: {
                    viewModel.mode = .destination
                    viewModel.isSearchFocused = false
                    viewModel.tutorialDidTapDropPinForDest()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sheetHeight = SheetHeight.collapsed.rawValue
                    }
                },
                onSearch: {
                    viewModel.activeField = .destination
                    viewModel.tutorialDidStartSearch()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.isSearchFocused = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sheetHeight = searchModeHeight
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFieldFocused = true
                        }
                    }
                }
            )
        }
    }

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(.systemGray3))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isSearchFocused {
            if !viewModel.searchText.isEmpty && !viewModel.searchResults.isEmpty {
                SearchResultsListView(
                    viewModel: viewModel,
                    onSelect: { result in
                        viewModel.selectSearchResult(result)
                        onCameraFit(result.coordinate)
                        isSearchFieldFocused = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sheetHeight = SheetHeight.collapsed.rawValue
                        }
                    }
                )
            } else if viewModel.searchText.isEmpty {
                SuggestionsView(
                    viewModel: viewModel,
                    userLocation: userLocation,
                    onSelectCurrentLocation: {
                        if let loc = userLocation {
                            viewModel.useCurrentLocation(loc)
                            viewModel.tutorialDidSelectCurrentLocation()
                            isSearchFieldFocused = false
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                sheetHeight = SheetHeight.collapsed.rawValue
                            }
                        }
                    },
                    onCameraFit: { coord in
                        onCameraFit(coord)
                        isSearchFieldFocused = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sheetHeight = SheetHeight.collapsed.rawValue
                        }
                    },
                    onDismiss: {
                        isSearchFieldFocused = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sheetHeight = SheetHeight.collapsed.rawValue
                        }
                    }
                )
            } else {
                VStack {
                    if viewModel.searchText.count >= 2 {
                        ProgressView()
                            .padding(.top, 40)
                        Text("Searching...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    } else {
                        Text("Type at least 2 characters")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    }
                    Spacer()
                }
            }
        } else if viewModel.isFetching {
            RouteFetchingView()
        } else if isShowingRoutes {
            RouteOptionsView(
                viewModel: viewModel,
                onSelectRoute: { routeType in
                    viewModel.useRoute(ofType: routeType)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sheetHeight = SheetHeight.collapsed.rawValue
                    }
                }
            )
        } else {
            SuggestionsView(
                viewModel: viewModel,
                userLocation: userLocation,
                onSelectCurrentLocation: {
                    if let loc = userLocation {
                        viewModel.useCurrentLocation(loc)
                    }
                },
                onCameraFit: onCameraFit,
                onDismiss: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sheetHeight = SheetHeight.collapsed.rawValue
                    }
                }
            )
        }
    }

    private func handleSearchTextChange(_ newValue: String) {
        viewModel.searchTask?.cancel()
        if newValue.isEmpty {
            viewModel.clearSearchResults()
        } else {
            guard newValue.count >= 2 else { return }

            viewModel.searchTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await viewModel.searchPlaces(query: newValue, userLocation: userLocation)
            }
        }
    }
}

struct RouteFetchingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .scaleEffect(x: CGFloat(isAnimating ? 1.2 : 1.0), y: CGFloat(isAnimating ? 1.2 : 1.0), anchor: .center)
                    .opacity(isAnimating ? 0.0 : 0.5)

                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: "figure.walk")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(x: isAnimating ? 3 : -3)
            }

            VStack(spacing: 6) {
                Text("Calculating Routes")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Comparing modeled route risk")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(CGFloat(1.1), anchor: .center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calculating routes. Comparing modeled route risk.")
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        LocationPickerOverlay(
            viewModel: RouteViewModel(),
            userLocation: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
            onCameraFit: { _ in }
        )
    }
}

#Preview("Route Fetching") {
    RouteFetchingView()
        .frame(height: 300)
        .background(Color(.systemBackground))
}
