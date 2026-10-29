import Foundation
import OrcaWatchCore
import WidgetKit

@MainActor
final class Collector {
  private var task: Task<Void, Never>?
  private var lastReload = Date.distantPast
  private var client: BridgeClient?

  func start() {
    guard task == nil else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        await self?.refresh()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  func stop() {
    task?.cancel()
    client?.cancel()
    task = nil
  }

  func focus(id: String) async {
    do {
      let client = try makeClient()
      try await Task.detached(priority: .userInitiated) {
        defer { client.cancel() }
        let fresh = try client.snapshot()
        guard let session = fresh.sessions.first(where: { $0.id == id }) else {
          throw BridgeError.unavailable
        }
        try client.focus(session)
      }.value
    } catch { report(error) }
  }

  private func refresh() async {
    do {
      let request = try makeClient()
      client = request
      let snapshot = try await Task.detached(priority: .utility) {
        defer { request.cancel() }
        return try request.snapshot()
      }.value
      guard !Task.isCancelled else { return }
      try SnapshotStore.write(snapshot, to: WidgetCache.url())
      if Date().timeIntervalSince(lastReload) >= 15 {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetCache.kind)
        lastReload = Date()
      }
    } catch {
      if !Task.isCancelled { report(error) }
    }
  }

  private func makeClient() throws -> BridgeClient {
    let configured = UserDefaults.standard.string(forKey: "bridgePath")
    return try BridgeClient(path: configured?.isEmpty == false ? configured : nil)
  }

  private func report(_ error: Error) {
    FileHandle.standardError.write(
      Data("Orca Watch widget: \(DisplayText.clean(error.localizedDescription))\n".utf8))
  }
}
