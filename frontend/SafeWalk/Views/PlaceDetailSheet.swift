import SwiftUI
import UIKit
import CoreLocation

struct PlaceDetailSheet: View {
    let place: SelectedPlace
    let onDirections: () -> Void
    let onDismiss: () -> Void

    private var shareText: String {
        let lat = place.coordinate.latitude
        let lon = place.coordinate.longitude
        let encodedName = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place.name
        var text = "\(place.name)"
        if let address = place.address {
            text += "\n\(address)"
        }
        text += "\nhttps://maps.apple.com/?ll=\(lat),\(lon)&q=\(encodedName)"
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            placeHeader
                .padding(.horizontal, 20)

            Divider()
                .padding(.top, 16)

            actionButtons
                .padding(.vertical, 16)
                .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color(.systemBackground))
    }

    private var placeHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)

                Image(systemName: place.categoryIcon)
                    .font(.system(size: 22))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if let category = place.category {
                    Text(category)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if place.isLoading {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(x: 0.7, y: 0.7)
                        Text("Loading details...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let address = place.address {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            ActionButton(
                icon: "arrow.triangle.turn.up.right.circle.fill",
                label: "Directions",
                color: .blue
            ) {
                onDirections()
            }

            if let phone = place.phone, !phone.isEmpty {
                ActionButton(
                    icon: "phone.fill",
                    label: "Call",
                    color: .green
                ) {
                    callPhone(phone)
                }
            }

            if let website = place.website {
                ActionButton(
                    icon: "safari.fill",
                    label: "Website",
                    color: .orange
                ) {
                    openWebsite(website)
                }
            }

            ShareLink(item: shareText) {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 52, height: 52)

                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                    }
                    Text("Share")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func callPhone(_ phone: String) {
        let cleaned = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let url = URL(string: "tel://\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    private func openWebsite(_ url: URL) {
        UIApplication.shared.open(url)
    }
}


#Preview {
    VStack {
        Spacer()
        PlaceDetailSheet(
            place: {
                var p = SelectedPlace(
                    name: "Tatte Bakery & Cafe",
                    coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
                    category: "Cafe"
                )
                p.isLoading = false
                p.address = "123 Boylston St, Boston, MA"
                p.phone = "(617) 555-1234"
                p.website = URL(string: "https://tattebakery.com")
                return p
            }(),
            onDirections: { print("Directions") },
            onDismiss: { print("Dismiss") }
        )
        .frame(height: 280)
        .background(Color(.systemBackground))
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
    }
    .ignoresSafeArea()
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
