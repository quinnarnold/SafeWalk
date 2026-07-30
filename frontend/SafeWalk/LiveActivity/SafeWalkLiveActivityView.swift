import ActivityKit
import SwiftUI
import WidgetKit

struct SafeWalkLiveActivityView: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SafeWalkNavigationAttributes.self) { context in
            LockScreenNavigationView(context: context)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.nextManeuverIcon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDistance(context.state.distanceRemainingMeters))
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(context.state.estimatedArrival, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.currentStepName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(formatDistance(context.state.distanceToNextManeuverMeters))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.fractionComplete)
                        .tint(routeColor(for: context.attributes.routeType))
                }
            } compactLeading: {
                Image(systemName: context.state.nextManeuverIcon)
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(formatDistance(context.state.distanceToNextManeuverMeters))
                    .font(.caption2)
                    .fontWeight(.medium)
            } minimal: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct LockScreenNavigationView: View {
    let context: ActivityViewContext<SafeWalkNavigationAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: context.state.nextManeuverIcon)
                    .font(.title)
                    .foregroundStyle(.blue)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.currentStepName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("in " + formatDistance(context.state.distanceToNextManeuverMeters))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ProgressView(value: context.state.fractionComplete)
                .tint(routeColor(for: context.attributes.routeType))

            HStack {
                Label(formatDistance(context.state.distanceRemainingMeters), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Label {
                    Text(context.state.estimatedArrival, style: .time)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text(context.attributes.destinationName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
    }
}

private func formatDistance(_ meters: Double) -> String {
    let feet = meters * 3.28084
    if feet < 1000 {
        return "\(Int(feet)) ft"
    }
    let miles = meters / 1609.344
    return String(format: "%.1f mi", miles)
}

private func routeColor(for routeType: String) -> Color {
    switch routeType {
    case "moderate": return .blue
    case "safest": return .orange
    case "shortest": return .red
    default: return .blue
    }
}
