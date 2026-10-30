import Darwin
import Foundation
import OrcaWatchCore

enum Key: Equatable {
  case up, down, left, right, enter, escape, backspace, pageUp, pageDown, halfPageUp, halfPageDown,
    home, end, redraw
  case character(String)
  case quit
}

final class Terminal {
  private var original = termios()
  private var previous: [String] = []
  private var input: [UInt8] = []
  private var escapeSince: Date?
  init() throws {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1,
      ProcessInfo.processInfo.environment["TERM"] != "dumb"
    else {
      throw CLIError.message(
        "Interactive watch requires a terminal. Use 'orca-watch snapshot' or 'orca-watch log --json'."
      )
    }
    guard tcgetattr(STDIN_FILENO, &original) == 0 else {
      throw CLIError.message("Cannot read terminal settings.")
    }
    var raw = original
    cfmakeraw(&raw)
    guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
      throw CLIError.message("Cannot enter terminal mode.")
    }
    setlocale(LC_CTYPE, "")
    write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J")
  }

  func restore() {
    tcsetattr(STDIN_FILENO, TCSANOW, &original)
    write("\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
  }

  var size: (width: Int, height: Int) {
    var dimensions = winsize()
    _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &dimensions)
    return (max(1, Int(dimensions.ws_col)), max(1, Int(dimensions.ws_row)))
  }

  func readKeys() -> [Key] {
    var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    if poll(&descriptor, 1, 50) > 0 {
      if descriptor.revents & Int16(POLLHUP | POLLERR) != 0 { return [.quit] }
      var buffer = [UInt8](repeating: 0, count: 256)
      let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
      if count == 0 { return [.quit] }
      if count > 0 { input += buffer.prefix(count) }
    }
    var keys: [Key] = []
    while let first = input.first {
      if first == 27 {
        if input.count >= 3, input[1] == 91, (48...57).contains(input[2]) {
          if input.count < 4 {
            if escapeSince == nil { escapeSince = Date() }
            if Date().timeIntervalSince(escapeSince!) < 0.08 { break }
          } else if input[3] == 126 {
            let key: Key? = [49: .home, 52: .end, 53: .pageUp, 54: .pageDown, 55: .home, 56: .end][
              input[2]]
            input.removeFirst(4)
            escapeSince = nil
            if let key { keys.append(key) }
            continue
          }
        }
        if input.count >= 3, input[1] == 91 || input[1] == 79 {
          let key: Key? = [65: .up, 66: .down, 67: .right, 68: .left, 72: .home, 70: .end][input[2]]
          input.removeFirst(3)
          escapeSince = nil
          if let key { keys.append(key) }
          continue
        }
        if input.count < 3, Date().timeIntervalSince(escapeSince ?? Date()) < 0.08 {
          if escapeSince == nil { escapeSince = Date() }
          break
        }
        input.removeFirst()
        escapeSince = nil
        keys.append(.escape)
        continue
      }
      input.removeFirst()
      switch first {
      case 3: keys.append(.quit)
      case 4: keys.append(.halfPageDown)
      case 21: keys.append(.halfPageUp)
      case 12: keys.append(.redraw)
      case 10, 13: keys.append(.enter)
      case 8, 127: keys.append(.backspace)
      case 32...126: keys.append(.character(String(UnicodeScalar(first))))
      default: break
      }
    }
    return keys
  }

  func paint(_ lines: [String]) {
    var output = ""
    for index in 0..<max(lines.count, previous.count) {
      let line = index < lines.count ? lines[index] : ""
      if index >= previous.count || previous[index] != line {
        output += "\u{1B}[\(index + 1);1H\u{1B}[2K\(line)"
      }
    }
    previous = lines
    if !output.isEmpty { write(output + "\u{1B}[1;1H") }
  }

  func invalidate() { previous = [] }

  private func write(_ value: String) { FileHandle.standardOutput.write(Data(value.utf8)) }
}
