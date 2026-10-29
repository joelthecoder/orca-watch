import Foundation
import OrcaWatchCore
import XCTest

@testable import OrcaWatchTerminal

final class ActivityScreenTests: XCTestCase {
  func testWideTableAlignsFieldsAndGivesRemainingSpaceToSession() {
    let state = makeState()
    let frame = ActivityScreen(color: false).render(state, width: 159, height: 24)
    let header = frame.lines[3]
    let session = frame.lines[6]
    for field in ["SESSION", "STATE", "AGENT", "PROJECT", "BRANCH", "MODEL", "AGE"] {
      XCTAssertTrue(header.contains(field), field)
    }
    let headerSeparators = header.enumerated().filter { $0.element == "│" }.map(\.offset)
    let rowSeparators = session.enumerated().filter { $0.element == "│" }.map(\.offset)
    XCTAssertEqual(headerSeparators, rowSeparators)
    XCTAssertTrue(session.contains("Refine the workspace navigator"))
    XCTAssertTrue(session.contains("GPT-6.1 Sol"))
    XCTAssertTrue(session.contains("joel/workspace"))
    XCTAssertTrue(session.contains("4s"))
    XCTAssertEqual(TableLayout(width: 159).columns.first?.width, 60)
  }

  func testNarrowTableDropsSecondaryColumnsBeforeClippingSession() {
    let wide = TableLayout(width: 159).columns.map(\.field)
    let medium = TableLayout(width: 109).columns.map(\.field)
    let narrow = TableLayout(width: 59).columns.map(\.field)
    XCTAssertEqual(wide, TableField.allCases)
    XCTAssertEqual(medium, [.session, .state, .agent, .project, .branch, .age])
    XCTAssertEqual(narrow, [.session, .state, .agent, .age])
    XCTAssertEqual(TableLayout(width: 20).columns.map(\.field), [.session])
  }

  func testEveryFrameFitsTerminalCellsAcrossSizesAndColorModes() {
    for width in [1, 7, 20, 39, 59, 79, 109, 159, 219] {
      for height in [6, 10, 24, 40] {
        for color in [false, true] {
          let frame = ActivityScreen(color: color).render(makeState(), width: width, height: height)
          XCTAssertEqual(frame.lines.count, height, "\(width)x\(height)")
          for line in frame.lines {
            XCTAssertEqual(
              TerminalText.cells(plain(line)), width, "\(width)x\(height): \(plain(line))")
          }
        }
      }
    }
  }

  func testSelectionStaysOnMovingSessionAndHasFullRowTreatment() {
    var state = makeState()
    state.navigation.select("demo:sonar:1")
    var snapshot = state.snapshot!
    snapshot.sessions[1].activityAt = now.addingTimeInterval(2)
    state.snapshot = snapshot
    state.navigation.update(snapshot.sessions)
    let frame = ActivityScreen().render(state, width: 159, height: 24)
    let selected = frame.lines.first {
      plain($0).contains("›") && plain($0).contains("Review the activity pipeline")
    }
    XCTAssertNotNil(selected)
    XCTAssertEqual(state.navigation.selectedID, "demo:sonar:1")
    XCTAssertEqual(TerminalText.cells(plain(selected!)), 159)
    XCTAssertTrue(selected!.contains("48;5;24m"))
    XCTAssertTrue(plain(selected!).contains("claude"))
  }

  func testViewportKeepsLastSelectedSessionVisibleAfterResize() {
    var state = makeState()
    let sessions = (0..<60).map {
      ActivitySession(
        id: "session-\($0)", projectID: "p", project: "P", title: "Session \($0)",
        activityAt: now.addingTimeInterval(Double(-$0)))
    }
    state.navigation.grouped = false
    state.navigation.update(sessions)
    state.navigation.select("session-59")
    let wide = ActivityScreen(color: false).render(state, width: 159, height: 40)
    let resized = ActivityScreen(color: false).render(
      state, width: 59, height: 12, viewport: wide.viewport)
    XCTAssertTrue(resized.lines.contains { $0.contains("›") && $0.contains("Session 59") })
    XCTAssertEqual(resized.viewport, 58)
  }

  func testUnknownEmptyFilteredPausedAndDisconnectedStates() {
    var state = makeState()
    state.paused = true
    XCTAssertTrue(
      ActivityScreen(color: false).render(state, width: 109, height: 24).lines[0].contains("PAUSED")
    )
    state.paused = false
    state.navigation.filter = "missing"
    state.navigation.rebuild()
    let filtered = ActivityScreen(color: false).render(state, width: 109, height: 24)
    XCTAssertTrue(filtered.lines.contains { $0.contains("No matching sessions") })
    state.snapshot = nil
    state.status = "STALE / offline"
    let offline = ActivityScreen(color: false).render(state, width: 109, height: 24)
    XCTAssertTrue(offline.lines[0].contains("STALE"))
    XCTAssertTrue(offline.lines.contains { $0.contains("Live inventory unavailable") })
    XCTAssertFalse(offline.lines.joined().contains("\u{1B}"))
  }

  func testUnicodeCellWidthsAndTruncationKeepClustersIntact() {
    XCTAssertEqual(TerminalText.cells("cafe\u{0301}"), 4)
    XCTAssertEqual(TerminalText.cells("\u{754C}"), 2)
    XCTAssertEqual(TerminalText.cells("\u{1F40B}"), 2)
    XCTAssertEqual(TerminalText.cells("\u{1F1E8}\u{1F1E6}"), 2)
    XCTAssertEqual(TerminalText.fit("\u{754C}abc", width: 4), "\u{754C}a…")
    XCTAssertEqual(TerminalText.fit("cafe\u{0301}123", width: 5), "cafe\u{0301}…")
    XCTAssertEqual(TerminalText.fit("5s", width: 7, right: true), "     5s")
  }

  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func makeState() -> ScreenState {
    let snapshot = Demo.snapshot(now: now)
    var navigation = NavigationState()
    navigation.update(snapshot.sessions)
    return ScreenState(
      navigation: navigation, snapshot: snapshot, status: "Bridge connected", demo: true, now: now)
  }

  private func plain(_ value: String) -> String {
    value.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
  }
}
