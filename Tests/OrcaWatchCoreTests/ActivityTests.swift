import XCTest

@testable import OrcaWatchCore

final class ActivityTests: XCTestCase {
  func testSessionDeepLinkPreservesUnicodeAndReservedCharactersAndRejectsAmbiguousRoutes() {
    let id = "local:codex:synthetic & / \u{00E9}"
    XCTAssertEqual(SessionLink.id(from: SessionLink.url(for: id)), id)
    for value in [
      "orcawatch://session", "orcawatch://session?id=", "orcawatch://session?id=a&id=b",
      "https://session?id=a", "orcawatch://other?id=a",
    ] {
      XCTAssertNil(SessionLink.id(from: URL(string: value)!))
    }
  }

  func testSelectionSurvivesIndexCatchup() {
    var navigation = NavigationState()
    let initial = ActivitySession(
      id: "terminal:inc:one", terminal: "one", incarnation: "inc", projectID: "p", project: "P",
      title: "Task")
    navigation.update([initial])
    navigation.select(initial.id)
    var indexed = initial
    indexed.id = "local:codex:one"
    indexed.bridgeID = indexed.id
    navigation.update([row("newer", time: 500), indexed])
    XCTAssertEqual(navigation.selectedID, indexed.id)
  }

  func testMissingResourceDataAndOrphanedTerminalsAreNotLive() throws {
    var fixture = snapshotJSON()
    fixture["tabs"] = ["available": true, "data": NSNull()]
    XCTAssertThrowsError(try ActivitySnapshot.project(decode(fixture)))
    fixture = snapshotJSON()
    var resource = fixture["terminals"] as! [String: Any]
    var terminals = resource["data"] as! [[String: Any]]
    terminals[0]["orphaned"] = true
    resource["data"] = terminals
    fixture["terminals"] = resource
    XCTAssertEqual(try ActivitySnapshot.project(decode(fixture)).sessions, [])
  }

  func testSelectionFollowsSessionWhenActivityReordersProjects() {
    var navigation = NavigationState()
    let old = row("a", project: "alpha", time: 10)
    let recent = row("b", project: "beta", time: 20)
    navigation.update([old, recent])
    navigation.select("a")
    navigation.update([row("a", project: "alpha", time: 30), recent])
    XCTAssertEqual(navigation.selectedID, "a")
    XCTAssertEqual(navigation.rows.map(\.id), ["project:alpha", "a", "project:beta", "b"])
    navigation.update([old, recent])
    XCTAssertEqual(navigation.selectedID, "a")
    XCTAssertEqual(navigation.rows.last?.id, "a")
  }

  func testCollapsePersistsThroughRefreshAndMovementRemainsBounded() {
    var navigation = NavigationState()
    let sessions = [row("a", project: "alpha", time: 10), row("b", project: "beta", time: 20)]
    navigation.update(sessions)
    navigation.select("a")
    navigation.toggleProject(expand: false)
    navigation.update(sessions.reversed())
    XCTAssertEqual(navigation.selectedID, "project:alpha")
    XCTAssertEqual(navigation.rows.map(\.id), ["project:beta", "b", "project:alpha"])
    navigation.move(100)
    XCTAssertEqual(navigation.selectedID, "project:alpha")
    navigation.toggleProject(expand: true)
    XCTAssertEqual(navigation.rows.last?.id, "a")
    navigation.move(-100)
    XCTAssertEqual(navigation.selectedID, "project:beta")
  }

  func testFlatModeAndFilterKeepIdentityUntilItIsNoLongerVisible() {
    var navigation = NavigationState()
    navigation.update([row("a", project: "alpha", time: 10), row("b", project: "beta", time: 20)])
    navigation.select("a")
    navigation.grouped = false
    navigation.rebuild()
    XCTAssertEqual(navigation.rows.map(\.id), ["b", "a"])
    XCTAssertEqual(navigation.selectedID, "a")
    navigation.filter = "BETA"
    navigation.rebuild()
    XCTAssertEqual(navigation.selectedID, "b")
    navigation.filter = "missing"
    navigation.rebuild()
    XCTAssertNil(navigation.selectedID)
  }

  func testProjectionRequiresRuntimeAndIncarnationProof() throws {
    var fixture = snapshotJSON()
    let bound = try ActivitySnapshot.project(decode(fixture))
    XCTAssertEqual(bound.sessions.map(\.id), ["local:codex:synthetic"])
    XCTAssertEqual(bound.sessions.first?.project, "Alpha")
    XCTAssertEqual(bound.sessions.first?.state, "working")
    XCTAssertEqual(bound.sessions.first?.activityAt, Date(timeIntervalSince1970: 200))

    var terminals = fixture["terminals"] as! [String: Any]
    var terminalRows = terminals["data"] as! [[String: Any]]
    terminalRows[0]["incarnationId"] = "new-incarnation"
    terminals["data"] = terminalRows
    fixture["terminals"] = terminals
    let mismatched = try ActivitySnapshot.project(decode(fixture))
    XCTAssertEqual(mismatched.sessions.count, 1)
    XCTAssertNil(mismatched.sessions.first?.bridgeID)
    XCTAssertEqual(mismatched.sessions.first?.state, "unknown")
    XCTAssertNil(mismatched.sessions.first?.activityAt)
  }

  func testUnknownLivenessNeverPromotesHistoryThroughFolderMatching() throws {
    var fixture = snapshotJSON()
    var sessions = fixture["sessions"] as! [String: Any]
    var rows = sessions["data"] as! [[String: Any]]
    rows[0]["liveState"] = "unknown"
    rows[0]["liveBindings"] = []
    sessions["data"] = rows
    fixture["sessions"] = sessions
    fixture["terminals"] = ["available": true, "data": []]
    let projection = try ActivitySnapshot.project(decode(fixture))
    XCTAssertEqual(projection.sessions, [])
  }

  func testOutageAndFutureSchemaFailExplicitly() throws {
    var fixture = snapshotJSON()
    fixture["runtime"] = ["available": false, "data": NSNull(), "error": "offline"]
    XCTAssertThrowsError(try ActivitySnapshot.project(decode(fixture)))
    fixture["schemaVersion"] = 2
    XCTAssertThrowsError(try decode(fixture))
  }

  func testTiesAndUnknownActivityHaveDeterministicOrder() {
    let snapshot = ActivitySnapshot(sessions: [
      row("b", time: 10), row("a", time: 10),
      .init(id: "c", projectID: "p", project: "P", title: "Unknown"),
    ])
    XCTAssertEqual(snapshot.sessions.map(\.id), ["a", "b", "c"])
    XCTAssertEqual(ProjectColor.index(for: "alpha"), ProjectColor.index(for: "alpha"))
    XCTAssertEqual(DisplayText.age(nil), "unknown")
    XCTAssertEqual(DisplayText.clean("title\u{1B}[2J\n"), "title[2J")
  }

  func testCacheRoundTripAndFreshness() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("snapshot.json")
    let snapshot = ActivitySnapshot(
      capturedAt: Date(timeIntervalSince1970: 100), sessions: [row("a", time: 90)])
    try SnapshotStore.write(snapshot, to: url)
    XCTAssertEqual(try SnapshotStore.read(from: url), snapshot)
    XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970: 125)))
    XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 131)))
    let permissions =
      try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    XCTAssertEqual(permissions?.intValue, 0o600)
  }

  func testLogEmitsOnlyChangesAndRemovals() {
    var changes = ActivityChanges()
    let first = ActivitySnapshot(sessions: [row("a", time: 10)])
    XCTAssertEqual(changes.consume(first).map(\.kind), ["opened"])
    XCTAssertEqual(changes.consume(first).count, 0)
    XCTAssertEqual(changes.consume(.init(sessions: [row("a", time: 20)])).map(\.kind), ["activity"])
    XCTAssertEqual(changes.consume(.init(sessions: [])).map(\.kind), ["removed"])
  }

  func testSubprocessDrainsLargeOutputAndBoundsTimeout() throws {
    let client = try BridgeClient(path: "/bin/sh")
    let data = try client.run(["-c", "head -c 100000 /dev/zero"], timeout: 2)
    XCTAssertEqual(data.count, 100000)
    let start = Date()
    XCTAssertThrowsError(try client.run(["-c", "exec sleep 5"], timeout: 0.1))
    XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    XCTAssertThrowsError(try client.run(["-c", "exit 7"]))
  }

  private func row(_ id: String, project: String = "p", time: TimeInterval) -> ActivitySession {
    .init(
      id: id, projectID: project, project: project, title: id,
      activityAt: Date(timeIntervalSince1970: time))
  }

  private func decode(_ fixture: [String: Any]) throws -> BridgeSnapshot {
    try BridgeSnapshot.decode(JSONSerialization.data(withJSONObject: fixture))
  }

  private func snapshotJSON() -> [String: Any] {
    [
      "schemaVersion": 1, "capturedAt": "2026-10-29T11:00:00.123456Z", "historyTruncated": false,
      "runtime": ["available": true, "data": ["runtimeId": "runtime"]],
      "sessions": [
        "available": true,
        "data": [
          [
            "id": "local:codex:synthetic", "title": "Synthetic task", "agent": "codex",
            "liveState": "live",
            "updatedAt": "1970-01-01T00:01:40Z", "cwd": "/synthetic/alpha",
            "liveBindings": [
              ["terminal": "term-one", "incarnationId": "inc-one", "runtimeId": "runtime"]
            ],
            "workspaceContexts": [["projectId": "project-one", "projectName": "Alpha"]],
          ]
        ],
      ],
      "projects": [
        "available": true,
        "data": [["id": "project-one", "displayName": "Alpha", "sourceRepoIds": ["repo-one"]]],
      ],
      "repositories": [
        "available": true,
        "data": [["id": "repo-one", "displayName": "Alpha", "path": "/synthetic/alpha"]],
      ],
      "terminals": [
        "available": true,
        "data": [
          [
            "handle": "term-one", "incarnationId": "inc-one",
            "worktreeId": "repo-one::/synthetic/alpha", "connected": true, "agentIdentity": "codex",
          ]
        ],
      ],
      "tabs": [
        "available": true,
        "data": [
          [
            "id": "tab-one", "terminal": "term-one", "incarnationId": "inc-one",
            "title": "Synthetic task", "worktreeId": "repo-one::/synthetic/alpha",
            "agentStatus": ["state": "working", "updatedAt": 200000, "agentType": "codex"],
          ]
        ],
      ],
    ]
  }
}
