import WidgetKit
import SwiftUI

struct QuickRouteProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRouteEntry {
        QuickRouteEntry(date: .now, locations: [], city: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRouteEntry) -> Void) {
        let locations = WidgetLocationProvider.loadLocations()
        let city = WidgetLocationProvider.currentCity()
        completion(QuickRouteEntry(date: .now, locations: locations, city: city))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRouteEntry>) -> Void) {
        let locations = WidgetLocationProvider.loadLocations()
        let city = WidgetLocationProvider.currentCity()
        let entry = QuickRouteEntry(date: .now, locations: locations, city: city)
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct QuickRouteEntry: TimelineEntry {
    let date: Date
    let locations: [WidgetLocation]
    let city: String
}

struct QuickRouteWidgetEntryView: View {
    var entry: QuickRouteEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(locations: entry.locations)
        case .systemMedium:
            MediumWidgetView(locations: entry.locations, city: entry.city)
        default:
            SmallWidgetView(locations: entry.locations)
        }
    }
}

struct SmallWidgetView: View {
    let locations: [WidgetLocation]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("SafeWalk")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            Spacer()

            if let location = locations.first {
                Link(destination: URL(string: "safewalk://route?to=\(location.id.uuidString)")!) {
                    HStack(spacing: 8) {
                        Image(systemName: location.icon)
                            .font(.body)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text("Route safely")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text("Save a location to get started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
        .widgetURL(URL(string: "safewalk://open"))
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MediumWidgetView: View {
    let locations: [WidgetLocation]
    let city: String

    var body: some View {
        if locations.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text("Save locations in SafeWalk to see them here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("SafeWalk")
                        .font(.caption)
                        .fontWeight(.semibold)
                    if !city.isEmpty {
                        Spacer()
                        Text(city)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(locations.prefix(3)) { location in
                        Link(destination: URL(string: "safewalk://route?to=\(location.id.uuidString)")!) {
                            VStack(spacing: 6) {
                                Image(systemName: location.icon)
                                    .font(.title3)
                                    .foregroundStyle(.blue)

                                Text(location.name)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(4)
            .widgetURL(URL(string: "safewalk://open"))
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct QuickRouteWidget: Widget {
    let kind: String = "QuickRouteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickRouteProvider()) { entry in
            QuickRouteWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Quick Route")
        .description("Route safely to your saved locations.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
