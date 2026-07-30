import SwiftUI
import CoreLocation

struct RouteHeaderView: View {
    @ObservedObject var viewModel: RouteViewModel
    var isSearchFieldFocused: FocusState<Bool>.Binding
    var userLocation: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                routeIndicators

                VStack(spacing: 8) {
                    LocationFieldRow(
                        icon: "circle.fill",
                        iconColor: .green,
                        placeholder: "Current Location",
                        displayText: sourceDisplayText,
                        isActive: viewModel.activeField == .source && viewModel.isSearchFocused,
                        searchText: viewModel.activeField == .source ? $viewModel.searchText : .constant(""),
                        onTap: {
                            viewModel.activeField = .source
                            viewModel.showSourceOptions = true
                            viewModel.tutorialDidTapFromField()
                        },
                        onClear: {
                            viewModel.clearSourceField()
                        }
                    )
                    .focused(isSearchFieldFocused, equals: viewModel.activeField == .source)

                    LocationFieldRow(
                        icon: "mappin.circle.fill",
                        iconColor: .red,
                        placeholder: "Where to?",
                        displayText: destDisplayText,
                        isActive: viewModel.activeField == .destination && viewModel.isSearchFocused,
                        searchText: viewModel.activeField == .destination ? $viewModel.searchText : .constant(""),
                        onTap: {
                            viewModel.activeField = .destination
                            viewModel.showDestinationOptions = true
                            viewModel.tutorialDidTapDestField()
                        },
                        onClear: {
                            viewModel.clearDestinationField()
                        }
                    )
                    .focused(isSearchFieldFocused, equals: viewModel.activeField == .destination)
                }

                VStack(spacing: 8) {
                    swapButton

                    if !viewModel.routes.isEmpty || viewModel.destCoord != nil {
                        clearButton
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var sourceDisplayText: String? {
        if viewModel.useCurrentLocationAsSource && viewModel.sourceCoord == nil {
            return nil // Show placeholder
        }
        return viewModel.sourceDisplayName ?? (viewModel.sourceCoord != nil ? "Dropped Pin" : nil)
    }

    private var destDisplayText: String? {
        return viewModel.destDisplayName ?? (viewModel.destCoord != nil ? "Dropped Pin" : nil)
    }

    private var routeIndicators: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(Color(.systemGray3))
                .frame(width: 2, height: 24)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        }
        .accessibilityHidden(true)
    }

    private var swapButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.swapSourceAndDestination()
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color(.systemGray6))
                )
        }
        .disabled(viewModel.sourceCoord == nil && viewModel.destCoord == nil)
        .opacity((viewModel.sourceCoord == nil && viewModel.destCoord == nil) ? 0.5 : 1)
        .accessibilityLabel("Swap start and destination")
        .accessibilityHint("Exchanges the start and destination locations")
    }

    private var clearButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.clearRoute()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color(.systemGray6))
                )
        }
        .accessibilityLabel("Clear route")
        .accessibilityHint("Clears the current route and destination")
    }
}

#Preview {
    @FocusState var focused: Bool

    return VStack {
        RouteHeaderView(
            viewModel: RouteViewModel(),
            isSearchFieldFocused: $focused,
            userLocation: nil
        )
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
