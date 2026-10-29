import Darwin
import Foundation
import OrcaWatchCore

public enum TerminalText {
  private static let localeReady: Void = {
    setlocale(LC_CTYPE, "")
    return ()
  }()

  public static func cells(_ value: String) -> Int {
    _ = localeReady
    return DisplayText.clean(value).reduce(0) { $0 + cellWidth($1) }
  }

  public static func fit(_ value: String, width: Int, right: Bool = false) -> String {
    guard width > 0 else { return "" }
    _ = localeReady
    let clean = DisplayText.clean(value)
    let overflow = cells(clean) > width
    let limit = overflow ? width - 1 : width
    var used = 0
    var text = ""
    for character in clean {
      let size = cellWidth(character)
      guard used + size <= limit else { break }
      if size > 0 {
        text.append(character)
        used += size
      }
    }
    if overflow {
      text += "…"
      used += 1
    }
    let padding = String(repeating: " ", count: max(0, width - used))
    return right ? padding + text : text + padding
  }

  private static func cellWidth(_ character: Character) -> Int {
    let scalars = character.unicodeScalars
    if scalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) {
      return 2
    }
    return max(0, scalars.map { Int(wcwidth(Int32($0.value))) }.max() ?? 0)
  }
}

public enum TableField: String, CaseIterable {
  case session = "SESSION"
  case state = "STATE"
  case agent = "AGENT"
  case project = "PROJECT"
  case branch = "BRANCH"
  case model = "MODEL"
  case age = "AGE ↑"
}

public struct TableColumn {
  public var field: TableField
  public var width: Int
}

public struct TableLayout {
  public let columns: [TableColumn]
  public let width: Int

  public init(width: Int) {
    self.width = max(1, width)
    let available = max(1, self.width - 2)
    var widths: [TableField: Int] = [:]
    if available >= 28 { widths[.age] = 7 }
    if available >= 38 { widths[.state] = 9 }
    for (field, size) in [(TableField.agent, 8), (.project, 16), (.branch, 18), (.model, 18)] {
      let remaining = available - 3 - widths.values.reduce(0, +) - (widths.count + 1) * 3 - size
      if remaining >= 18 { widths[field] = size }
    }
    widths[.session] = max(1, available - 3 - widths.values.reduce(0, +) - widths.count * 3)
    columns = TableField.allCases.compactMap { field in
      widths[field].map { TableColumn(field: field, width: $0) }
    }
  }
}
