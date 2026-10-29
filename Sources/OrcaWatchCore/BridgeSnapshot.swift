import Foundation

public struct Resource<T: Decodable>: Decodable {
  public var available: Bool
  public var data: T?
  public var error: String?
}

public struct BridgeSnapshot: Decodable {
  public var schemaVersion: Int
  public var capturedAt: Date
  public var historyTruncated: Bool
  public var runtime: Resource<RuntimeInfo>
  public var sessions: Resource<[BridgeSession]>
  public var projects: Resource<[BridgeProject]>
  public var repositories: Resource<[BridgeRepository]>
  public var terminals: Resource<[BridgeTerminal]>
  public var tabs: Resource<[BridgeTab]>

  public static func decode(_ data: Data) throws -> Self {
    let decoder = JSONDecoder()
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let whole = ISO8601DateFormatter()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      guard let date = fractional.date(from: value) ?? whole.date(from: value) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "Invalid Bridge date"))
      }
      return date
    }
    let result = try decoder.decode(Self.self, from: data)
    guard result.schemaVersion == 1 else {
      throw BridgeError.unsupportedSchema(result.schemaVersion)
    }
    return result
  }

  public var liveAvailable: Bool {
    runtime.available && runtime.data != nil && terminals.available && terminals.data != nil
      && tabs.available && tabs.data != nil && sessions.available && sessions.data != nil
  }
}

public struct RuntimeInfo: Decodable {
  public var runtimeId: String
}

public struct BridgeSession: Decodable {
  public var id: String
  public var title: String
  public var agent: String
  public var model: String?
  public var cwd: String?
  public var branch: String?
  public var updatedAt: Date?
  public var liveState: String
  public var liveBindings: [LiveBinding]
  public var workspaceContexts: [WorkspaceContext]
}

public struct LiveBinding: Decodable {
  public var terminal: String
  public var incarnationId: String
  public var runtimeId: String
}

public struct WorkspaceContext: Decodable {
  public var projectId: String?
  public var projectName: String?
  public var repositoryId: String?
  public var repositoryName: String?
  public var folder: String?
}

public struct BridgeProject: Decodable {
  public var id: String
  public var displayName: String
  public var sourceRepoIds: [String]?
}

public struct BridgeRepository: Decodable {
  public var id: String
  public var displayName: String
  public var path: String
}

public struct BridgeTerminal: Decodable {
  public var handle: String
  public var incarnationId: String
  public var worktreeId: String
  public var agentIdentity: String?
  public var connected: Bool
  public var orphaned: Bool?
}

public struct BridgeTab: Decodable {
  public var id: String
  public var title: String?
  public var terminal: String?
  public var incarnationId: String?
  public var worktreeId: String
  public var agentStatus: AgentStatus?
}

public struct AgentStatus: Decodable {
  public var state: String?
  public var agentType: String?
  public var updatedAt: Double?
  public var stateObservedAt: Double?
  public var stateStartedAt: Double?

  public var activityAt: Date? {
    [updatedAt, stateObservedAt, stateStartedAt].compactMap { $0 }
      .filter { $0.isFinite && $0 > 0 }.max().map { Date(timeIntervalSince1970: $0 / 1000) }
  }
}
