import Foundation

public enum Demo {
  public static func snapshot(now: Date = Date()) -> ActivitySnapshot {
    .init(
      capturedAt: now,
      sessions: [
        .init(
          id: "demo:reef:1", projectID: "reef", project: "Reef",
          title: "Refine the workspace navigator",
          agent: "codex", model: "GPT-6.1 Sol", branch: "joel/workspace", state: "working",
          activityAt: now.addingTimeInterval(-4)),
        .init(
          id: "demo:sonar:1", projectID: "sonar", project: "Sonar",
          title: "Review the activity pipeline",
          agent: "claude", branch: "joel/activity", state: "waiting",
          activityAt: now.addingTimeInterval(-18)),
        .init(
          id: "demo:reef:2", projectID: "reef", project: "Reef",
          title: "Run the navigation acceptance checks",
          agent: "codex", branch: "main", state: "done", activityAt: now.addingTimeInterval(-43)),
        .init(
          id: "demo:harbor:1", projectID: "harbor", project: "Harbor",
          title: "Build the desktop widget",
          agent: "codex", branch: "joel/widget", state: "working",
          activityAt: now.addingTimeInterval(-72)),
        .init(
          id: "demo:sonar:2", projectID: "sonar", project: "Sonar",
          title: "Trace reconnect behavior",
          agent: "claude", state: "unknown", activityAt: nil),
      ])
  }
}
