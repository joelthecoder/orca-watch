import AppKit
import OrcaWatchCore
import SwiftUI

@MainActor
final class WidgetHostDelegate: NSObject, NSApplicationDelegate {
  private let collector = Collector()

  func applicationDidFinishLaunching(_ notification: Notification) { collector.start() }

  func applicationWillTerminate(_ notification: Notification) { collector.stop() }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard let id = SessionLink.id(from: url) else { continue }
      Task { await collector.focus(id: id) }
    }
  }
}

@main
enum WidgetHost {
  @MainActor
  static func main() {
    if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
      CommandLine.arguments.count > index + 1
    {
      PreviewExporter.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
      return
    }
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let delegate = WidgetHostDelegate()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
  }
}

@MainActor
enum PreviewExporter {
  static func write(to directory: URL) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for (name, width, height, limit, compact) in [
        ("small", 170, 170, 3, true), ("medium", 360, 170, 3, true), ("large", 360, 380, 6, false),
      ] {
        let renderer = ImageRenderer(
          content: ActivityCard(snapshot: Demo.snapshot(), limit: limit, compact: compact)
            .padding(16).frame(width: CGFloat(width), height: CGFloat(height))
            .background(Color(red: 0.045, green: 0.09, blue: 0.12)).environment(
              \.colorScheme, .dark))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: directory.appendingPathComponent("widget-\(name).png"))
      }
    } catch {
      FileHandle.standardError.write(
        Data("Preview export failed: \(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }
}
