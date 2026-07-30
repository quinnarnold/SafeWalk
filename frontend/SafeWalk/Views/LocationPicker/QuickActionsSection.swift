import SwiftUI
import CoreLocation

struct QuickActionsSection: View {
    @ObservedObject var viewModel: RouteViewModel
    var onCameraFit: (CLLocationCoordinate2D) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                QuickActionButton(
                    icon: "mappin",
                    title: "Drop Pin",
                    color: .red
                ) {
                    switch viewModel.activeField {
                    case .source:
                        viewModel.mode = .source
                        viewModel.tutorialDidTapDropPinForSource()
                    case .destination:
                        viewModel.mode = .destination
                        viewModel.tutorialDidTapDropPinForDest()
                    }
                    viewModel.isSearchFocused = false
                }

                QuickActionButton(
                    icon: "star.fill",
                    title: "Saved",
                    color: .yellow
                ) {
                    viewModel.showSavedLocations = true
                }

                QuickActionButton(
                    icon: "clock.arrow.circlepath",
                    title: "History",
                    color: .blue
                ) {
                    viewModel.showRouteHistory = true
                }
            }
            .padding(.leading, 32)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(color.opacity(0.15))
                    )

                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview {
    QuickActionsSection(
        viewModel: RouteViewModel(),
        onCameraFit: { _ in }
    )
}
