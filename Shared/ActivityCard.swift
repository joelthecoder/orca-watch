import OrcaWatchCore
import SwiftUI

struct ActivityCard: View {
  let snapshot: ActivitySnapshot?
  var observedAt = Date()
  var limit = 3
  var compact = false

  private var stale: Bool { snapshot?.isStale(at: observedAt) ?? true }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 10 : 14) {
      HStack(spacing: 7) {
        Image(systemName: "dot.radiowaves.left.and.right")
          .foregroundStyle(Color.mint)
        Text("ORCA WATCH")
          .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
          .tracking(1.4)
        Spacer(minLength: 0)
        Circle().fill(stale ? Color.orange : Color.mint).frame(width: 5, height: 5)
      }
      if let snapshot, !snapshot.sessions.isEmpty {
        ForEach(Array(snapshot.sessions.prefix(limit))) { session in
          Link(destination: SessionLink.url(for: session.id)) {
            HStack(alignment: .top, spacing: 9) {
              RoundedRectangle(cornerRadius: 2)
                .fill(projectColor(session.projectID)).frame(width: 3)
              VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                  Text(session.project.uppercased()).font(.system(size: 9, weight: .bold))
                    .tracking(0.5).foregroundStyle(projectColor(session.projectID)).lineLimit(1)
                  Spacer(minLength: 1)
                  Text(DisplayText.age(session.activityAt, now: observedAt))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                Text(session.title).font(.system(size: compact ? 11 : 12, weight: .medium))
                  .foregroundStyle(.primary).lineLimit(1)
                if !compact {
                  Text("\(session.agent) · \(session.state)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
              }
            }
            .fixedSize(horizontal: false, vertical: true)
          }
          .buttonStyle(.plain)
        }
      } else {
        Spacer(minLength: 0)
        Text(snapshot == nil ? "Run orca-watch widget start" : "No open agents")
          .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack(spacing: 4) {
        Text(stale ? "LAST OBSERVED" : "RECENT ACTIVITY")
          .font(.system(size: 8, weight: .semibold)).tracking(0.7)
        Spacer(minLength: 0)
        if let date = snapshot?.capturedAt {
          Text(date, style: .relative).font(.system(size: 8, design: .monospaced))
        }
      }
      .foregroundStyle(.secondary)
    }
  }

  private func projectColor(_ id: String) -> Color {
    let value = UInt32(ProjectColor.hex[ProjectColor.index(for: id)], radix: 16) ?? 0x59D8C6
    return Color(
      red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
      blue: Double(value & 255) / 255)
  }
}
