import SwiftUI

struct TransitLegView: View {
    let leg: TransitLeg

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            legIcon
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                if leg.isWalk {
                    Text("Walk to \(leg.to.name)")
                        .font(.subheadline)
                    HStack(spacing: 8) {
                        Text(formatDistance(leg.distanceM))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(legTimeRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let safetyType = leg.safetyType, safetyType != "shortest" {
                        Text(safetyType.capitalized + " route")
                            .font(.caption2)
                            .foregroundStyle(safetyType == "safest" ? .orange : .blue)
                    }
                } else {
                    HStack(spacing: 6) {
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
                                    .font(.subheadline)
                            }
                        } else {
                            Text(leg.mode)
                                .font(.subheadline)
                        }
                    }
                    Text("\(leg.from.name) -> \(leg.to.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(legTimeRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let stops = leg.intermediateStops, !stops.isEmpty {
                            Text("\(stops.count + 1) stops")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Text(formatDuration(leg.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var legIcon: some View {
        if leg.isWalk {
            Image(systemName: "figure.walk")
                .foregroundStyle(legColor)
        } else {
            Image(systemName: transitIcon)
                .foregroundStyle(legColor)
        }
    }

    private var transitIcon: String {
        switch leg.mode {
        case "SUBWAY": return "tram.fill"
        case "BUS": return "bus.fill"
        case "RAIL": return "train.side.front.car"
        case "TRAM": return "tram"
        case "FERRY": return "ferry.fill"
        default: return "arrow.right"
        }
    }

    private var routeColor: Color {
        if let hex = leg.route?.color, let color = Color(hex: hex) {
            return color
        }
        return .purple
    }

    private var legColor: Color {
        if leg.isWalk {
            switch leg.safetyType {
            case "moderate": return .blue
            case "safest": return .orange
            default: return .gray
            }
        }
        return routeColor
    }

    private var legTimeRange: String {
        let depart = Date(timeIntervalSince1970: leg.startTime / 1000)
        let arrive = Date(timeIntervalSince1970: leg.endTime / 1000)
        let fmt = Self.timeFormatter
        return "\(fmt.string(from: depart)) - \(fmt.string(from: arrive))"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 1 { return "<1 min" }
        return "\(minutes) min"
    }
}
