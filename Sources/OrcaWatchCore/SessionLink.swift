import Foundation

public enum SessionLink {
  public static func url(for id: String) -> URL {
    var components = URLComponents()
    components.scheme = "orcawatch"
    components.host = "session"
    components.queryItems = [URLQueryItem(name: "id", value: id)]
    return components.url!
  }

  public static func id(from url: URL) -> String? {
    guard url.scheme == "orcawatch", url.host == "session",
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      items.filter({ $0.name == "id" }).count == 1,
      let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty
    else { return nil }
    return id
  }
}
