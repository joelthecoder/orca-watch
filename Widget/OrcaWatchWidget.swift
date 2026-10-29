import OrcaWatchCore
import SwiftUI
import WidgetKit

struct ActivityEntry: TimelineEntry {
  let date: Date
  let snapshot: ActivitySnapshot?
}

struct ActivityProvider: TimelineProvider {
  func placeholder(in context: Context) -> ActivityEntry {
    .init(date: Date(), snapshot: Demo.snapshot())
  }

  func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
    let current = entry()
    let later = ActivityEntry(date: Date().addingTimeInterval(31), snapshot: current.snapshot)
    completion(Timeline(entries: [current, later], policy: .after(Date().addingTimeInterval(60))))
  }

  private func entry() -> ActivityEntry {
    let snapshot = try? SnapshotStore.read(from: WidgetCache.url())
    return ActivityEntry(date: Date(), snapshot: snapshot)
  }
}

struct ActivityWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ActivityEntry

  var body: some View {
    ActivityCard(
      snapshot: entry.snapshot, observedAt: entry.date,
      limit: family == .systemLarge ? 6 : 3,
      compact: family != .systemLarge
    )
    .containerBackground(for: .widget) { Color(red: 0.045, green: 0.09, blue: 0.12) }
    .environment(\.colorScheme, .dark)
  }
}

@main
struct OrcaWatchWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetCache.kind, provider: ActivityProvider()) {
      ActivityWidgetView(entry: $0)
    }
    .configurationDisplayName("Orca Watch")
    .description("Recent activity from open Orca agents.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
