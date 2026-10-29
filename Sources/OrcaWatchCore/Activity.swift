import Foundation

public struct ActivitySession: Codable, Equatable, Identifiable {
  public var id: String
  public var bridgeID: String?
  public var terminal: String
  public var incarnation: String
  public var projectID: String
  public var project: String
  public var title: String
  public var agent: String
  public var model: String?
  public var branch: String?
  public var state: String
  public var activityAt: Date?

  public init(
    id: String, bridgeID: String? = nil, terminal: String = "", incarnation: String = "",
    projectID: String, project: String,
    title: String, agent: String = "unknown", model: String? = nil, branch: String? = nil,
    state: String = "unknown", activityAt: Date? = nil
  ) {
    self.id = id
    self.bridgeID = bridgeID
    self.terminal = terminal
    self.incarnation = incarnation
    self.projectID = projectID
    self.project = project
    self.title = title
    self.agent = agent
    self.model = model
    self.branch = branch
    self.state = state
    self.activityAt = activityAt
  }

  public static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.activityAt != rhs.activityAt {
      return (lhs.activityAt ?? .distantPast) > (rhs.activityAt ?? .distantPast)
    }
    return lhs.id < rhs.id
  }
}

public struct ActivitySnapshot: Codable, Equatable {
  public var capturedAt: Date
  public var sessions: [ActivitySession]
  public var warning: String?

  public init(capturedAt: Date = Date(), sessions: [ActivitySession], warning: String? = nil) {
    self.capturedAt = capturedAt
    self.sessions = sessions.sorted(by: ActivitySession.newestFirst)
    self.warning = warning
  }

  public func isStale(at now: Date = Date()) -> Bool { now.timeIntervalSince(capturedAt) > 30 }

  public static func project(_ snapshot: BridgeSnapshot) throws -> Self {
    guard snapshot.liveAvailable else { throw BridgeError.unavailable }
    let terminals = snapshot.terminals.data ?? []
    let tabs = snapshot.tabs.data ?? []
    var rows: [ActivitySession] = []
    var usedTerminals = Set<String>()
    for session in snapshot.sessions.data ?? [] where session.liveState == "live" {
      let bindings = session.liveBindings.filter { binding in
        binding.runtimeId == snapshot.runtime.data?.runtimeId
          && terminals.contains {
            $0.handle == binding.terminal && $0.incarnationId == binding.incarnationId
              && $0.connected && $0.orphaned != true
          }
      }
      guard let binding = bindings.sorted(by: { $0.terminal < $1.terminal }).first else { continue }
      let statuses = tabs.filter { tab in
        bindings.contains { $0.terminal == tab.terminal && $0.incarnationId == tab.incarnationId }
      }.compactMap(\.agentStatus)
      let status = statuses.max {
        ($0.activityAt ?? .distantPast) < ($1.activityAt ?? .distantPast)
      }
      let context = session.workspaceContexts.first
      let folder = session.cwd ?? "Unknown project"
      let projectID = context?.projectId ?? context?.repositoryId ?? "folder:\(folder)"
      let project =
        context?.projectName ?? context?.repositoryName
        ?? URL(fileURLWithPath: folder).lastPathComponent
      let activity = [session.updatedAt, status?.activityAt].compactMap { $0 }.max()
      rows.append(
        .init(
          id: session.id, bridgeID: session.id, terminal: binding.terminal,
          incarnation: binding.incarnationId,
          projectID: projectID, project: project, title: session.title,
          agent: session.agent, model: session.model, branch: session.branch,
          state: status?.state ?? "unknown", activityAt: activity))
      usedTerminals.formUnion(bindings.map(\.terminal))
    }
    for terminal in terminals
    where terminal.connected && terminal.orphaned != true
      && !usedTerminals.contains(terminal.handle)
    {
      let tab = tabs.first {
        $0.terminal == terminal.handle && $0.incarnationId == terminal.incarnationId
      }
      guard let agent = tab?.agentStatus?.agentType ?? terminal.agentIdentity, !agent.isEmpty else {
        continue
      }
      let repo = (snapshot.repositories.data ?? []).first {
        terminal.worktreeId.hasPrefix($0.id + "::")
      }
      let project = (snapshot.projects.data ?? []).first {
        $0.sourceRepoIds?.contains(repo?.id ?? "") == true
      }
      rows.append(
        .init(
          id: "terminal:\(terminal.incarnationId):\(terminal.handle)", terminal: terminal.handle,
          incarnation: terminal.incarnationId,
          projectID: project?.id ?? repo?.id ?? terminal.worktreeId,
          project: project?.displayName ?? repo?.displayName ?? "Unassigned",
          title: tab?.title ?? "Unindexed agent", agent: agent,
          state: tab?.agentStatus?.state ?? "unknown", activityAt: tab?.agentStatus?.activityAt))
    }
    return Self(
      capturedAt: snapshot.capturedAt, sessions: rows,
      warning: snapshot.historyTruncated
        ? "History capped at 2000; unindexed open agents shown separately" : nil)
  }
}

public enum ProjectColor {
  public static let hex = ["59D8C6", "88BFFF", "C5A0FF", "F3B675", "F18FAF", "BDD980"]

  public static func index(for id: String) -> Int {
    let hash = id.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
      ($0 ^ UInt64($1)) &* 1_099_511_628_211
    }
    return Int(hash % UInt64(hex.count))
  }
}

public enum DisplayText {
  public static func clean(_ text: String) -> String {
    String(
      text.unicodeScalars.filter {
        !CharacterSet.controlCharacters.contains($0) && $0.value != 0x7F
      })
  }

  public static func age(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "unknown" }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86400)d"
  }
}
