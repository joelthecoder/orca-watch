import Foundation

public struct ActivityRow: Equatable, Identifiable {
  public var id: String
  public var projectID: String
  public var project: String
  public var session: ActivitySession?
  public var count: Int
}

public struct NavigationState {
  public private(set) var selectedID: String?
  public private(set) var collapsed = Set<String>()
  public private(set) var rows: [ActivityRow] = []
  public var grouped = true
  public var filter = ""
  private var sessions: [ActivitySession] = []

  public init() {}

  public mutating func update(_ sessions: [ActivitySession]) {
    if let selected = self.sessions.first(where: { $0.id == selectedID }),
      !selected.terminal.isEmpty, !selected.incarnation.isEmpty,
      !sessions.contains(where: { $0.id == selectedID }),
      let replacement = sessions.first(where: {
        $0.terminal == selected.terminal && $0.incarnation == selected.incarnation
      })
    {
      selectedID = replacement.id
    }
    self.sessions = sessions
    rebuild()
  }

  public mutating func select(_ id: String) {
    if rows.contains(where: { $0.id == id }) { selectedID = id }
  }

  public mutating func move(_ delta: Int) {
    guard !rows.isEmpty else { return }
    let current = rows.firstIndex { $0.id == selectedID } ?? 0
    selectedID = rows[max(0, min(rows.count - 1, current + delta))].id
  }

  public mutating func toggleProject(expand: Bool? = nil) {
    guard grouped, let row = rows.first(where: { $0.id == selectedID }) else { return }
    let shouldExpand = expand ?? collapsed.contains(row.projectID)
    if shouldExpand {
      collapsed.remove(row.projectID)
    } else {
      collapsed.insert(row.projectID)
      selectedID = "project:\(row.projectID)"
    }
    rebuild()
  }

  public mutating func rebuild() {
    let visible = sessions.filter {
      filter.isEmpty
        || "\($0.project) \($0.title) \($0.agent) \($0.branch ?? "")"
          .localizedCaseInsensitiveContains(filter)
    }
    .sorted(by: ActivitySession.newestFirst)
    if grouped {
      let groups = Dictionary(grouping: visible, by: \.projectID)
      let projects = groups.values.compactMap(\.first).sorted {
        let order = $0.project.compare($1.project, options: [.caseInsensitive, .numeric])
        return order == .orderedSame ? $0.projectID < $1.projectID : order == .orderedAscending
      }
      rows = projects.flatMap { session -> [ActivityRow] in
        let children = groups[session.projectID] ?? []
        let parent = ActivityRow(
          id: "project:\(session.projectID)", projectID: session.projectID,
          project: session.project, session: nil, count: children.count)
        return [parent]
          + (collapsed.contains(session.projectID)
            ? []
            : children.map {
              ActivityRow(
                id: $0.id, projectID: $0.projectID, project: $0.project, session: $0, count: 0)
            })
      }
    } else {
      rows = visible.map {
        ActivityRow(id: $0.id, projectID: $0.projectID, project: $0.project, session: $0, count: 0)
      }
    }
    if !rows.contains(where: { $0.id == selectedID }) {
      selectedID = rows.first(where: { $0.session != nil })?.id ?? rows.first?.id
    }
  }
}
