import WidgetKit
import SwiftUI

struct LockScreenProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenEntry) -> Void) {
        completion(LockScreenEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockScreenEntry>) -> Void) {
        let timeline = Timeline(entries: [LockScreenEntry(date: .now)], policy: .never)
        completion(timeline)
    }
}

struct LockScreenEntry: TimelineEntry {
    let date: Date
}

struct LockScreenWidget: Widget {
    let kind: String = "LockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenProvider()) { _ in
            ZStack {
                Image(systemName: "figure.walk")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SafeWalk")
        .description("Quick access to SafeWalk.")
        .supportedFamilies([.accessoryCircular])
    }
}
