import Foundation

public enum SnapshotStore {
  public static func encode(_ snapshot: ActivitySnapshot) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(snapshot)
  }

  public static func read(from url: URL) throws -> ActivitySnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(ActivitySnapshot.self, from: Data(contentsOf: url))
  }

  public static func write(_ snapshot: ActivitySnapshot, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try encode(snapshot).write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

public struct ActivityChanges {
  private var previous: [String: ActivitySession] = [:]
  public init() {}

  public mutating func consume(_ snapshot: ActivitySnapshot) -> [ActivityEvent] {
    let current = Dictionary(
      snapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var events = snapshot.sessions.compactMap { session -> ActivityEvent? in
      guard previous[session.id] != session else { return nil }
      return ActivityEvent(
        kind: previous[session.id] == nil ? "opened" : "activity", observedAt: snapshot.capturedAt,
        session: session)
    }
    events += previous.values.filter { current[$0.id] == nil }.sorted(
      by: ActivitySession.newestFirst
    ).map {
      ActivityEvent(kind: "removed", observedAt: snapshot.capturedAt, session: $0)
    }
    previous = current
    return events
  }
}

public struct ActivityEvent: Encodable {
  public var kind: String
  public var observedAt: Date
  public var session: ActivitySession
}
