import Foundation
import OrcaWatchCore

public struct ScreenState {
  public var navigation: NavigationState
  public var snapshot: ActivitySnapshot?
  public var status: String
  public var filtering: Bool
  public var paused: Bool
  public var refreshing: Bool
  public var demo: Bool
  public var interval: Double
  public var now: Date

  public init(
    navigation: NavigationState, snapshot: ActivitySnapshot?, status: String,
    filtering: Bool = false, paused: Bool = false, refreshing: Bool = false,
    demo: Bool = false, interval: Double = 5, now: Date = Date()
  ) {
    self.navigation = navigation
    self.snapshot = snapshot
    self.status = status
    self.filtering = filtering
    self.paused = paused
    self.refreshing = refreshing
    self.demo = demo
    self.interval = interval
    self.now = now
  }
}

public struct ScreenFrame {
  public var lines: [String]
  public var viewport: Int
  public var capacity: Int
}

public struct ActivityScreen {
  public var color: Bool
  private let ink = 252
  private let muted = 245
  private let edge = 240
  private let accent = 80
  private let cursor = 24

  public init(color: Bool = true) { self.color = color }

  public func render(
    _ state: ScreenState, width requestedWidth: Int, height requestedHeight: Int,
    viewport: Int = 0
  ) -> ScreenFrame {
    let width = max(1, requestedWidth)
    let height = max(1, requestedHeight)
    let layout = TableLayout(width: width)
    let navigation = state.navigation
    let selectedIndex = navigation.rows.firstIndex { $0.id == navigation.selectedID } ?? 0
    let capacity = max(1, height - (height < 10 ? 3 : 10))
    let start = min(max(0, min(viewport, selectedIndex)), max(0, navigation.rows.count - capacity))
    let offset = selectedIndex >= start + capacity ? selectedIndex - capacity + 1 : start
    let sessions = state.snapshot?.sessions ?? []
    let connected = state.snapshot != nil && !state.status.hasPrefix("STALE")
    let mode =
      state.paused
      ? "PAUSED" : state.status.hasPrefix("STALE") ? "STALE" : connected ? "LIVE" : "CONNECTING"
    let modeColor = state.paused ? 221 : connected ? accent : 203
    let environment = state.demo ? "DEMO" : "LOCAL"
    var lines = [
      bar(
        " ORCA WATCH  /  AGENTS", right: "\(mode)  \(environment) ", width: width,
        foreground: accent, background: 235, bold: true)
    ]
    let projects = Set(sessions.map(\.projectID)).count
    let working = sessions.filter { $0.state == "working" }.count
    let waiting = sessions.filter { ["waiting", "approval", "blocked"].contains($0.state) }.count
    let summary =
      " \(sessions.count) sessions  /  \(projects) projects  ·  \(working) working  ·  \(waiting) waiting"
    let freshness =
      state.snapshot.map { DisplayText.age($0.capturedAt, now: state.now) } ?? "unknown"
    let sync = state.refreshing ? "syncing" : "sync \(freshness)"
    lines.append(
      bar(
        summary, right: "\(sync)  ·  \(interval(state.interval))s ", width: width,
        foreground: muted))
    let view = navigation.grouped ? "grouped" : "flat"
    let filter = navigation.filter.isEmpty ? "" : "  /\(navigation.filter)"
    let order = navigation.grouped ? "projects A–Z · sessions newest first" : "newest first"
    lines.append(
      rule(" sessions\(filter) ", right: " \(view) · \(order) ", width: width, top: true))
    lines.append(tableHeader(layout))
    lines.append(divider(width: width))
    for position in 0..<capacity {
      let index = offset + position
      if index < navigation.rows.count {
        lines.append(
          tableRow(navigation.rows[index], navigation: navigation, layout: layout, now: state.now))
      } else if navigation.rows.isEmpty && position == min(2, capacity - 1) {
        let message =
          state.status.hasPrefix("STALE")
          ? "Live inventory unavailable. Retrying…"
          : state.snapshot == nil
            ? "Connecting to Orca Bridge…"
            : !navigation.filter.isEmpty
              ? "No matching sessions. Esc clears the filter." : "No open agent sessions."
        lines.append(
          bordered(TerminalText.fit("  \(message)", width: max(0, width - 2)), foreground: muted))
      } else {
        lines.append(bordered(String(repeating: " ", count: max(0, width - 2))))
      }
    }
    let range =
      navigation.rows.isEmpty
      ? "0 / 0"
      : "\(offset + 1)-\(min(offset + capacity, navigation.rows.count)) / \(navigation.rows.count)"
    lines.append(
      rule(
        " \(range) ", right: " cursor \(navigation.rows.isEmpty ? 0 : selectedIndex + 1) ",
        width: width, top: false))
    let selected = navigation.rows.first { $0.id == navigation.selectedID }?.session
    let detail =
      selected.map {
        " \($0.project) / \($0.branch ?? "branch unknown")  ·  \($0.model ?? "model unknown")  ·  \($0.id)"
      } ?? " Project selected  ·  h/l collapse or expand  ·  j/k move"
    lines.append(paint(TerminalText.fit(detail, width: width), foreground: muted, background: 235))
    let status = state.filtering ? " /\(navigation.filter)" : " \(state.status)"
    lines.append(bar(status, right: " \(mode) ", width: width, foreground: modeColor))
    lines.append(
      hints(
        [
          ("j/k", "move"), ("h/l", "fold"), ("space", "toggle"), ("g/G", "ends"), ("^u/^d", "page"),
        ], width: width))
    lines.append(
      hints(
        [
          ("enter", "focus"), ("/", "filter"), ("f", "\(view == "flat" ? "group" : "flat")"),
          ("p", state.paused ? "resume" : "pause"), ("r", "reload"), ("q", "quit"),
        ], width: width))
    if height < 10 {
      let compact =
        [lines[0], lines[3]] + Array(lines.dropFirst(5).prefix(max(0, height - 3)))
        + [hints([("j/k", "move"), ("enter", "focus"), ("q", "quit")], width: width)]
      return ScreenFrame(
        lines: Array(compact.prefix(height)).map { clippedLine($0, width: width) },
        viewport: offset, capacity: capacity)
    }
    return ScreenFrame(
      lines: Array(lines.prefix(height)).map { clippedLine($0, width: width) }, viewport: offset,
      capacity: capacity)
  }

  private func tableHeader(_ layout: TableLayout) -> String {
    let cells = layout.columns.map {
      paint(
        TerminalText.fit($0.field.rawValue, width: $0.width, right: $0.field == .age),
        foreground: $0.field == .age ? accent : 250, background: 235, bold: true)
    }
    return paint("│", foreground: edge) + paint("   ", foreground: muted, background: 235)
      + cells.joined(separator: paint(" │ ", foreground: edge, background: 235))
      + paint("│", foreground: edge)
  }

  private func tableRow(
    _ row: ActivityRow, navigation: NavigationState, layout: TableLayout, now: Date
  ) -> String {
    let selected = row.id == navigation.selectedID
    let projectColors = [80, 111, 183, 215, 211, 150]
    let projectColor = projectColors[ProjectColor.index(for: row.projectID)]
    let background: Int? = selected ? cursor : row.session == nil ? 235 : nil
    let foreground = selected ? 255 : ink
    let gutter =
      paint("▎", foreground: projectColor, background: background)
      + paint(
        selected ? "› " : "  ", foreground: foreground, background: background, bold: selected)
    let cells = layout.columns.map { column -> String in
      let text: String
      var cellColor = foreground
      if let session = row.session {
        switch column.field {
        case .session: text = "\(navigation.grouped ? "  " : "")\(session.title)"
        case .state:
          text = "\(stateSymbol(session.state)) \(session.state)"
          cellColor = statusColor(session.state)
        case .agent:
          text = session.agent
          cellColor = session.agent == "codex" ? 111 : 183
        case .project:
          text = session.project
          cellColor = projectColor
        case .branch:
          text = session.branch ?? "unknown"
          cellColor = selected ? 252 : muted
        case .model:
          text = session.model ?? "unknown"
          cellColor = selected ? 252 : muted
        case .age:
          text = DisplayText.age(session.activityAt, now: now)
          cellColor = session.activityAt == nil ? muted : 250
        }
      } else {
        switch column.field {
        case .session:
          text = "\(navigation.collapsed.contains(row.projectID) ? "▸" : "▾") \(row.project)"
        case .state: text = "project"
        case .agent: text = "\(row.count) total"
        default: text = ""
        }
        cellColor = projectColor
      }
      return paint(
        TerminalText.fit(text, width: column.width, right: column.field == .age),
        foreground: cellColor, background: background, bold: selected || row.session == nil)
    }
    return paint("│", foreground: edge) + gutter
      + cells.joined(
        separator: paint(" │ ", foreground: selected ? 67 : edge, background: background))
      + paint("│", foreground: edge)
  }

  private func stateSymbol(_ state: String) -> String {
    switch state {
    case "working": return "●"
    case "waiting", "approval", "blocked": return "◆"
    case "done", "idle": return "○"
    case "error", "failed": return "!"
    default: return "?"
    }
  }

  private func statusColor(_ state: String) -> Int {
    switch state {
    case "working": return 114
    case "waiting", "approval", "blocked": return 221
    case "error", "failed": return 203
    default: return muted
    }
  }

  private func paint(_ value: String, foreground: Int, background: Int? = nil, bold: Bool = false)
    -> String
  {
    guard color else { return value }
    return
      "\u{1B}[\(bold ? "1;" : "")38;5;\(foreground)\(background.map { ";48;5;\($0)" } ?? "")m\(value)\u{1B}[0m"
  }

  private func bar(
    _ left: String, right: String, width: Int, foreground: Int, background: Int? = nil,
    bold: Bool = false
  ) -> String {
    let rightWidth = min(TerminalText.cells(right), max(0, width / 2))
    let text =
      TerminalText.fit(left, width: width - rightWidth)
      + TerminalText.fit(right, width: rightWidth, right: true)
    return paint(text, foreground: foreground, background: background, bold: bold)
  }

  private func rule(_ left: String, right: String, width: Int, top: Bool) -> String {
    let inner = max(0, width - 2)
    let leftWidth = min(TerminalText.cells(left), inner)
    let rightWidth = min(TerminalText.cells(right), max(0, inner - leftWidth))
    let middle = String(repeating: "─", count: max(0, inner - leftWidth - rightWidth))
    return paint(top ? "┌" : "└", foreground: edge)
      + paint(TerminalText.fit(left, width: leftWidth), foreground: accent)
      + paint(middle, foreground: edge)
      + paint(TerminalText.fit(right, width: rightWidth), foreground: muted)
      + paint(top ? "┐" : "┘", foreground: edge)
  }

  private func divider(width: Int) -> String {
    paint("├" + String(repeating: "─", count: max(0, width - 2)) + "┤", foreground: edge)
  }

  private func bordered(_ value: String, foreground: Int? = nil) -> String {
    paint("│", foreground: edge) + paint(value, foreground: foreground ?? ink)
      + paint("│", foreground: edge)
  }

  private func hints(_ values: [(String, String)], width: Int) -> String {
    var used = 1
    var result = paint(" ", foreground: muted)
    for (key, action) in values {
      let length = TerminalText.cells(key + " " + action + "   ")
      guard used + length <= width else { break }
      result +=
        paint(key, foreground: 252, bold: true) + paint(" " + action + "   ", foreground: muted)
      used += length
    }
    return result + String(repeating: " ", count: max(0, width - used))
  }

  private func clippedLine(_ line: String, width: Int) -> String {
    guard width < 8 else { return line }
    let plain = line.replacingOccurrences(
      of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    return TerminalText.fit(plain, width: width)
  }

  private func interval(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
  }
}
