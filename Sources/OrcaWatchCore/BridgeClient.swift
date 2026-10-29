import Darwin
import Foundation

public enum BridgeError: Error, LocalizedError {
  case missingExecutable
  case unsupportedSchema(Int)
  case unavailable
  case timedOut
  case failed(Int32, String)
  case oversized
  case cancelled

  public var errorDescription: String? {
    switch self {
    case .missingExecutable:
      return "orca-bridge not found. Set ORCA_WATCH_BRIDGE to its absolute path."
    case .unsupportedSchema(let version): return "Unsupported Bridge snapshot schema: \(version)"
    case .unavailable:
      return "Live Orca inventory unavailable. Open Orca and check orca-bridge doctor."
    case .timedOut: return "Orca Bridge timed out. Retrying on the next refresh."
    case .failed(let code, let message): return "Bridge exited \(code): \(message)"
    case .oversized: return "Bridge output exceeded 32 MiB."
    case .cancelled: return "Bridge request cancelled."
    }
  }
}

public final class BridgeClient {
  public let executable: URL
  private let lock = NSLock()
  private var processes: [UUID: Process] = [:]
  private var cancelled = false

  public func cancel() {
    lock.lock()
    cancelled = true
    let running = Array(processes.values)
    lock.unlock()
    for process in running where process.isRunning {
      process.terminate()
      let deadline = Date().addingTimeInterval(0.5)
      while process.isRunning && Date() < deadline { usleep(10000) }
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      process.waitUntilExit()
    }
  }

  public init(path: String? = nil) throws {
    let environment = ProcessInfo.processInfo.environment
    if let explicit = path ?? environment["ORCA_WATCH_BRIDGE"] {
      guard explicit.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: explicit) else {
        throw BridgeError.missingExecutable
      }
      executable = URL(fileURLWithPath: explicit)
      return
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let directories =
      (environment["PATH"] ?? "").split(separator: ":").map(String.init)
      + ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
    guard
      let candidate = directories.map({ "\($0)/orca-bridge" }).first(where: {
        FileManager.default.isExecutableFile(atPath: $0)
      })
    else { throw BridgeError.missingExecutable }
    executable = URL(fileURLWithPath: candidate)
  }

  public func snapshot() throws -> ActivitySnapshot {
    try ActivitySnapshot.project(
      BridgeSnapshot.decode(run(["snapshot", "--limit", "2000", "--json"])))
  }

  public func focus(_ session: ActivitySession) throws {
    _ = try run(["terminals", "focus", session.terminal, "--json"])
  }

  public func run(_ arguments: [String], timeout: TimeInterval = 10) throws -> Data {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent(
      "orca-watch-\(UUID().uuidString)")
    try manager.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? manager.removeItem(at: directory) }
    let output = directory.appendingPathComponent("stdout")
    let errors = directory.appendingPathComponent("stderr")
    manager.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
    manager.createFile(atPath: errors.path, contents: nil, attributes: [.posixPermissions: 0o600])
    let outputHandle = try FileHandle(forWritingTo: output)
    let errorHandle = try FileHandle(forWritingTo: errors)
    defer {
      try? outputHandle.close()
      try? errorHandle.close()
    }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = outputHandle
    process.standardError = errorHandle
    process.standardInput = FileHandle.nullDevice
    let completed = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in completed.signal() }
    let requestID = UUID()
    lock.lock()
    if cancelled {
      lock.unlock()
      throw BridgeError.cancelled
    }
    do {
      try process.run()
      processes[requestID] = process
      lock.unlock()
    } catch {
      lock.unlock()
      throw error
    }
    defer {
      lock.lock()
      processes.removeValue(forKey: requestID)
      lock.unlock()
    }
    if completed.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      if completed.wait(timeout: .now() + 0.5) == .timedOut {
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
      throw BridgeError.timedOut
    }
    let size = try manager.attributesOfItem(atPath: output.path)[.size] as? NSNumber
    guard (size?.intValue ?? 0) <= 32 * 1024 * 1024 else { throw BridgeError.oversized }
    if process.terminationStatus != 0 {
      let handle = try FileHandle(forReadingFrom: errors)
      defer { try? handle.close() }
      let errorData = try handle.read(upToCount: 1024) ?? Data()
      let message = DisplayText.clean(String(decoding: errorData, as: UTF8.self))
      throw BridgeError.failed(process.terminationStatus, message)
    }
    return try Data(contentsOf: output)
  }
}
