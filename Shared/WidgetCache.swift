import Foundation
import OrcaWatchCore

enum WidgetCache {
  static let kind = "OrcaWatchActivity"

  static func url() throws -> URL {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "OrcaWatchAppGroup") as? String,
      !group.hasPrefix("."),
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else {
      throw CacheError.unavailable
    }
    return container.appendingPathComponent("activity.json")
  }

  enum CacheError: Error, LocalizedError {
    case unavailable
    var errorDescription: String? {
      "Shared widget container unavailable. Build app and widget with the same development team."
    }
  }
}
