import AppKit
import Foundation
import OrcaWatchCore

enum WidgetControl {
  static let bundleID = "com.joelthecoder.orca-watch"

  static func run(_ arguments: [String]) throws {
    let command = arguments.first ?? "status"
    guard ["start", "stop", "status"].contains(command), arguments.count <= 2,
      arguments.count < 2 || arguments[1] == "--json"
    else {
      throw CLIError.message("Use orca-watch widget start|stop|status [--json].")
    }
    let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    if command == "stop" {
      for application in applications {
        guard application.terminate() else {
          throw CLIError.message("Could not stop the widget collector.")
        }
      }
      let deadline = Date().addingTimeInterval(3)
      while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
      }
      guard !applications.contains(where: { !$0.isTerminated }) else {
        throw CLIError.message("Widget collector has not stopped yet.")
      }
    }
    let appURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Applications/Orca Watch.app")
    if command == "start" && applications.isEmpty {
      guard FileManager.default.fileExists(atPath: appURL.path) else {
        throw CLIError.message(
          "Widget helper is not installed. Run make install-widget TEAM_ID=YOUR_TEAM_ID in the source checkout."
        )
      }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-gj", appURL.path]
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw CLIError.message("Could not start the widget collector.")
      }
      let deadline = Date().addingTimeInterval(3)
      while NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        && Date() < deadline
      {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
      }
      guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
        throw CLIError.message("Widget collector did not start.")
      }
    }
    let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    let bundle = Bundle(url: appURL)
    let group = bundle?.object(forInfoDictionaryKey: "OrcaWatchAppGroup") as? String
    let cache = group.flatMap {
      try? SnapshotStore.read(
        from: FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent("Library/Group Containers/\($0)/activity.json"))
    }
    let status = WidgetStatus(
      running: running, lastObservedAt: cache?.capturedAt,
      sessionCount: cache?.sessions.count, stale: cache?.isStale() ?? true)
    if arguments.contains("--json") {
      try emit(status)
    } else {
      print("Widget collector: \(running ? "running in background" : "stopped")")
      print(
        "Snapshot: \(cache.map { "\($0.sessions.count) sessions, observed \(DisplayText.age($0.capturedAt)) ago" } ?? "not collected yet")"
      )
      if status.stale { print("Widget snapshot is stale.") }
    }
  }
}

struct WidgetStatus: Encodable {
  var running: Bool
  var lastObservedAt: Date?
  var sessionCount: Int?
  var stale: Bool
}
