import SwiftUI
import CoreLocation

struct DroppedPinSheet: View {
    let droppedPin: DroppedPin
    let onDirections: () -> Void
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @State private var showSaveSheet = false
    @State private var saveName = ""

    @Environment(\.dismiss) private var dismiss

    private var displayAddress: String {
        droppedPin.address ?? "Dropped Pin"
    }

    private var coordinateText: String {
        String(format: "%.4f, %.4f",
               droppedPin.coordinate.latitude,
               droppedPin.coordinate.longitude)
    }

    private var shareText: String {
        let name = droppedPin.address ?? "Dropped Pin"
        let lat = droppedPin.coordinate.latitude
        let lon = droppedPin.coordinate.longitude
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return """
        \(name)
        Coordinates: \(String(format: "%.6f, %.6f", lat, lon))
        https://maps.apple.com/?ll=\(lat),\(lon)&q=\(encodedName)
        """
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
        .sheet(isPresented: $showSaveSheet) {
            saveLocationSheet
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
        }
    }

    private var placeHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)

                Image(systemName: "mappin")
                    .font(.system(size: 22))
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                if droppedPin.isLoadingAddress {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(x: 0.8, y: 0.8)
                        Text("Finding address...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(displayAddress)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }

                Text(coordinateText)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                dismiss()
            }

            ActionButton(
                icon: "star.fill",
                label: "Save",
                color: .orange
            ) {
                saveName = droppedPin.address ?? "Dropped Pin"
                showSaveSheet = true
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

    private var saveLocationSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Location name", text: $saveName)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()
            }
            .navigationTitle("Save Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSaveSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            onSave(name)
                            showSaveSheet = false
                            dismiss()
                        }
                    }
                    .disabled(saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        DroppedPinSheet(
            droppedPin: {
                var pin = DroppedPin(coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589))
                pin.address = "123 Boylston St, Boston"
                pin.isLoadingAddress = false
                return pin
            }(),
            onDirections: { print("Directions") },
            onSave: { name in print("Save: \(name)") },
            onDismiss: { print("Dismiss") }
        )
        .frame(height: 240)
        .background(Color(.systemBackground))
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(radius: 10)
    }
    .ignoresSafeArea()
}
