import SwiftUI
import CoreLocation
internal import MapKit

struct SearchResultsListView: View {
    @ObservedObject var viewModel: RouteViewModel
    let onSelect: (SearchResult) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.searchResults) { result in
                    searchResultRow(result)

                    if result.id != viewModel.searchResults.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func searchResultRow(_ result: SearchResult) -> some View {
        Button {
            onSelect(result)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: result.categoryIcon)
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let address = result.address {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let distanceFormatted = result.distanceFormatted {
                    Text(distanceFormatted)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(result.name)\(result.address.map { ", \($0)" } ?? "")\(result.distanceFormatted.map { ", \($0) away" } ?? "")")
        .accessibilityHint("Tap to select as \(viewModel.activeField == .source ? "start" : "destination")")
    }
}

#Preview {
    SearchResultsListView(
        viewModel: {
            let vm = RouteViewModel()
            vm.searchResults = [
                SearchResult(
                    name: "Starbucks",
                    coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
                    distance: 483,
                    address: "123 Main St, Boston, MA",
                    category: .cafe,
                    phone: nil
                ),
                SearchResult(
                    name: "Boston Common",
                    coordinate: CLLocationCoordinate2D(latitude: 42.3551, longitude: -71.0656),
                    distance: 804,
                    address: "Boston, MA",
                    category: .park,
                    phone: nil
                )
            ]
            return vm
        }(),
        onSelect: { _ in }
    )
}
