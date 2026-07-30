import SwiftUI
import CoreLocation

struct RouteHistoryView: View {
    @ObservedObject var viewModel: RouteViewModel
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationView {
            Group {
                if viewModel.routeHistory.isEmpty && viewModel.lifetimeStats.totalRoutes == 0 {
                    emptyStateView
                } else {
                    historyList
                }
            }
            .navigationTitle("Route History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.routeHistory.isEmpty {
                        Button("Clear Recent", role: .destructive) {
                            viewModel.clearRouteHistory()
                        }
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text("No Route History")
                .font(.headline)

            Text("Your completed routes will appear here so you can track your walking patterns and safety improvements.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var historyList: some View {
        List {
            Section {
                lifetimeStatisticsCard
            }

            if !viewModel.routeHistory.isEmpty {
                Section("Recent Routes (Last 10)") {
                    ForEach(viewModel.routeHistory) { entry in
                        historyRow(entry)
                    }
                    .onDelete { offsets in
                        offsets.forEach { index in
                            let entry = viewModel.routeHistory[index]
                            viewModel.deleteHistoryEntry(entry)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var lifetimeStatisticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lifetime Walking Stats")
                .font(.headline)

            HStack(spacing: 20) {
                statItem(
                    value: "\(viewModel.lifetimeStats.totalRoutes)",
                    label: "Routes",
                    icon: "map"
                )

                statItem(
                    value: formatDistance(viewModel.lifetimeStats.totalDistanceMeters),
                    label: "Total Distance",
                    icon: "figure.walk"
                )

                statItem(
                    value: formatRiskReduction(viewModel.lifetimeStats.averageRiskReduction),
                    label: "Avg Risk Reduced",
                    icon: "shield.checkered"
                )
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lifetime walking statistics: \(viewModel.lifetimeStats.totalRoutes) routes, \(formatDistance(viewModel.lifetimeStats.totalDistanceMeters)) total distance, \(formatRiskReduction(viewModel.lifetimeStats.averageRiskReduction)) average risk reduction")
    }

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            Text(value)
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func historyRow(_ entry: RouteHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let from = entry.sourceDisplayName, let to = entry.destDisplayName {
                        Text("\(from) \u{2192} \(to)")
                            .font(.headline)
                            .lineLimit(1)
                        Text(entry.city.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(entry.city.capitalized)
                            .font(.headline)
                    }
                }

                Spacer()

                routeTypeBadge(entry.routeType)
            }

            HStack(spacing: 16) {
                Label(formatDistance(entry.distance), systemImage: "ruler")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Label(formatTime(entry.time), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let reduction = entry.riskReduction, reduction > 0 {
                Label(String(format: "%.1f%% lower modeled risk", reduction), systemImage: "shield.checkered")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }

            HStack {
                Text(dateFormatter.string(from: entry.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                ShareLink(item: shareText(for: entry)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)

                if entry.routeGeometry != nil {
                    Button(action: {
                        viewRoute(entry)
                    }) {
                        Label("View", systemImage: "eye")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.city) \(routeDisplayName(entry.routeType)) route, \(formatDistance(entry.distance)), \(formatTime(entry.time))")
        .accessibilityHint("Use buttons to view saved route or recalculate")
    }

    private func routeDisplayName(_ type: String) -> String {
        switch type.lowercased() {
        case "moderate": return "Recommended"
        case "safest": return "Lower Risk"
        case "shortest": return "Fastest"
        default: return type.capitalized
        }
    }

    private func routeTypeBadge(_ type: String) -> some View {
        Text(routeDisplayName(type))
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(routeTypeColor(type).opacity(0.2))
            .foregroundColor(routeTypeColor(type))
            .clipShape(Capsule())
    }

    private func routeTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "moderate": return .blue
        case "safest": return .orange
        case "shortest": return .red
        default: return .gray
        }
    }

    private func reuseRoute(_ entry: RouteHistoryEntry) {
        viewModel.sourceCoord = entry.sourceCoordinate
        viewModel.destCoord = entry.destCoordinate
        viewModel.selectedCity = entry.city
        viewModel.playImpactFeedback()
        dismiss()
    }

    private func viewRoute(_ entry: RouteHistoryEntry) {
        viewModel.loadRouteFromHistory(entry)
        dismiss()
    }

    private func shareText(for entry: RouteHistoryEntry) -> String {
        var text = "Check out my SafeWalk route in \(entry.city)!\n\n"
        text += "Route Type: \(routeDisplayName(entry.routeType))\n"
        text += String(format: "Distance: %.2f mi\n", entry.distance / 1609.34)
        text += String(format: "Time: %.0f min\n", entry.time / 60)
        if let reduction = entry.riskReduction, reduction > 0 {
            text += String(format: "Risk Reduction: %.1f%%\n", reduction)
        }
        text += "\nCompare walking routes with SafeWalk."
        return text
    }

    private func formatDistance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        if miles < 0.1 {
            return String(format: "%.0f ft", meters * 3.281)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return String(format: "%.0f min", minutes)
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes.truncatingRemainder(dividingBy: 60)
            return String(format: "%.0fh %.0fm", hours, remainingMinutes)
        }
    }

    private func formatRiskReduction(_ value: Double?) -> String {
        guard let value = value else { return "N/A" }
        return String(format: "%.1f%%", value)
    }
}
