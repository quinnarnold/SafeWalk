import SwiftUI

struct TransitInfoCard: View {
    let leg: TransitLeg
    let onBoarded: () -> Void
    let onDismiss: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Board Transit")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .accessibilityLabel("Dismiss")
            }

            HStack(spacing: 12) {
                Image(systemName: transitIcon)
                    .font(.title2)
                    .foregroundStyle(routeColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let route = leg.route {
                            Text(route.shortName ?? route.longName ?? leg.mode)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(routeColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            if let longName = route.longName {
                                Text(longName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                        } else {
                            Text(leg.mode.capitalized)
                                .font(.subheadline.weight(.medium))
                        }
                    }

                    Text("Board at \(leg.from.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Departs \(departureTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "list.number")
                    .foregroundStyle(.secondary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(rideDescription)
                        .font(.subheadline)

                    Text("Exit at \(leg.to.name)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }

            if let stops = leg.intermediateStops, !stops.isEmpty {
                intermediateStopsView(stops)
            }

            Button(action: onBoarded) {
                Text("I've Boarded")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(routeColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("I have boarded the transit")
            .accessibilityHint("Tap when you are on board to track the ride")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func intermediateStopsView(_ stops: [IntermediateStop]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup {
                ForEach(stops, id: \.name) { stop in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(routeColor.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(stop.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 2)
                }
            } label: {
                Text("Intermediate stops (\(stops.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transitIcon: String {
        switch leg.mode {
        case "SUBWAY": return "tram.fill"
        case "BUS": return "bus.fill"
        case "RAIL": return "train.side.front.car"
        case "TRAM": return "tram"
        case "FERRY": return "ferry.fill"
        default: return "arrow.right.circle.fill"
        }
    }

    private var routeColor: Color {
        if let hex = leg.route?.color, let color = Color(hex: hex) {
            return color
        }
        return .purple
    }

    private var departureTime: String {
        let date = Date(timeIntervalSince1970: leg.startTime / 1000)
        return Self.timeFormatter.string(from: date)
    }

    private var rideDescription: String {
        let stopCount: Int
        if let stops = leg.intermediateStops {
            stopCount = stops.count + 1
        } else {
            let minutes = Int(leg.duration) / 60
            return "Ride approx. \(minutes) min"
        }
        return "Ride \(stopCount) stop\(stopCount == 1 ? "" : "s")"
    }
}

struct TransitRidingCard: View {
    let leg: TransitLeg

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transitIcon)
                .font(.title3)
                .foregroundStyle(routeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let route = leg.route {
                        Text(route.shortName ?? route.longName ?? leg.mode)
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(routeColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text("Riding")
                        .font(.subheadline.weight(.medium))
                }

                Text("Exit at \(leg.to.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Arrives \(arrivalTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.up.circle")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
    }

    private var transitIcon: String {
        switch leg.mode {
        case "SUBWAY": return "tram.fill"
        case "BUS": return "bus.fill"
        case "RAIL": return "train.side.front.car"
        case "TRAM": return "tram"
        case "FERRY": return "ferry.fill"
        default: return "arrow.right.circle.fill"
        }
    }

    private var routeColor: Color {
        if let hex = leg.route?.color, let color = Color(hex: hex) {
            return color
        }
        return .purple
    }

    private var arrivalTime: String {
        let date = Date(timeIntervalSince1970: leg.endTime / 1000)
        return Self.timeFormatter.string(from: date)
    }
}
