import SwiftUI
import CoreLocation

struct DestinationOptionsView: View {
    @ObservedObject var viewModel: RouteViewModel
    var onDropPin: () -> Void
    var onSearch: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Set Destination")
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                LocationOptionRow(
                    icon: "mappin",
                    iconColor: .red,
                    title: "Drop Pin on Map",
                    subtitle: "Tap the map to set destination"
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
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    DestinationOptionsView(
        viewModel: RouteViewModel(),
        onDropPin: {},
        onSearch: {}
    )
}
