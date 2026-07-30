import SwiftUI
import CoreLocation

struct SourceOptionsView: View {
    @ObservedObject var viewModel: RouteViewModel
    var userLocation: CLLocationCoordinate2D?
    var onSelectCurrentLocation: () -> Void
    var onDropPin: () -> Void
    var onSearch: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Set Start Location")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                LocationOptionRow(
                    icon: "location.fill",
                    iconColor: .blue,
                    title: "Current Location",
                    subtitle: userLocation != nil ? "Use your GPS location" : "Location unavailable"
                ) {
                    onSelectCurrentLocation()
                    dismiss()
                }
                .disabled(userLocation == nil)

                Divider()
                    .padding(.leading, 56)

                LocationOptionRow(
                    icon: "mappin",
                    iconColor: .red,
                    title: "Drop Pin on Map",
                    subtitle: "Tap the map to set start"
                ) {
                    onDropPin()
                    dismiss()
                }

                Divider()
                    .padding(.leading, 56)

                LocationOptionRow(
                    icon: "magnifyingglass",
                    iconColor: .gray,
                    title: "Search for Location",
                    subtitle: "Find an address or place"
                ) {
                    onSearch()
                    dismiss()
                }
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal, 16)

            Spacer()
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}

struct LocationOptionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isEnabled ? iconColor : .gray)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(isEnabled ? .primary : .secondary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SourceOptionsView(
        viewModel: RouteViewModel(),
        userLocation: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
        onSelectCurrentLocation: {},
        onDropPin: {},
        onSearch: {}
    )
}
