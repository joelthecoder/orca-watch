import Darwin
import Foundation
import OrcaWatchCore

enum Key: Equatable {
  case up, down, left, right, enter, escape, backspace
  case character(String)
  case quit
}

final class Terminal {
  private var original = termios()
  private var previous: [String] = []
  private var input: [UInt8] = []
  private var escapeSince: Date?
  let color: Bool

  init(color: Bool) throws {
    self.color = color
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
    return (max(20, Int(dimensions.ws_col)), max(6, Int(dimensions.ws_row)))
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
        if input.count >= 3, input[1] == 91 || input[1] == 79 {
          let key: Key? = [65: .up, 66: .down, 67: .right, 68: .left][input[2]]
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
      case 3, 4: keys.append(.quit)
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
    if !output.isEmpty { write(output) }
  }

  func invalidate() { previous = [] }

  func style(_ text: String, _ code: String) -> String {
    color ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
  }

  func projectStyle(_ text: String, id: String, selected: Bool) -> String {
    let colors = [80, 111, 183, 215, 211, 150]
    return style(text, "\(selected ? "7;" : "")38;5;\(colors[ProjectColor.index(for: id)])")
  }

  func fit(_ text: String, width: Int) -> String {
    var used = 0
    var result = ""
    for character in DisplayText.clean(text) {
      let cells = max(
        1, character.unicodeScalars.map { max(0, Int(wcwidth(Int32($0.value)))) }.max() ?? 1)
      if used + cells > width { break }
      result.append(character)
      used += cells
    }
    return result + String(repeating: " ", count: max(0, width - used))
  }

  private func write(_ value: String) { FileHandle.standardOutput.write(Data(value.utf8)) }
}
