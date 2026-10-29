import Darwin
import Foundation
import OrcaWatchCore

enum CLIError: Error, LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let value) = self { return value }
    return nil
  }
}

struct Options {
  var command = "watch"
  var interval = 2.0
  var bridge: String?
  var demo = false
  var once = false
  var json = false
  var color = ProcessInfo.processInfo.environment["NO_COLOR"] == nil

  init(_ arguments: [String]) throws {
    var index = 0
    while index < arguments.count {
      let value = arguments[index]
      switch value {
      case "watch", "snapshot", "log": command = value
      case "--demo": demo = true
      case "--once": once = true
      case "--json": json = true
      case "--no-color": color = false
      case "--bridge", "--interval":
        index += 1
        guard index < arguments.count else { throw CLIError.message("Missing value for \(value)") }
        if value == "--bridge" {
          bridge = arguments[index]
        } else {
          guard let seconds = Double(arguments[index]), seconds.isFinite, seconds >= 0.5,
            seconds <= 3600
          else {
            throw CLIError.message("Interval must be 0.5...3600 seconds.")
          }
          interval = seconds
        }
      default: throw CLIError.message("Unknown argument: \(value). Use --help.")
      }
      index += 1
    }
    if json && command == "watch" { command = "snapshot" }
  }
}

final class RefreshMailbox {
  private let lock = NSLock()
  private var result: Result<ActivitySnapshot, Error>?
  func put(_ value: Result<ActivitySnapshot, Error>) {
    lock.lock()
    result = value
    lock.unlock()
  }
  func take() -> Result<ActivitySnapshot, Error>? {
    lock.lock()
    defer { lock.unlock() }
    let value = result
    result = nil
    return value
  }
}

var interrupted = false
signal(SIGINT) { _ in interrupted = true }
signal(SIGTERM) { _ in interrupted = true }
signal(SIGPIPE, SIG_IGN)

func emit<T: Encodable>(_ value: T) throws {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.sortedKeys]
  do { try FileHandle.standardOutput.write(contentsOf: encoder.encode(value) + Data([10])) } catch {
    if errno == EPIPE { exit(0) }
    throw error
  }
}

func run(_ options: Options) throws {
  let client = options.demo ? nil : try BridgeClient(path: options.bridge)
  let pending = DispatchGroup()
  defer {
    client?.cancel()
    _ = pending.wait(timeout: .now() + 1)
  }
  let load: () throws -> ActivitySnapshot = { try client?.snapshot() ?? Demo.snapshot() }
  if options.command == "snapshot" {
    try emit(load())
    return
  }
  if options.command == "log" {
    var changes = ActivityChanges()
    repeat {
      do {
        let snapshot = try load()
        for event in changes.consume(snapshot) {
          if options.json {
            try emit(event)
          } else {
            let text =
              "\(event.kind.uppercased())  \(event.session.project) / \(event.session.title)  [\(event.session.state)]"
            print(DisplayText.clean(text))
            fflush(stdout)
          }
        }
      } catch {
        FileHandle.standardError.write(
          Data("orca-watch: \(DisplayText.clean(error.localizedDescription))\n".utf8))
        if options.once { throw error }
      }
      if options.once { return }
      let until = Date().addingTimeInterval(options.interval)
      while !interrupted && Date() < until { usleep(50000) }
    } while !interrupted
    return
  }
  let terminal = try Terminal(color: options.color)
  defer { terminal.restore() }
  var navigation = NavigationState()
  var snapshot: ActivitySnapshot?
  var status = "Connecting to Orca Bridge..."
  var filtering = false
  var paused = false
  var nextRefresh = Date.distantPast
  var refreshing = false
  var viewport = 0
  var previousSize = (0, 0)
  let mailbox = RefreshMailbox()
  while !interrupted {
    if let result = mailbox.take() {
      refreshing = false
      switch result {
      case .success(let value):
        snapshot = value
        navigation.update(value.sessions)
        status = value.warning ?? "Bridge connected"
      case .failure(let error): status = "STALE / \(error.localizedDescription)"
      }
    }
    if !refreshing && !paused && Date() >= nextRefresh {
      refreshing = true
      nextRefresh = Date().addingTimeInterval(options.interval)
      pending.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        defer { pending.leave() }
        mailbox.put(Result { try load() })
      }
    }
    let size = terminal.size
    if previousSize != (size.width, size.height) {
      terminal.invalidate()
      previousSize = (size.width, size.height)
    }
    let capacity = max(1, size.height - 9)
    let selectedIndex = navigation.rows.firstIndex { $0.id == navigation.selectedID } ?? 0
    if selectedIndex < viewport { viewport = selectedIndex }
    if selectedIndex >= viewport + capacity { viewport = selectedIndex - capacity + 1 }
    viewport = max(0, min(viewport, max(0, navigation.rows.count - capacity)))
    var lines = [
      terminal.style(
        terminal.fit(
          "  ◉ ORCA WATCH                                     \(options.demo ? "DEMO" : "LOCAL")",
          width: size.width - 1), "1;38;5;80"), "",
    ]
    let count = snapshot?.sessions.count ?? 0
    let freshness = snapshot.map { DisplayText.age($0.capturedAt) } ?? "unknown"
    lines += [
      terminal.style(
        terminal.fit(
          "  \(count) open agents  ·  newest activity first  ·  synced \(freshness) ago\(paused ? "  ·  PAUSED" : "")",
          width: size.width - 1), "2"), "",
    ]
    for index in viewport..<min(navigation.rows.count, viewport + capacity) {
      let row = navigation.rows[index]
      let selected = row.id == navigation.selectedID
      let prefix = selected ? "› " : "  "
      let text: String
      if let session = row.session {
        let indent = navigation.grouped ? "  " : "\(session.project) / "
        let age = DisplayText.age(session.activityAt)
        text = "\(prefix)\(indent)\(session.title)  ·  \(session.agent)  [\(session.state)]  \(age)"
      } else {
        text =
          "\(prefix)\(navigation.collapsed.contains(row.projectID) ? "▸" : "▾") \(row.project)  \(row.count)"
      }
      lines.append(
        terminal.projectStyle(
          terminal.fit(text, width: size.width - 1), id: row.projectID, selected: selected))
    }
    if navigation.rows.isEmpty {
      lines.append(
        terminal.fit(
          snapshot == nil ? "  Waiting for Bridge..." : "  No matching open agents",
          width: size.width - 1))
    }
    while lines.count < size.height - 5 { lines.append("") }
    let selected = navigation.rows.first { $0.id == navigation.selectedID }?.session
    let detail =
      selected.map {
        "  \($0.agent) · \($0.model ?? "model unknown") · \($0.branch ?? "branch unknown")"
      } ?? "  Select a session to inspect it"
    lines.append(terminal.style(terminal.fit(detail, width: size.width - 1), "2"))
    lines.append(
      terminal.fit(filtering ? "  /\(navigation.filter)" : "  \(status)", width: size.width - 1))
    lines.append("")
    lines.append(
      terminal.style(
        terminal.fit(
          "  j/k move  h/l fold  space toggle  g/G ends  f flat  / filter", width: size.width - 1),
        "2"))
    lines.append(
      terminal.style(
        terminal.fit(
          "  enter focus  p pause  r refresh  esc clear filter  q quit", width: size.width - 1), "2"
      ))
    terminal.paint(Array(lines.prefix(size.height)))
    for key in terminal.readKeys() {
      if key == .quit {
        interrupted = true
        break
      }
      if filtering {
        switch key {
        case .escape:
          filtering = false
          navigation.filter = ""
        case .enter: filtering = false
        case .backspace: if !navigation.filter.isEmpty { navigation.filter.removeLast() }
        case .character(let value): navigation.filter += value
        default: break
        }
        navigation.rebuild()
        continue
      }
      switch key {
      case .up, .character("k"): navigation.move(-1)
      case .down, .character("j"): navigation.move(1)
      case .left, .character("h"): navigation.toggleProject(expand: false)
      case .right, .character("l"): navigation.toggleProject(expand: true)
      case .character(" "): navigation.toggleProject()
      case .character("g"): navigation.move(-navigation.rows.count)
      case .character("G"): navigation.move(navigation.rows.count)
      case .character("f"):
        navigation.grouped.toggle()
        navigation.rebuild()
      case .character("/"): filtering = true
      case .character("p"): paused.toggle()
      case .character("r"): nextRefresh = .distantPast
      case .escape:
        navigation.filter = ""
        navigation.rebuild()
      case .character("q"): interrupted = true
      case .enter:
        if let selected, !options.demo {
          do {
            try client?.focus(selected)
            status = "Focused \(selected.title)"
          } catch { status = error.localizedDescription }
        } else {
          navigation.toggleProject()
        }
      default: break
      }
    }
  }
}

do {
  if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print(
      """
      Orca Watch: open Orca agents, ordered by recent activity.

      orca-watch [watch] [--interval SECONDS] [--bridge /path/to/orca-bridge]
      orca-watch snapshot [--json]
      orca-watch log [--json] [--once]
      orca-watch widget start|stop|status [--json]

      --demo       Use synthetic sessions without Orca Bridge
      --no-color   Disable terminal colors (also honors NO_COLOR)

      j/k or arrows move; h/l collapse/expand; space toggles a project.
      f toggles flat order; / filters; enter focuses; p pauses; q quits.
      Selection follows identity across reorder. The widget uses an invisible collector.
      """)
  } else if CommandLine.arguments.dropFirst().first == "widget" {
    try WidgetControl.run(Array(CommandLine.arguments.dropFirst(2)))
  } else {
    try run(Options(Array(CommandLine.arguments.dropFirst())))
  }
} catch {
  FileHandle.standardError.write(
    Data("orca-watch: \(DisplayText.clean(error.localizedDescription))\n".utf8))
  exit(1)
}
